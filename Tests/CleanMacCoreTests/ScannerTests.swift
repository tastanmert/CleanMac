import Foundation
import Testing
@testable import CleanMacCore

struct ScannerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `measures allocated size including hidden files`() throws {
        let tmp = try TempDir()
        try tmp.file("a/one.bin", bytes: 100_000)
        try tmp.file("a/.hidden.bin", bytes: 50_000)
        try tmp.file("a/deep/two.bin", bytes: 200_000)
        let size = Scanner.allocatedSize(of: tmp.url.appending(path: "a"))
        #expect(size >= 350_000)
        #expect(size < 400_000)   // allocated blocks, not wildly more
    }

    @Test func `children strategy skips apple and listed caches and leaves running apps unticked`() async throws {
        let home = try TempDir()
        for name in ["com.example.editor", "com.apple.Safari", "Homebrew", "com.running.app", "Google"] {
            try home.file("Library/Caches/\(name)/blob", bytes: 10_000)
        }
        let rule = try #require(CleanRule.catalog.first { $0.id == "appCaches" })
        let scanner = Scanner(home: home.url, runningApps: ["com.running.app", "Google Chrome"], now: now)
        let result = await scanner.scan(rule)
        #expect(Set(result.items.map(\.title)) == ["com.example.editor", "com.running.app", "Google"])
        #expect(result.items.filter(\.isSelected).map(\.title) == ["com.example.editor"])
        #expect(result.items.first { $0.title == "Google" }?.detail?.contains("uygulama açık") == true)
    }

    @Test func `old logs only`() async throws {
        let home = try TempDir()
        try home.file("Library/Logs/old.log", bytes: 5_000, modified: now.addingTimeInterval(-10 * 86_400))
        try home.file("Library/Logs/new.log", bytes: 5_000, modified: now.addingTimeInterval(-1 * 86_400))
        try home.file("Library/Logs/CleanMac/old-own.log", bytes: 5_000, modified: now.addingTimeInterval(-30 * 86_400))
        let rule = try #require(CleanRule.catalog.first { $0.id == "logs" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["old.log"])
    }

    @Test func `large files are listed but never selected`() async throws {
        let home = try TempDir()
        try home.file("Downloads/small.zip", bytes: 1_000)
        let rule = CleanRule(id: "t", category: .largeFiles, title: "", explanation: "", symbol: "", risk: .review,
                             strategy: .largeFiles(in: ["~/Downloads"], minBytes: 500))
        try home.file("Downloads/big.dmg", bytes: 600_000)
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(Set(result.items.map(\.title)) == ["small.zip", "big.dmg"])
        #expect(result.items.allSatisfy { !$0.isSelected })
    }

    @Test func `every catalog path passes the safety guard`() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let guardian = SafetyGuard(home: home)
        for rule in CleanRule.catalog {
            let paths: [String] = switch rule.strategy {
            case .paths(let p): p
            case .children(let f, _, _, _, _, .junk): [f + "/x"]
            case .children: []   // other policies, checked in SystemJunkTests
            case .nested(let r, _): [r + "/x"]
            case .appSupportCaches, .brokenPreferences, .orphanedSupportFiles: []
            case .installers: []   // user-file policy
            case .oldFiles(let f, _): [f + "/x"]
            case .largeFiles: []   // user-file policy, checked in PolicyTests
            case .tool(_, _, let m): rule.category == .privacy ? [] : [m]   // a database cleared in place, not trashed
            case .simulators: ["~/Library/Developer/CoreSimulator/Devices/x"]
            case .ollamaModels, .simulatorRuntimes: []
            case .containerCaches, .tempFiles, .adminChildren, .adminOldFiles, .appDataCaches, .iosBackups, .brokenLaunchAgents, .duplicates, .privacyTraces, .darwinCaches, .aiTempFolders, .staleVersions, .audioPlugins, .threats: []
            }
            for path in paths {
                #expect(guardian.isAllowed(CleanRule.expand(path, home: home)), "\(rule.id): \(path)")
            }
        }
    }

    @Test func `parses simctl json and picks candidates`() throws {
        let json = """
        {"devices": {
          "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [
            {"udid": "A", "name": "iPhone 16", "state": "Shutdown", "isAvailable": false, "dataPath": "/x"},
            {"udid": "B", "name": "iPhone 17", "state": "Shutdown", "isAvailable": true, "lastBootedAt": "2026-01-01T10:00:00Z"},
            {"udid": "C", "name": "iPhone 17 Pro", "state": "Booted", "isAvailable": true, "lastBootedAt": "2020-01-01T10:00:00Z"},
            {"udid": "D", "name": "iPad", "state": "Shutdown", "isAvailable": true, "lastBootedAt": "2027-01-10T10:00:00Z"},
            {"udid": "E", "name": "QA", "state": "Shutdown", "isAvailable": false, "lastBootedAt": "2027-01-10T10:00:00Z",
             "availabilityError": "runtime profile not found using \\"System\\" match policy"}
          ]}}
        """
        let sims = try SimulatorService.parse(Data(json.utf8))
        #expect(sims.first?.runtime == "iOS 26.4")
        let picked = SimulatorService.candidates(sims, unusedDays: 30, now: now)  // now ≈ 2027-01-15
        #expect(picked.map(\.0.udid).sorted() == ["A", "B", "E"])
        #expect(picked.first { $0.0.udid == "E" }?.isSafe == false)   // missing runtime: never pre-selected
        #expect(picked.first { $0.0.udid == "A" }?.isSafe == true)
        #expect(picked.first { $0.0.udid == "B" }?.isSafe == false)
    }
}
