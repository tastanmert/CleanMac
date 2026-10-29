import Foundation
import Security

/// Finds third-party apps and the support files they leave behind in ~/Library.
public struct Uninstaller: Sendable {
    public enum Source: String, Sendable, CaseIterable {
        case appStore = "App Store", setapp = "Setapp", steam = "Steam", battleNet = "Battle.net", other = "Diğer"
    }

    public struct App: Identifiable, Sendable, Hashable {
        public var id: URL { url }
        public let url: URL
        public let name: String
        public let bundleID: String
        public var size: Int64
        /// When the app was last opened (Spotlight); nil if it never was or Spotlight does not know.
        public let lastUsed: Date?
        public let isAppStore: Bool
        /// Second part of the bundle identifier, as a readable developer label ("com.figma.Desktop" → "Figma").
        public var vendor: String {
            let parts = bundleID.split(separator: ".")
            guard parts.count >= 2 else { return bundleID }
            return parts[1].prefix(1).uppercased() + parts[1].dropFirst()
        }

        /// Not opened for six months, or never opened in the two weeks since it arrived.
        public func isUnused(now: Date = .now) -> Bool {
            // Spotlight may simply not know (helpers, apps opened from the command line): then go by when the
            // app arrived, so a fresh install is not called unused.
            if let lastUsed { return now.timeIntervalSince(lastUsed) > 180 * 86_400 }
            // Never opened: unused once it has had two weeks to be.
            guard let installed else { return false }
            return now.timeIntervalSince(installed) > 14 * 86_400
        }

        /// When the app was put on this Mac (Spotlight's date added, else the bundle's modification date).
        public var installed: Date? = nil
        /// Where the app came from, for the Uninstaller's "Kaynak" filters.
        public var source: Source = .other
        /// No valid Developer ID or App Store signature: unsigned, ad-hoc or broken. Worth a look.
        public var isUnsigned = false
        /// A menu-bar agent or URL handler without a Dock presence: nobody "opens" it, so it is never unused.
        public var isBackground = false

        /// Unused, and not kept alive by something running: an open app, or a sibling from the same
        /// developer (Karabiner's settings app while its daemon runs), is in use whatever Spotlight says.
        public func isUnused(now: Date = .now, runningBundleIDs: Set<String>) -> Bool {
            guard !isBackground, isUnused(now: now), !runningBundleIDs.contains(bundleID) else { return false }
            let family = bundleID.split(separator: ".").prefix(2).joined(separator: ".")
            guard !bundleID.hasPrefix("com.apple.") else { return true }
            return !runningBundleIDs.contains { $0.hasPrefix(family + ".") }
        }
    }

    public let home: URL
    let guardian: SafetyGuard

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        guardian = SafetyGuard(home: home)
    }

    /// Apps in /Applications and ~/Applications that are not Apple's. Sizes are left at 0 so the
    /// list appears at once; fill them with `size(of:)`.
    @concurrent
    public func installedApps() async -> [App] {
        let roots = [URL(filePath: "/Applications"), home.appending(path: "Applications"),
                     home.appending(path: "Library/Application Support/Steam/steamapps/common")]
        // Apps directly in a root, plus one plain folder down (Setapp, Battle.net games, Steam games).
        let bundles = roots.flatMap { root -> [URL] in
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            return children.flatMap { child -> [URL] in
                if child.pathExtension == "app" { return [child] }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      child.lastPathComponent != "Utilities" else { return [] }
                return ((try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.pathExtension == "app" }
            }
        }
        return await withTaskGroup(of: App?.self) { group in
            for url in bundles {
                group.addTask {
                    guard guardian.isAllowed(url, policy: .application),
                          let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    let metadata = NSMetadataItem(url: url)
                    let lastUsed = metadata?.value(forAttribute: "kMDItemLastUsedDate") as? Date
                    let installed = (metadata?.value(forAttribute: "kMDItemDateAdded") as? Date)
                        ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    let isAppStore = FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path)
                    let info = bundle.infoDictionary ?? [:]
                    let background = (info["LSUIElement"] as? Bool ?? false) || (info["LSBackgroundOnly"] as? Bool ?? false)
                        || (info["LSUIElement"] as? String) == "1"
                    return App(url: url, name: name, bundleID: id, size: 0, lastUsed: lastUsed, isAppStore: isAppStore,
                               installed: installed,
                               source: Self.source(of: url, bundleID: id, isAppStore: isAppStore),
                               isUnsigned: !isAppStore && !Self.hasTrustedSignature(url), isBackground: background)
                }
            }
            return await group.reduce(into: [App]()) { if let app = $1 { $0.append(app) } }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func source(of url: URL, bundleID: String, isAppStore: Bool) -> Source {
        let path = url.path
        if isAppStore { return .appStore }
        if path.contains("/Setapp/") || bundleID.hasSuffix("-setapp") { return .setapp }
        if path.contains("/steamapps/") || bundleID == "com.valvesoftware.steam" { return .steam }
        if bundleID.hasPrefix("net.battle") || bundleID.hasPrefix("com.blizzard") { return .battleNet }
        return .other
    }

    /// Signed by an identity Apple vouches for (Developer ID or Apple). Resources are not re-hashed: this is
    /// about who signed, not a full integrity check, and stays fast for big apps.
    static func hasTrustedSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess else { return true }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), requirement) == errSecSuccess
    }

    @concurrent
    public static func size(of app: App) async -> Int64 {
        Scanner.allocatedSize(of: app.url)
    }

    /// The app itself plus every support file that matches its bundle identifier or name.
    @concurrent
    public func items(for app: App) async -> [CleanItem] {
        let appSize = app.size > 0 ? app.size : Scanner.allocatedSize(of: app.url)
        var items = [CleanItem(title: app.name, detail: app.url.path, size: appSize,
                               action: .trash(app.url), isSelected: true, policy: .application)]
        for url in leftovers(bundleID: app.bundleID, appName: app.url.deletingPathExtension().lastPathComponent) {
            let sure = Self.isExactly(url, bundleID: app.bundleID)
            items.append(CleanItem(title: url.lastPathComponent,
                                   detail: url.path.replacingOccurrences(of: home.path, with: "~")
                                       + (sure ? "" : String(localized: " · adı benziyor, başka bir uygulamanın olabilir")),
                                   size: Scanner.allocatedSize(of: url),
                                   action: .trash(url), isSelected: sure, policy: .appLeftover))
        }
        return items
    }

    /// Named after the bundle id itself (`com.x.app`, `com.x.app.plist`, `TEAM.com.x.app`), not a sibling such as
    /// `com.x.app.canary` or a folder that merely shares the app's name (Steam's whole game library): those are listed unticked.
    static func isExactly(_ url: URL, bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        let entry = url.lastPathComponent.lowercased()
        let suffixes = ["", ".plist", ".savedstate", ".binarycookies"]
        return suffixes.contains { entry == id + $0 } || entry.hasSuffix("." + id)
    }

    func leftovers(bundleID: String, appName: String) -> [URL] {
        let id = bundleID.lowercased()
        let name = appName.lowercased()
        return guardian.leftoverRoots.flatMap { root -> [URL] in
            let children = (try? FileManager.default.contentsOfDirectory(at: URL(filePath: root), includingPropertiesForKeys: nil)) ?? []
            return children.filter { url in
                let entry = url.lastPathComponent.lowercased()
                let matchesID = entry == id || entry.hasPrefix(id + ".") || entry.hasSuffix("." + id)
                // Names are only trusted when distinctive enough not to hit another app's folder.
                let matchesName = name.count >= 4 && entry == name
                return (matchesID || matchesName) && guardian.isAllowed(url, policy: .appLeftover)
            }
        }
    }
}
