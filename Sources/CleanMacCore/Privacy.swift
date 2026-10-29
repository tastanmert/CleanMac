import Foundation

/// Browser traces and macOS activity lists. Everything here is listed for review only and goes to the
/// Trash like any other item; a browser's files are skipped while that browser is open.
/// Saved passwords, bookmarks and autofill data are never touched.
public enum Privacy {
    public struct Trace: Sendable, Hashable {
        public let app: String      // running-app name used to skip it
        public let title: String
        public let url: URL
    }

    static let chromium: [(app: String, root: String)] = [
        ("Google Chrome", "Library/Application Support/Google/Chrome"),
        ("Brave Browser", "Library/Application Support/BraveSoftware/Brave-Browser"),
        ("Microsoft Edge", "Library/Application Support/Microsoft Edge"),
        ("Arc", "Library/Application Support/Arc/User Data"),
    ]
    static let chromiumFiles: [(name: String, title: String)] = [
        ("History", String(localized: "tarama ve indirme geçmişi")), ("Cookies", String(localized: "çerezler")), ("Sessions", String(localized: "son oturum sekmeleri")),
    ]
    static let firefoxFiles: [(name: String, title: String)] = [
        ("cookies.sqlite", String(localized: "çerezler")), ("formhistory.sqlite", String(localized: "arama ve form geçmişi")), ("sessionstore-backups", String(localized: "son oturum sekmeleri")),
    ]
    static let recentLists: [(name: String, title: String)] = [
        ("com.apple.LSSharedFileList.RecentDocuments", String(localized: "Son belgeler")),
        ("com.apple.LSSharedFileList.RecentApplications", String(localized: "Son uygulamalar")),
        ("com.apple.LSSharedFileList.RecentServers", String(localized: "Son sunucular")),
    ]

    /// Every trace that exists on disk right now.
    public static func traces(home: URL) -> [Trace] {
        let fm = FileManager.default
        var result: [Trace] = []
        func add(_ app: String, _ title: String, _ url: URL) {
            if fm.fileExists(atPath: url.path) { result.append(Trace(app: app, title: title, url: url)) }
        }

        add("Safari", String(localized: "Safari · tarama geçmişi"), home.appending(path: "Library/Safari/History.db"))
        add("Safari", String(localized: "Safari · son oturum sekmeleri"), home.appending(path: "Library/Safari/LastSession.plist"))
        add("Safari", String(localized: "Safari · çerezler"), home.appending(path: "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"))
        add("Safari", String(localized: "Safari · çerezler"), home.appending(path: "Library/Cookies/Cookies.binarycookies"))

        for browser in chromium {
            for profile in profiles(home.appending(path: browser.root)) {
                let label = profile.lastPathComponent == "Default" ? browser.app : "\(browser.app) (\(profile.lastPathComponent))"
                for file in chromiumFiles { add(browser.app, "\(label) · \(file.title)", profile.appending(path: file.name)) }
            }
        }

        let firefox = home.appending(path: "Library/Application Support/Firefox/Profiles")
        for profile in (try? fm.contentsOfDirectory(at: firefox, includingPropertiesForKeys: nil)) ?? [] {
            for file in firefoxFiles { add("Firefox", "Firefox · \(file.title)", profile.appending(path: file.name)) }
        }

        let lists = home.appending(path: "Library/Application Support/com.apple.sharedfilelist")
        for list in recentLists {
            for ext in ["sfl4", "sfl3", "sfl2"] { add("", list.title, lists.appending(path: "\(list.name).\(ext)")) }
        }
        return result
    }

    /// Chromium keeps one folder per profile ("Default", "Profile 1"…), each with its own History.
    static func profiles(_ root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "History").path) }
    }

    /// True when `path` is exactly one of the trace files above (by its place, not by a list on disk).
    static func isTrace(_ path: String, home: String) -> Bool {
        // A database's -wal/-shm/-journal sidecar goes with it.
        if let suffix = ["-wal", "-shm", "-journal"].first(where: path.hasSuffix) {
            return isTrace(String(path.dropLast(suffix.count)), home: home)
        }
        let fixed = ["Library/Safari/History.db", "Library/Safari/LastSession.plist",
                     "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                     "Library/Cookies/Cookies.binarycookies"].map { "\(home)/\($0)" }
        if fixed.contains(path) { return true }
        let url = URL(filePath: path)
        let name = url.lastPathComponent, profile = url.deletingLastPathComponent()
        if chromiumFiles.contains(where: { $0.name == name }),
           chromium.contains(where: { profile.deletingLastPathComponent().path == "\(home)/\($0.root)" }) { return true }
        if firefoxFiles.contains(where: { $0.name == name }),
           profile.deletingLastPathComponent().path == "\(home)/Library/Application Support/Firefox/Profiles" { return true }
        if profile.path == "\(home)/Library/Application Support/com.apple.sharedfilelist",
           recentLists.contains(where: { list in ["sfl4", "sfl3", "sfl2"].contains { name == "\(list.name).\($0)" } }) { return true }
        return false
    }

    /// SQLite keeps recent writes next to the database; they go with it.
    public static func sidecars(of url: URL) -> [URL] {
        ["-wal", "-shm", "-journal"].map { URL(filePath: url.path + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// What apps are allowed to use (camera, microphone, files…), read from macOS's privacy database.
/// Reading needs Full Disk Access; removing a permission uses `tccutil reset`, so the app simply asks again.
public enum Permissions {
    public struct Grant: Identifiable, Sendable, Hashable {
        public var id: String { service + "|" + client }
        public let service: String
        public let client: String
        public let allowed: Bool
        public let changed: Date?
    }

    public static let serviceNames: [String: String] = [
        "kTCCServiceCamera": String(localized: "Kamera"), "kTCCServiceMicrophone": String(localized: "Mikrofon"),
        "kTCCServiceScreenCapture": String(localized: "Ekran kaydı"), "kTCCServiceAccessibility": String(localized: "Erişilebilirlik"),
        "kTCCServiceListenEvent": String(localized: "Giriş izleme"), "kTCCServicePostEvent": String(localized: "Klavye ve fare denetimi"),
        "kTCCServiceSystemPolicyAllFiles": String(localized: "Tam disk erişimi"), "kTCCServiceSystemPolicyDesktopFolder": String(localized: "Masaüstü klasörü"),
        "kTCCServiceSystemPolicyDocumentsFolder": String(localized: "Belgeler klasörü"), "kTCCServiceSystemPolicyDownloadsFolder": String(localized: "İndirilenler klasörü"),
        "kTCCServiceSystemPolicyNetworkVolumes": String(localized: "Ağ birimleri"), "kTCCServiceSystemPolicyRemovableVolumes": String(localized: "Çıkarılabilir birimler"),
        "kTCCServiceAddressBook": String(localized: "Kişiler"), "kTCCServiceCalendar": String(localized: "Takvim"), "kTCCServiceReminders": String(localized: "Anımsatıcılar"),
        "kTCCServicePhotos": String(localized: "Fotoğraflar"), "kTCCServiceAppleEvents": String(localized: "Otomasyon"), "kTCCServiceSpeechRecognition": String(localized: "Konuşma tanıma"),
        "kTCCServiceBluetoothAlways": "Bluetooth", "kTCCServiceLocation": String(localized: "Konum"), "kTCCServiceMediaLibrary": String(localized: "Medya arşivi"),
    ]

    public enum Failure: Error, Sendable { case noAccess }

    public static func list(home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> Result<[Grant], Failure> {
        let databases = [home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path,
                         "/Library/Application Support/com.apple.TCC/TCC.db"]
        var grants: [Grant] = []
        var readAny = false
        for db in databases {
            let result = await Shell.run("/usr/bin/sqlite3", ["-readonly", "-separator", "\t", db,
                                                              "SELECT service, client, auth_value, last_modified FROM access"])
            guard result.status == 0 else { continue }
            readAny = true
            grants += parse(result.output)
        }
        guard readAny else { return .failure(.noAccess) }
        // The same app can appear in both databases; keep one row per service and app.
        var seen = Set<String>()
        return .success(grants.filter { seen.insert($0.id).inserted }
            .sorted { (serviceNames[$0.service] ?? $0.service, $0.client) < (serviceNames[$1.service] ?? $1.service, $1.client) })
    }

    static func parse(_ output: String) -> [Grant] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, serviceNames[f[0]] != nil else { return nil }
            return Grant(service: f[0], client: f[1], allowed: f[2] == "2",
                         changed: Double(f[3]).map { Date(timeIntervalSince1970: $0) })
        }
    }

    /// Forgets the permission; the app asks again next time it needs it.
    public static func reset(_ grant: Grant) async -> Bool {
        let service = grant.service.replacingOccurrences(of: "kTCCService", with: "")
        return await Shell.run("/usr/bin/tccutil", ["reset", service, grant.client]).status == 0
    }
}

/// Full Disk Access: without it macOS hides sandbox containers, Mail and other apps' data from the scan.
public enum FullDiskAccess {
    /// macOS has no API for this; probe places only Full Disk Access unlocks. The per-user TCC database
    /// is gone on recent macOS, so several probes are tried and any one that opens settles it.
    public static var isGranted: Bool { isGranted(home: FileManager.default.homeDirectoryForCurrentUser) }

    static func isGranted(home: URL) -> Bool {
        let databases = ["/Library/Application Support/com.apple.TCC/TCC.db",
                         home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path]
        for path in databases where FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forReadingAtPath: path) { try? handle.close(); return true }
        }
        let folders = ["Library/Safari", "Library/Mail", "Library/Messages", "Library/Containers/com.apple.Safari",
                       "Library/Suggestions", "Library/Cookies"]
        for folder in folders {
            let url = home.appending(path: folder)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil { return true }
        }
        return false
    }
}

/// Wi-Fi networks this Mac remembers and joins by itself. Listing needs no permission; forgetting one
/// changes system settings, so it goes through the administrator prompt.
public enum WiFiNetworks {
    /// The Wi-Fi device name (usually en0), from `networksetup -listallhardwareports`.
    public static func interface() async -> String? {
        let out = await Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]).output
        return parseInterface(out)
    }

    static func parseInterface(_ output: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") || line.contains("Hardware Port: AirPort") {
            if i + 1 < lines.count, let device = lines[i + 1].components(separatedBy: "Device: ").last?.trimmingCharacters(in: .whitespaces),
               !device.isEmpty { return device }
        }
        return nil
    }

    public static func saved(on interface: String) async -> [String] {
        parseSaved(await Shell.run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", interface]).output)
    }

    static func parseSaved(_ output: String) -> [String] {
        output.components(separatedBy: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func forget(_ name: String, on interface: String) async -> Bool {
        let command = "/usr/sbin/networksetup -removepreferredwirelessnetwork \(Shell.quote(interface)) \(Shell.quote(name))"
        return await Maintenance.runCommand(command, admin: true).status == 0
    }
}
