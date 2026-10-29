import Foundation
import Testing
@testable import CleanMacCore

struct CoverageRuleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var old: Date { now.addingTimeInterval(-5 * 86_400) }

    @Test func `darwin cache children are listed, open apps unticked, apple skipped`() async throws {
        let home = try TempDir()
        let cache = try TempDir()
        try cache.file("clang/a.bin", bytes: 20_000)
        try cache.file("com.example.helper/b.bin", bytes: 20_000)
        try cache.file("com.apple.metal/c.bin", bytes: 20_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "darwinCaches" })
        let result = await Scanner(home: home.url, runningApps: ["com.example.helper"], now: now, darwinCacheDirectory: cache.url).scan(rule)
        #expect(Set(result.items.map(\.title)) == ["clang", "com.example.helper"])
        #expect(result.items.first { $0.title == "clang" }?.isSelected == true)
        #expect(result.items.first { $0.title == "com.example.helper" }?.isSelected == false)
        let guardian = SafetyGuard(home: home.url, darwinCacheDirectory: cache.url)
        #expect(!guardian.isAllowed(cache.url.appending(path: "clang/a.bin"), policy: .darwinCache))
        #expect(!guardian.isAllowed(cache.url, policy: .darwinCache))
    }

    @Test func `ai temp folders need two levels and an old newest file`() async throws {
        let home = try TempDir()
        let tmp = try TempDir()
        let root = tmp.url.appending(path: "claude-501").path
        try tmp.file("claude-501/-Users-me-proj/old-session/out.txt", bytes: 30_000, modified: old)
        try tmp.file("claude-501/-Users-me-proj/live-session/out.txt", bytes: 30_000, modified: old)
        try tmp.file("claude-501/-Users-me-proj/live-session/tasks/new.txt", bytes: 10, modified: now)
        for session in ["old-session", "live-session"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: tmp.url.appending(path: "claude-501/-Users-me-proj/\(session)").path)
        }
        let rule = try #require(CleanRule.catalog.first { $0.id == "claudeTemp" })
        let result = await Scanner(home: home.url, now: now, aiTempRoots: [root]).scan(rule)
        #expect(result.items.count == 1)
        #expect(result.items.first?.title == "Claude Code oturumu · old-sess")
        let guardian = SafetyGuard(home: home.url, aiTempRoots: [root])
        #expect(guardian.isAllowed(tmp.url.appending(path: "claude-501/-Users-me-proj/old-session"), policy: .aiTemp))
        #expect(!guardian.isAllowed(tmp.url.appending(path: "claude-501/-Users-me-proj"), policy: .aiTemp))
        #expect(!guardian.isAllowed(tmp.url.appending(path: "claude-501/-Users-me-proj/old-session/out.txt"), policy: .aiTemp))
    }

    @Test func `stale tool versions keep the one the link points to`() async throws {
        let home = try TempDir()
        try home.file(".local/share/claude/versions/1.0.0/bin", bytes: 40_000)
        try home.file(".local/share/claude/versions/1.0.1/bin", bytes: 40_000)
        try FileManager.default.createDirectory(at: home.url.appending(path: ".local/bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.url.appending(path: ".local/bin/claude"),
                                                   withDestinationURL: home.url.appending(path: ".local/share/claude/versions/1.0.1/bin"))
        let rule = try #require(CleanRule.catalog.first { $0.id == "claudeVersions" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["1.0.0"])

        try FileManager.default.removeItem(at: home.url.appending(path: ".local/bin/claude"))
        let orphaned = await Scanner(home: home.url, now: now).scan(rule)
        #expect(orphaned.items.isEmpty)   // no link, no way to tell which version is in use
    }
}

struct OllamaManifestTests {
    @Test func `models are read from manifests when the server is down`() throws {
        let home = try TempDir()
        let manifest = #"{"config":{"size":500},"layers":[{"size":1000000000},{"size":2000}]}"#
        let a = home.url.appending(path: ".ollama/models/manifests/registry.ollama.ai/library/qwen3/8b")
        let b = home.url.appending(path: ".ollama/models/manifests/registry.ollama.ai/someone/tool/latest")
        for url in [a, b] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: url)
        }
        let models = ToolData.ollamaFromManifests(home: home.url)
        #expect(Set(models.map(\.name)) == ["qwen3:8b", "someone/tool:latest"])
        #expect(models.allSatisfy { $0.size == 1_000_002_500 })
    }
}

struct FailureExplanationTests {
    @Test func `permission errors come with a finder location, app store apps say why`() throws {
        let home = try TempDir()
        let app = home.url.appending(path: "Applications/Store.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/_MASReceipt"), withIntermediateDirectories: true)
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let item = CleanItem(title: "Store", size: 1, action: .trash(app), isSelected: true, policy: .application)
        let (reason, url) = Cleaner.explain(denied, for: item)
        #expect(reason.hasPrefix("App Store uygulaması"))
        #expect(url == app)

        let plain = CleanItem(title: "x", size: 1, action: .trash(home.url.appending(path: "x")), isSelected: true, policy: .userFile)
        let (plainReason, plainURL) = Cleaner.explain(denied, for: plain)
        #expect(plainReason.contains("Finder'da gösterip"))
        #expect(plainURL != nil)

        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(Cleaner.explain(other, for: plain).1 == nil)
    }
}

struct FullDiskAccessTests {
    @Test func `a readable protected folder counts as access, none does not`() throws {
        let empty = try TempDir()
        // This test process has no Full Disk Access, so only the fake readable folder can say yes.
        #expect(FullDiskAccess.isGranted(home: empty.url) == FullDiskAccess.isGranted(home: URL(filePath: "/nonexistent")))
        let home = try TempDir()
        try home.file("Library/Safari/History.db", bytes: 10)
        #expect(FullDiskAccess.isGranted(home: home.url))
    }
}

struct AudioPluginTests {
    @Test func `user plug-ins are listed unticked, system ones need the admin path`() async throws {
        let home = try TempDir()
        try home.file("Library/Audio/Plug-Ins/Components/Synth.component/Contents/x", bytes: 30_000)
        try home.file("Library/Audio/Plug-Ins/VST3/Reverb.vst3/Contents/x", bytes: 30_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "audioPlugins" })
        let result = await Scanner(home: home.url).scan(rule)
        let mine = result.items.filter { $0.detail?.hasSuffix("~/Library") == true }
        #expect(Set(mine.map(\.title)) == ["Synth", "Reverb"])
        #expect(result.items.allSatisfy { !$0.isSelected })
        #expect(result.items.filter { $0.policy == .systemAdmin }.allSatisfy { if case .adminTrash = $0.action { true } else { false } })
        #expect(SafetyGuard().isAllowed(URL(filePath: "/Library/Audio/Plug-Ins/HAL/X.driver"), policy: .systemAdmin))
        #expect(!SafetyGuard().isAllowed(URL(filePath: "/Library/Audio/Plug-Ins/HAL"), policy: .systemAdmin))
    }
}
