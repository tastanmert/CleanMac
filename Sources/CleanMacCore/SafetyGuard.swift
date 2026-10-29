import Foundation

/// Every path is checked here before it is moved to the Trash.
///
/// Each item carries a `Policy` that says why it may be removed:
/// - `junk`: found automatically by a rule; must sit strictly inside a known cache/log/build root.
/// - `userFile`: picked by the user (space map, duplicates); any file in the home folder or /Users/Shared except
///   ~/Library, credential folders, library packages (Photos, Music) and the standard folders themselves.
/// - `application`: an .app directly inside /Applications or ~/Applications that is not Apple's.
/// - `appLeftover`: a direct child of the Library folders where apps keep support files.
/// - `appSupportCache`: a known cache folder (Cache, GPUCache, logs…) exactly two levels inside
///   ~/Library/Application Support, i.e. Application Support/<App>/<cache folder>.
///
/// - `containerCache`: something inside a sandboxed app's own Caches or Logs folder
///   (Containers/<id>/Data/Library/Caches|Logs, Group Containers/<id>/Library/Caches), never Apple's.
/// - `tempFile`: a direct child of this user's temporary folder (/private/var/folders/…/T).
/// - `systemAdmin`: root-owned junk: a child of /Library/Caches (not Apple's) or /Users/Deleted Users,
///   or a file inside /Library/Logs or /private/var/log. Moved with an administrator prompt.
/// - `knownData`: a direct child of a few known app data folders (iOS backups, Mail Downloads, Spotify's
///   stream cache, Adobe's media cache, simulator caches, iOS device logs).
///
/// - `launchItem`: a launch agent or daemon plist directly in /Library/LaunchAgents or /Library/LaunchDaemons,
///   never Apple's. Moved with an administrator prompt.
///
/// - `privacy`: exactly one of the browser history, cookie, session and recent-items files `Privacy` knows.
///
/// Mounted file systems on another volume (e.g. CoreDevice's DeviceFS) are always refused.
public struct SafetyGuard: Sendable {
    public enum Policy: Sendable, Hashable {
        case junk, userFile, application, appLeftover, appSupportCache, containerCache, tempFile, systemAdmin, knownData, privacy, darwinCache, aiTemp, launchItem
    }

    public enum Rejection: Error, Equatable, Sendable {
        case outsideAllowedRoots(String)
        case forbidden(String)
        case isRoot(String)
        case otherVolume(String)
        case appleApp(String)
    }

    public let home: URL
    let allowedRoots: [String]
    let forbidden: [String]
    let userForbidden: [String]
    let standardFolders: Set<String>
    let leftoverRoots: [String]
    let applicationRoots: [String]
    /// Steam installs each game in its own folder here.
    let steamCommon: String
    let appSupport: String
    let temporaryRoot: String
    let knownDataRoots: [String]
    /// This user's per-user cache folder under /var/folders (`confstr`), where clang, Metal and helper apps cache.
    let darwinCacheRoot: String
    /// AI tools' scratch folders in /tmp: `claude-<uid>/<project>/<session>`.
    let aiTempRoots: [String]
    static let systemAdminChildRoots = ["/Library/Caches", "/Users/Deleted Users"] + audioPluginKinds.map { "/Library/Audio/Plug-Ins/\($0)" }
    /// Audio plug-in folders under Library/Audio/Plug-Ins (Audio Units, VST, VST3, audio drivers).
    public static let audioPluginKinds = ["Components", "VST", "VST3", "HAL"]
    static let launchItemRoots = ["/Library/LaunchAgents", "/Library/LaunchDaemons"]
    static let systemAdminLogRoots = ["/Library/Logs", "/private/var/log", "/var/log"]   // Foundation drops /private when resolving
    /// Folder names Chromium/Electron apps rebuild on their own.
    public static let appSupportCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "ShaderCache", "CachedData", "CachedExtensionVSIXs", "logs",
    ]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                darwinCacheDirectory: URL = SafetyGuard.systemDarwinCacheDirectory,
                aiTempRoots: [String]? = nil) {
        let home = home.resolvingSymlinksInPath().standardizedFileURL
        self.home = home
        let h = home.path
        allowedRoots = [
            "\(h)/Library/Caches",
            "\(h)/Library/Logs",
            "\(h)/Library/Developer/Xcode/DerivedData",
            "\(h)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(h)/Library/Developer/Xcode/Archives",
            "\(h)/Library/Developer/CoreSimulator/Devices",
            "\(h)/.npm",
            "\(h)/.cache",
            "\(h)/Library/pnpm",
            "\(h)/.lmstudio/models",
            "\(h)/Library/Audio/Plug-Ins",
            "\(h)/Downloads",
            "\(h)/Movies",
        ]
        forbidden = [
            "\(h)/Library/Application Support",
            "\(h)/Library/Containers",
            "\(h)/Library/Group Containers",
            "\(h)/Library/Keychains",
            "\(h)/Library/Mail",
            "\(h)/Library/Messages",
            "\(h)/Library/Mobile Documents",
            "\(h)/Library/CloudStorage",
            "\(h)/Library/Developer/CoreDevice",
            "\(h)/Library/Logs/CleanMac",
            "\(h)/Documents",
            "\(h)/Desktop",
            "\(h)/Pictures",
            "\(h)/.ssh",
            "\(h)/.gnupg",
        ]
        userForbidden = [
            "\(h)/Library",
            "\(h)/.ssh",
            "\(h)/.gnupg",
            "\(h)/.aws",
            "\(h)/.kube",
            "\(h)/.Trash",
        ]
        standardFolders = Set(["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications", "Library"]
            .map { "\(h)/\($0)" })
        leftoverRoots = ["Application Support", "Caches", "Preferences", "Saved Application State", "Logs",
                         "HTTPStorages", "WebKit", "Containers", "Group Containers", "Application Scripts", "LaunchAgents"]
            .map { "\(h)/Library/\($0)" }
        applicationRoots = ["/Applications", "\(h)/Applications"]
        steamCommon = "\(h)/Library/Application Support/Steam/steamapps/common"
        appSupport = "\(h)/Library/Application Support"
        temporaryRoot = Self.normalized(temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL).path
        darwinCacheRoot = Self.normalized(darwinCacheDirectory.resolvingSymlinksInPath().standardizedFileURL).path
        // Foundation reports /private/tmp as /tmp once symlinks are resolved: accept both spellings.
        self.aiTempRoots = aiTempRoots ?? ["/private/tmp/claude-\(getuid())", "/tmp/claude-\(getuid())"]
        knownDataRoots = [
            "Library/Application Support/MobileSync/Backup",
            "Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "Library/Mail Downloads",
            "Library/Logs/CrashReporter/MobileDevice",
            "Library/Developer/Xcode/iOS Device Logs",
            "Library/Developer/CoreSimulator/Caches",
            "Library/Application Support/Spotify/PersistentCache",
            "Library/Application Support/Claude/vm_bundles",
            ".local/share/claude/versions",
            "Library/Application Support/Adobe/Common",
        ].map { "\(h)/\($0)" }
    }

    /// `getconf DARWIN_USER_CACHE_DIR`: /var/folders/xx/yyyy/C/.
    public static var systemDarwinCacheDirectory: URL {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        return length > 0 ? URL(filePath: String(cString: buffer)) : URL(filePath: "/var/empty")
    }

    /// The data volume is also mounted at /System/Volumes/Data; judge such paths by their usual form.
    static func normalized(_ url: URL) -> URL {
        let dataVolume = "/System/Volumes/Data"
        guard url.path.hasPrefix(dataVolume + "/") else { return url }
        return URL(filePath: String(url.path.dropFirst(dataVolume.count)))
    }

    /// Returns the resolved URL that is safe to move, or throws why it is not.
    @discardableResult
    public func validate(_ url: URL, policy: Policy = .junk) throws(Rejection) -> URL {
        // Resolve the parent, not the item: trashing a symlink moves the link itself.
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        // APFS ignores case but the comparisons below do not: take a real item's on-disk spelling (~/LIBRARY → ~/Library).
        let joined = parent.appendingPathComponent(url.lastPathComponent)
        let isLink = (try? joined.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
        let resolved = Self.normalized((isLink ? joined : joined.resolvingSymlinksInPath()).standardizedFileURL)
        let path = resolved.path
        let parentPath = resolved.deletingLastPathComponent().path

        switch policy {
        case .junk:
            if forbidden.contains(where: { Self.isInside(path, $0) || path == $0 }) { throw .forbidden(path) }
            if allowedRoots.contains(path) { throw .isRoot(path) }
            guard allowedRoots.contains(where: { Self.isInside(path, $0) }) else { throw .outsideAllowedRoots(path) }

        case .userFile:
            // The home folder, plus /Users/Shared which every user can write to (games, shared installers).
            guard Self.isInside(path, home.path) || Self.isInside(path, "/Users/Shared") else { throw .outsideAllowedRoots(path) }
            if standardFolders.contains(path) { throw .isRoot(path) }
            if userForbidden.contains(where: { Self.isInside(path, $0) || path == $0 }) { throw .forbidden(path) }
            if Self.isInsideLibraryPackage(path) { throw .forbidden(path) }

        case .application:
            // Directly in an Applications folder, or one plain folder down (Setapp, game folders, Steam's common/<game>).
            let grandparent = parent.deletingLastPathComponent().path
            let nested = parent.pathExtension != "app" && parent.lastPathComponent != "Utilities"
                && (applicationRoots.contains(grandparent) || grandparent == steamCommon)
            guard path.hasSuffix(".app"), applicationRoots.contains(parent.path) || nested else { throw .outsideAllowedRoots(path) }
            // An unreadable bundle could be Apple's: refuse it rather than guess.
            guard let bundleID = Bundle(url: resolved)?.bundleIdentifier,
                  !bundleID.hasPrefix("com.apple."), bundleID != Bundle.main.bundleIdentifier else { throw .appleApp(path) }

        case .appSupportCache:
            let app = parent   // Application Support/<App>
            guard app.deletingLastPathComponent().path == appSupport,
                  Self.appSupportCacheNames.contains(resolved.lastPathComponent),
                  !app.lastPathComponent.hasPrefix("com.apple.") else { throw .outsideAllowedRoots(path) }

        case .appLeftover:
            guard leftoverRoots.contains(parent.path) else { throw .outsideAllowedRoots(path) }
            if Self.isApple(resolved.lastPathComponent) || Self.appleSupportFolders.contains(resolved.lastPathComponent) {
                throw .appleApp(path)
            }

        case .containerCache:
            guard let container = containerID(of: path) else { throw .outsideAllowedRoots(path) }
            if Self.isApple(container) { throw .appleApp(path) }

        case .tempFile:
            guard parentPath == temporaryRoot else { throw .outsideAllowedRoots(path) }
            if resolved.lastPathComponent.hasPrefix("com.apple.") { throw .appleApp(path) }

        case .systemAdmin:
            if Self.systemAdminChildRoots.contains(parentPath) {
                if parentPath == "/Library/Caches", resolved.lastPathComponent.hasPrefix("com.apple.") { throw .appleApp(path) }
            } else if !Self.systemAdminLogRoots.contains(where: { Self.isInside(path, $0) }) {
                throw .outsideAllowedRoots(path)
            }

        case .knownData:
            guard knownDataRoots.contains(parentPath) else { throw .outsideAllowedRoots(path) }

        case .darwinCache:
            guard parentPath == darwinCacheRoot else { throw .outsideAllowedRoots(path) }

        case .aiTemp:
            // <root>/<project>/<session>: exactly two levels below the tool's own scratch folder.
            guard aiTempRoots.contains(where: { root in
                path.hasPrefix(root + "/") && path.dropFirst(root.count + 1).split(separator: "/").count == 2
            }) else { throw .outsideAllowedRoots(path) }

        case .privacy:
            guard Privacy.isTrace(path, home: home.path) else { throw .outsideAllowedRoots(path) }

        case .launchItem:
            guard Self.launchItemRoots.contains(parentPath), resolved.pathExtension == "plist" else { throw .outsideAllowedRoots(path) }
            if Self.isApple(resolved.lastPathComponent) { throw .appleApp(path) }
        }

        // The item itself, not just its folder: a mount point under the home folder (a network share) is another disk.
        let onDisk = !isLink && FileManager.default.fileExists(atPath: resolved.path) ? resolved : parent
        if policy != .application, let v = Self.volume(of: onDisk), let hv = Self.volume(of: home), v != hv {
            throw .otherVolume(path)
        }
        return resolved
    }

    /// The container identifier when `path` is strictly inside a container's Caches or Logs folder.
    func containerID(of path: String) -> String? {
        let h = home.path
        for (root, tails) in [("\(h)/Library/Containers/", ["Data/Library/Caches", "Data/Library/Logs"]),
                              ("\(h)/Library/Group Containers/", ["Library/Caches"])] where path.hasPrefix(root) {
            let rest = path.dropFirst(root.count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            let id = String(rest[..<slash])
            let inner = String(rest[rest.index(after: slash)...])
            return tails.contains { inner.hasPrefix($0 + "/") } ? id : nil
        }
        return nil
    }

    public func isAllowed(_ url: URL, policy: Policy = .junk) -> Bool {
        (try? validate(url, policy: policy)) != nil
    }

    /// Apple's identifiers, also as group (`group.com.apple.notes`) or team-prefixed (`243LU875E5.groups.com.apple.podcasts`).
    static func isApple(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("com.apple.") || lower.contains(".com.apple.")
    }

    /// Application Support folders Apple's own apps keep under plain names.
    static let appleSupportFolders: Set<String> = [
        "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "Knowledge",
        "MobileSync", "iCloud", "FileProvider", "Dock", "accountsd", "icdd",
    ]

    static func isInside(_ path: String, _ root: String) -> Bool {
        path.hasPrefix(root + "/")
    }

    /// Photos and Music libraries are databases: removing them or anything inside breaks the app.
    static func isInsideLibraryPackage(_ path: String) -> Bool {
        let packages = [".photoslibrary", ".musiclibrary", ".tvlibrary", ".photolibrary"]
        return path.lowercased().split(separator: "/").contains { part in packages.contains { part.hasSuffix($0) } }
    }

    static func volume(of url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attrs[.systemNumber] as? NSNumber)?.intValue
    }
}
