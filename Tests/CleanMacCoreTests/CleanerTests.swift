import Foundation
import Synchronization
import Testing
@testable import CleanMacCore

struct CleanerTests {
    @Test func `moves allowed items, refuses protected ones, writes a log`() async throws {
        let home = try TempDir()
        let cache = try home.file("Library/Caches/com.example/blob", bytes: 4_096).deletingLastPathComponent()
        let secret = try home.file("Library/Application Support/App/data.db", bytes: 4_096)

        let moved = Mutex<[URL]>([])
        let cleaner = Cleaner(home: home.url) { url in
            moved.withLock { $0.append(url) }
            try FileManager.default.removeItem(at: url)   // stand-in for the real Trash
        }
        let items = [
            CleanItem(title: "cache", size: 4_096, action: .trash(cache), isSelected: true),
            CleanItem(title: "secret", size: 4_096, action: .trash(secret), isSelected: true),
        ]
        let report = await cleaner.clean(items)

        #expect(report.cleanedCount == 1)
        #expect(report.trashedBytes == 4_096)
        #expect(report.failures.map(\.title) == ["secret"])
        #expect(moved.withLock { $0 } == [cache.standardizedFileURL])
        #expect(FileManager.default.fileExists(atPath: secret.path))

        let logs = try FileManager.default.contentsOfDirectory(atPath: home.url.appending(path: "Library/Logs/CleanMac").path)
        #expect(logs.count == 1)
    }

    @Test func `uses the real Trash by default`() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appending(path: "Library/Caches/TemizleTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: folder.appending(path: "x"))

        let report = await Cleaner().clean([CleanItem(title: "t", size: 10, action: .trash(folder), isSelected: true)])
        #expect(report.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}

struct CleanErrorTests {
    @Test func `failure text has no terminal escape codes`() {
        let raw = "\u{1B}[?2026h\u{1B}[?25l\u{1B}[1G\u{1B}[KError: model 'x' not found\n"
        #expect(Cleaner.CleanError.commandFailed(raw).description == "Komut başarısız: Error: model 'x' not found")
    }
}
