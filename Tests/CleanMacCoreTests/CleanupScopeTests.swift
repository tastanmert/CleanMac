import Foundation
import Testing
@testable import CleanMacCore

/// The everyday cleanup stays on user-level junk; developer and system-level findings live in their own tool.
struct CleanupScopeTests {
    static let cleanup: Set<CleanMacCore.Category> = [.xcode, .appCaches, .logs, .broken, .aiClutter, .localModels, .mail]

    @Test(arguments: ["derivedData", "xcodeCaches", "appCaches", "darwinCaches", "appleCaches", "containerCaches",
                      "logs", "brokenPrefs", "brokenAgents", "aiAppCaches", "claudeTemp", "ollama", "localModels", "mailDownloads"])
    func `everyday junk findings are in the cleanup scope`(_ id: String) throws {
        let rule = try #require(CleanRule.catalog.first { $0.id == id })
        #expect(Self.cleanup.contains(rule.category))
    }

    @Test(arguments: ["runtimes", "simulators", "deviceSupport", "archives", "npm", "uv", "pnpm", "browsers", "hfCache",
                      "claudeVM", "deletedUsers", "systemLogs", "systemCaches", "iosBackups", "tempFiles"])
    func `developer and system findings stay out of the cleanup scope`(_ id: String) throws {
        let rule = try #require(CleanRule.catalog.first { $0.id == id })
        #expect(!Self.cleanup.contains(rule.category))
    }

    @Test func `finder metadata is never a finding`() async throws {
        let home = try TempDir()
        try home.file("Library/Developer/Xcode/Archives/.DS_Store", bytes: 10)
        try home.file("Library/Developer/Xcode/Archives/2026-10-01/App.xcarchive/x", bytes: 10)
        let rule = try #require(CleanRule.catalog.first { $0.id == "archives" })
        let result = await Scanner(home: home.url).scan(rule)
        #expect(result.items.map(\.title) == ["2026-10-01"])
    }
}
