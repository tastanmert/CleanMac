import Foundation
import Synchronization
import Testing
@testable import CleanMacCore

struct SystemJunkTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `container policy allows only inside a container's caches or logs`() throws {
        let home = try TempDir()
        let guardian = SafetyGuard(home: home.url)
        let h = home.url
        #expect(guardian.isAllowed(h.appending(path: "Library/Containers/com.example.app/Data/Library/Caches/blob"), policy: .containerCache))
        #expect(guardian.isAllowed(h.appending(path: "Library/Containers/com.example.app/Data/Library/Logs/a.log"), policy: .containerCache))
        #expect(guardian.isAllowed(h.appending(path: "Library/Group Containers/ABCDE12345.com.example/Library/Caches/x"), policy: .containerCache))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Containers/com.example.app/Data/Library/Caches"), policy: .containerCache))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Containers/com.example.app/Data/Documents/x"), policy: .containerCache))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Containers/com.apple.mail/Data/Library/Caches/x"), policy: .containerCache))
    }

    @Test func `system admin policy`() {
        let guardian = SafetyGuard()
        #expect(guardian.isAllowed(URL(filePath: "/Library/Caches/com.vendor.updater"), policy: .systemAdmin))
        #expect(guardian.isAllowed(URL(filePath: "/private/var/log/system.log.0.gz"), policy: .systemAdmin))
        #expect(guardian.isAllowed(URL(filePath: "/Library/Logs/DiagnosticReports/a.ips"), policy: .systemAdmin))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/Caches/com.apple.iconservices.store"), policy: .systemAdmin))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/Caches"), policy: .systemAdmin))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/Preferences/x.plist"), policy: .systemAdmin))
        #expect(!guardian.isAllowed(URL(filePath: "/System/Library/Caches/x"), policy: .systemAdmin))
    }

    @Test func `temp and known data policies`() throws {
        let home = try TempDir()
        let temp = try TempDir()
        let guardian = SafetyGuard(home: home.url, temporaryDirectory: temp.url)
        #expect(guardian.isAllowed(temp.url.appending(path: "leftover.tmp"), policy: .tempFile))
        #expect(!guardian.isAllowed(temp.url.appending(path: "a/b"), policy: .tempFile))
        #expect(!guardian.isAllowed(temp.url.appending(path: "com.apple.x"), policy: .tempFile))
        #expect(guardian.isAllowed(home.url.appending(path: "Library/Application Support/MobileSync/Backup/0000-AAA"), policy: .knownData))
        #expect(!guardian.isAllowed(home.url.appending(path: "Library/Application Support/MobileSync/Backup"), policy: .knownData))
        #expect(!guardian.isAllowed(home.url.appending(path: "Library/Application Support/Spotify/prefs"), policy: .knownData))
    }

    @Test func `container caches skip apple and running apps`() async throws {
        let home = try TempDir()
        try home.file("Library/Containers/com.example.reader/Data/Library/Caches/blob", bytes: 20_000)
        try home.file("Library/Containers/com.example.player/Data/Library/Caches/blob", bytes: 20_000)
        try home.file("Library/Containers/com.apple.news/Data/Library/Caches/blob", bytes: 20_000)
        try home.file("Library/Group Containers/ABCDE12345.com.example.chat/Library/Caches/blob", bytes: 20_000)
        try home.file("Library/Group Containers/ABCDE12345.com.example.reader/Library/Caches/blob", bytes: 20_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "containerCaches" })
        let result = await Scanner(home: home.url, runningApps: ["com.example.player", "com.example.chat"], now: now).scan(rule)
        #expect(Set(result.items.map(\.title)) == ["com.example.reader · önbellek", "ABCDE12345.com.example.reader · önbellek"])
        #expect(result.items.allSatisfy { $0.policy == .containerCache && $0.isSelected })
    }

    @Test func `emptying a container cache keeps the folder`() async throws {
        let home = try TempDir()
        try home.file("Library/Containers/com.example.reader/Data/Library/Caches/a/blob", bytes: 4_096)
        try home.file("Library/Containers/com.example.reader/Data/Library/Caches/b.db", bytes: 4_096)
        let folder = home.url.appending(path: "Library/Containers/com.example.reader/Data/Library/Caches")
        let cleaner = Cleaner(home: home.url) { try FileManager.default.removeItem(at: $0) }
        let report = await cleaner.clean([CleanItem(title: "c", size: 8_192, action: .trashContents(folder), isSelected: true,
                                                    policy: .containerCache)])
        #expect(report.failures.isEmpty)
        #expect(report.trashedBytes == 8_192)
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func `old temp files only`() async throws {
        let home = try TempDir()
        let temp = try TempDir()
        try temp.file("old.tmp", bytes: 5_000, modified: now.addingTimeInterval(-5 * 86_400))
        try temp.file("fresh.tmp", bytes: 5_000, modified: now.addingTimeInterval(-3_600))
        let rule = try #require(CleanRule.catalog.first { $0.id == "tempFiles" })
        let result = await Scanner(home: home.url, now: now, temporaryDirectory: temp.url).scan(rule)
        #expect(result.items.map(\.title) == ["old.tmp"])
    }

    @Test func `ios backups are named after the device and never selected`() async throws {
        let home = try TempDir()
        let backup = "Library/Application Support/MobileSync/Backup/00008110-ABC"
        try home.file("\(backup)/Manifest.db", bytes: 30_000)
        let info: NSDictionary = ["Device Name": "Mert's iPhone", "Product Version": "26.4"]
        try info.write(to: home.url.appending(path: "\(backup)/Info.plist"))
        let rule = try #require(CleanRule.catalog.first { $0.id == "iosBackups" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["Mert's iPhone"])
        #expect(result.items.allSatisfy { !$0.isSelected })
    }

    @Test func `shell quoting survives apostrophes`() async {
        let result = await Shell.run("/bin/sh", ["-c", "printf %s \(Shell.quote("it's a/b c"))"])
        #expect(result.output == "it's a/b c")
    }
}

struct TrashBinTests {
    @Test func `lists the user's trash and each external disk's trash`() throws {
        let home = try TempDir()
        let volumes = try TempDir()
        try home.file(".Trash/old.zip", bytes: 8_000)
        try volumes.file("Backup/.Trashes/\(getuid())/movie.mov", bytes: 16_000)
        try FileManager.default.createDirectory(at: volumes.url.appending(path: "Empty"), withIntermediateDirectories: true)
        let bins = TrashBins.list(home: home.url, volumes: volumes.url)
        #expect(bins.map(\.name) == ["Çöp", "Backup"])
        #expect(bins.map(\.count) == [1, 1])
        #expect(bins[1].isExternal && bins[1].size >= 16_000)
    }
}

struct BrokenAgentTests {
    @Test func `finds agents whose program is gone`() async throws {
        let home = try TempDir()
        let agents = home.url.appending(path: "Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try (["Label": "com.gone.helper", "Program": "/Applications/Gone.app/Contents/MacOS/helper"] as NSDictionary)
            .write(to: agents.appending(path: "com.gone.helper.plist"))
        try (["Label": "com.ok.helper", "ProgramArguments": ["/bin/sh", "-c", "true"]] as NSDictionary)
            .write(to: agents.appending(path: "com.ok.helper.plist"))
        let rule = try #require(CleanRule.catalog.first { $0.id == "brokenAgents" })
        let result = await Scanner(home: home.url).scan(rule)
        #expect(result.items.map(\.title) == ["com.gone.helper"])
    }
}

struct ActivityTests {
    @Test func `cleaning is recorded and ignored items stay out of scans`() async throws {
        let home = try TempDir()
        let keep = try home.file("Library/Caches/com.example.keep/blob", bytes: 4_096).deletingLastPathComponent()
        try home.file("Library/Caches/com.example.go/blob", bytes: 4_096)
        IgnoreList.add(keep, home: home.url)
        let rule = try #require(CleanRule.catalog.first { $0.id == "appCaches" })
        let result = await Scanner(home: home.url).scan(rule)
        #expect(result.items.map(\.title) == ["com.example.go"])

        let cleaner = Cleaner(home: home.url) { try FileManager.default.removeItem(at: $0) }
        _ = await cleaner.clean(result.items, source: "Test")
        let entries = ActivityLog.entries(home: home.url)
        #expect(entries.map(\.source) == ["Test"])
        #expect(entries.first?.count == 1)
    }
}
