import Foundation

/// Read-only update check: Sparkle appcasts (the feed the app itself would ask), Homebrew casks and
/// macOS. CleanMac never installs anything itself; it hands the update to the app, Homebrew or Settings.
public enum Updater {
    public enum Source: String, Sendable { case sparkle, homebrew, system }

    public struct Update: Identifiable, Sendable, Hashable {
        public var id: String { source.rawValue + name }
        public let name: String
        public let current: String
        public let latest: String
        public let source: Source
        public let app: URL?
        /// For Homebrew: the cask token to upgrade.
        public let token: String?
    }

    public static func check(applications: [URL] = defaultApplications()) async -> [Update] {
        async let sparkle = sparkleUpdates(applications)
        async let brew = homebrewUpdates()
        async let system = systemUpdates()
        let all = await sparkle + brew + system
        // An app found in both Homebrew and Sparkle is listed once, as Homebrew manages it.
        let brewNames = Set(all.filter { $0.source == .homebrew }.map { $0.name.lowercased() })
        return all.filter { $0.source != .sparkle || !brewNames.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func defaultApplications() -> [URL] {
        let roots = [URL(filePath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
        return roots.flatMap { ((try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []) }
            .filter { $0.pathExtension == "app" }
    }

    // MARK: Sparkle

    static func sparkleUpdates(_ apps: [URL]) async -> [Update] {
        await withTaskGroup(of: Update?.self) { group in
            for app in apps {
                guard let info = Bundle(url: app)?.infoDictionary,
                      let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme == "https" else { continue }
                let short = info["CFBundleShortVersionString"] as? String ?? ""
                let build = info["CFBundleVersion"] as? String ?? short
                let name = app.deletingPathExtension().lastPathComponent
                group.addTask {
                    var request = URLRequest(url: feed, timeoutInterval: 12)
                    request.setValue("CleanMac update check", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: request),
                          let latest = Appcast.latest(in: data) else { return nil }
                    guard isNewer(latest.build, than: build) else { return nil }
                    return Update(name: name, current: short, latest: latest.short ?? latest.build,
                                  source: .sparkle, app: app, token: nil)
                }
            }
            return await group.reduce(into: []) { if let u = $1 { $0.append(u) } }
        }
    }

    // MARK: Homebrew

    static func homebrewUpdates() async -> [Update] {
        let result = await Shell.login("command -v brew >/dev/null && brew outdated --cask --json=v2")
        guard result.status == 0 else { return [] }
        return parseBrew(Data(result.output.utf8))
    }

    static func parseBrew(_ data: Data) -> [Update] {
        struct Output: Decodable {
            struct Cask: Decodable { let name: String; let installed_versions: [String]; let current_version: String }
            let casks: [Cask]
        }
        // brew may print notices before the JSON.
        guard let start = data.firstIndex(of: UInt8(ascii: "{")),
              let output = try? JSONDecoder().decode(Output.self, from: data[start...]) else { return [] }
        return output.casks.map {
            Update(name: $0.name, current: $0.installed_versions.last ?? "", latest: $0.current_version,
                   source: .homebrew, app: nil, token: $0.name)
        }
    }

    // MARK: macOS

    static func systemUpdates() async -> [Update] {
        let result = await Shell.run("/usr/sbin/softwareupdate", ["--list", "--no-scan"])
        return parseSoftwareUpdate(result.output)
    }

    /// Lines look like: "\tTitle: macOS Tahoe 27.0.2, Version: 27.0.2, Size: …"
    static func parseSoftwareUpdate(_ output: String) -> [Update] {
        output.split(separator: "\n").compactMap { line in
            guard line.contains("Title:"), let title = line.split(separator: ",").first?.split(separator: ":").last else { return nil }
            let version = line.split(separator: ",").first { $0.contains("Version:") }?.split(separator: ":").last
            return Update(name: title.trimmingCharacters(in: .whitespaces), current: ProcessInfo.processInfo.operatingSystemVersionString,
                          latest: version.map { $0.trimmingCharacters(in: .whitespaces) } ?? "", source: .system, app: nil, token: nil)
        }
    }

    // MARK: Versions

    /// Compares dotted versions numerically ("1.10" > "1.9"); non-numeric parts compare as text.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(whereSeparator: { ".-_ ".contains($0) }), b = current.split(whereSeparator: { ".-_ ".contains($0) })
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? String(a[i]) : "0", y = i < b.count ? String(b[i]) : "0"
            if let xi = Int(x), let yi = Int(y) {
                if xi != yi { return xi > yi }
            } else if x != y {
                return x.compare(y, options: .numeric) == .orderedDescending
            }
        }
        return false
    }
}

/// The newest stable item in a Sparkle appcast that runs on this macOS.
enum Appcast {
    struct Entry { var build = ""; var short: String?; var minimumSystem: String?; var channel: String? }

    static func latest(in data: Data, system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> (build: String, short: String?)? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        let os = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        let usable = delegate.entries.filter { entry in
            !entry.build.isEmpty && entry.channel == nil
                && (entry.minimumSystem.map { !Updater.isNewer($0, than: os) } ?? true)
        }
        guard let best = usable.max(by: { Updater.isNewer($1.build, than: $0.build) }) else { return nil }
        return (best.build, best.short)
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []
        var current: Entry?
        var text = ""
        var inDeltas = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "item": current = Entry()
            case "sparkle:deltas": inDeltas = true
            case "enclosure" where !inDeltas:
                if let v = attributes["sparkle:version"], current?.build.isEmpty == true { current?.build = v }
                if let s = attributes["sparkle:shortVersionString"], current?.short == nil { current?.short = s }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version": current?.build = value
            case "sparkle:shortVersionString": current?.short = value
            case "sparkle:minimumSystemVersion": current?.minimumSystem = value
            case "sparkle:channel": current?.channel = value
            case "sparkle:deltas": inDeltas = false
            case "item": if let c = current { entries.append(c) }; current = nil
            default: break
            }
        }
    }
}
