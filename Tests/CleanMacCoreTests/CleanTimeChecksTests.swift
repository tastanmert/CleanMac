import Foundation
import Testing
@testable import CleanMacCore

struct CleanTimeChecksTests {
    let now = Date.now

    @Test func `an app opened after the scan keeps its cache`() async throws {
        let home = try TempDir()
        let cache = try home.file("Library/Caches/com.example.editor/blob", bytes: 4_096).deletingLastPathComponent()
        let cleaner = Cleaner(home: home.url, runningApps: ["com.example.editor"]) { try FileManager.default.removeItem(at: $0) }
        let report = await cleaner.clean([CleanItem(title: "cache", size: 4_096, action: .trash(cache), isSelected: true)])
        #expect(report.cleanedCount == 0)
        #expect(FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func `a temp folder written to after the scan is skipped`() async throws {
        let home = try TempDir()
        let temp = try TempDir()
        let old = now.addingTimeInterval(-5 * 86_400)
        let folder = try temp.file("job/a.log", bytes: 10, modified: old).deletingLastPathComponent()
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: folder.path)
        try temp.file("job/new.log", bytes: 10)   // written "now", after the scan saw it idle
        let cleaner = Cleaner(home: home.url, temporaryDirectory: temp.url) { try FileManager.default.removeItem(at: $0) }
        let item = CleanItem(title: "job", size: 10, action: .trash(folder), isSelected: true, policy: .tempFile, date: old)
        let report = await cleaner.clean([item])
        #expect(report.cleanedCount == 0)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func `the temp scan judges a folder by its newest file`() async throws {
        let home = try TempDir()
        let temp = try TempDir()
        let old = now.addingTimeInterval(-5 * 86_400)
        let busy = try temp.file("busy/deep/live.log", bytes: 5_000).deletingLastPathComponent().deletingLastPathComponent()
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: busy.path)
        let rule = try #require(CleanRule.catalog.first { $0.id == "tempFiles" })
        let result = await Scanner(home: home.url, now: now, temporaryDirectory: temp.url).scan(rule)
        #expect(result.items.isEmpty)
    }

    @Test func `a stopped cleanup reports what it left untouched`() async throws {
        let home = try TempDir()
        let a = try home.file("Library/Caches/a/x", bytes: 10).deletingLastPathComponent()
        let cleaner = Cleaner(home: home.url) { try FileManager.default.removeItem(at: $0) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cleaner.clean([CleanItem(title: "a", size: 10, action: .trash(a), isSelected: true)])
        }
        let report = await task.value
        #expect(report.skippedCount == 1)
        #expect(report.cleanedCount == 0)
    }

    @Test func `only osascript's own cancel code counts as cancelled`() {
        #expect(Shell.wasCancelled(.init(status: 1, output: "execution error: User canceled. (-128)")))
        #expect(!Shell.wasCancelled(.init(status: 1, output: "mv: icon-128.png: Permission denied")))
    }

    @Test func `a browser database's sidecars count as the same trace`() {
        let home = "/Users/x"
        #expect(Privacy.isTrace("\(home)/Library/Safari/History.db-wal", home: home))
        #expect(!Privacy.isTrace("\(home)/Library/Safari/Other.db-wal", home: home))
    }
}
