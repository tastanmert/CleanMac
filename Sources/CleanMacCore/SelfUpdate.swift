import Foundation

/// CleanMac's own updates, from the public GitHub repository's latest release (no account or tool needed).
public enum SelfUpdate {
    public static let repo = "tastanmert/CleanMac"

    public struct Release: Sendable, Equatable {
        public let version: String
        public let tag: String
        public let notes: String
        public let date: Date?
        /// The release's DMG.
        public let download: URL?
    }

    public enum Check: Sendable, Equatable {
        case upToDate(latest: String)
        case available(Release)
        /// Offline, rate-limited or no release yet; the reason is shown as is.
        case unavailable(String)
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case download(String), notAnUpdate(String), notWritable(String)
        public var description: String {
            switch self {
            case .download(let why): String(localized: "İndirilemedi: \(why)")
            case .notAnUpdate(let why): String(localized: "İndirilen paket kurulmadı: \(why)")
            case .notWritable(let path): String(localized: "\(path) klasörüne yazılamıyor; DMG'den elle kur.")
            }
        }
    }

    public static func check(current: String) async -> Check {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            return .unavailable(reason(status: nil))
        }
        guard status == 200 else { return .unavailable(reason(status: status)) }
        guard let release = parse(data) else { return .unavailable(String(localized: "Sürüm bilgisi okunamadı.")) }
        return Updater.isNewer(release.version, than: current) ? .available(release) : .upToDate(latest: release.version)
    }

    /// GitHub's `releases/latest` JSON: tag, notes, date and the first DMG asset.
    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let date = (json["published_at"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        let dmg = (json["assets"] as? [[String: Any]])?
            .first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
        return Release(version: version, tag: tag, notes: json["body"] as? String ?? "", date: date,
                       download: dmg.flatMap(URL.init(string:)))
    }

    static func reason(status: Int?) -> String {
        switch status {
        case 404?: String(localized: "Henüz yayınlanmış sürüm yok.")
        case 403?, 429?: String(localized: "GitHub şu an çok sık soruldu; biraz sonra yeniden dene.")
        case nil: String(localized: "GitHub'a ulaşılamadı. İnternet bağlantını kontrol et.")
        default: String(localized: "GitHub yanıt vermedi (\(status!)).")
        }
    }

    /// Downloads the release's DMG and copies the app out of it, then checks it really is the update:
    /// same bundle id, the announced version, a valid signature. Returns the staged app.
    public static func prepare(_ release: Release, bundleID: String) async throws(Failure) -> URL {
        guard let source = release.download, source.scheme == "https", source.host() == "github.com" else {
            throw .download(String(localized: "Sürümde DMG yok"))
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "CleanMacUpdate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dmg = folder.appending(path: "CleanMac.dmg")
        do {
            let (file, response) = try await URLSession.shared.download(from: source)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: file, to: dmg)
        } catch {
            throw .download(String(localized: "bağlantı kesildi"))
        }
        let mount = folder.appending(path: "mnt")
        let attach = await Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path],
                                     timeout: 120)
        guard attach.status == 0 else { throw .download(String(localized: "DMG açılamadı")) }
        let staged = folder.appending(path: "CleanMac.app")
        let copy = await Shell.run("/usr/bin/ditto", [mount.appending(path: "CleanMac.app").path, staged.path], timeout: 300)
        _ = await Shell.run("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 60)
        guard copy.status == 0 else { throw .download(String(localized: "Uygulama DMG'den kopyalanamadı")) }
        try await verify(staged, bundleID: bundleID, version: release.version)
        return staged
    }

    static func verify(_ app: URL, bundleID: String, version: String) async throws(Failure) {
        let info = Bundle(url: app)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == bundleID else { throw .notAnUpdate(String(localized: "başka bir uygulama")) }
        guard info?["CFBundleShortVersionString"] as? String == version else { throw .notAnUpdate(String(localized: "sürüm numarası tutmuyor")) }
        let signature = await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120)
        guard signature.status == 0 else { throw .notAnUpdate(String(localized: "imza geçersiz")) }
    }

    /// Hands over to a small script that waits for this process to quit, moves the running copy to the Trash
    /// (nothing is deleted for good), puts the new one in its place and opens it.
    public static func install(_ staged: URL, replacing current: URL) throws(Failure) {
        let parent = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isWritableFile(atPath: current.path) else {
            throw .notWritable(parent.path)
        }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
        let script = installScript(staged: staged, current: current, trash: trash, pid: getpid(), relaunch: true)
        let file = staged.deletingLastPathComponent().appending(path: "install.sh")
        do { try script.write(to: file, atomically: true, encoding: .utf8) } catch { throw .download(String(localized: "Kurulum betiği yazılamadı")) }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        // nohup and & detach it, so it outlives this app.
        process.arguments = ["-c", "/usr/bin/nohup /bin/zsh \(Shell.quote(file.path)) >/dev/null 2>&1 &"]
        do { try process.run() } catch { throw .download(String(localized: "Kurulum başlatılamadı")) }
        process.waitUntilExit()
    }

    static func installScript(staged: URL, current: URL, trash: URL, pid: Int32, relaunch: Bool) -> String {
        let old = Shell.quote(current.path), new = Shell.quote(staged.path)
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let aside = Shell.quote(trash.appending(path: String(localized: "CleanMac (eski) \(stamp).app")).path)
        return """
        #!/bin/zsh
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/mkdir -p \(Shell.quote(trash.path))
        /bin/mv \(old) \(aside) || exit 1
        if ! /usr/bin/ditto \(new) \(old); then /bin/rm -rf \(old); /bin/mv \(aside) \(old); fi
        /usr/bin/xattr -dr com.apple.quarantine \(old) 2>/dev/null
        \(relaunch ? "/usr/bin/open \(old)" : "")
        /bin/rm -rf \(Shell.quote(staged.deletingLastPathComponent().path))
        """
    }
}
