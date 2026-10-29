import Foundation
import Testing
@testable import CleanMacCore

struct SafetyGuardTests {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let guardian = SafetyGuard()

    @Test(arguments: [
        "Library/Caches/com.example.app",
        "Library/Developer/Xcode/DerivedData/MyApp-abc",
        "Library/Logs/old.log",
        ".npm/_cacache",
        "Downloads/big.dmg",
    ])
    func `allows items inside allowed roots`(_ relative: String) {
        #expect(guardian.isAllowed(home.appending(path: relative)))
    }

    @Test(arguments: [
        "Library/Application Support/Claude",
        "Library/Containers/com.apple.mail",
        "Library/Keychains/login.keychain-db",
        "Library/Mobile Documents/iCloud~md~obsidian",
        "Library/Developer/CoreDevice/DeviceFS/device-1",
        "Library/Logs/CleanMac/today.log",
        "Documents/Projects",
        "Desktop/file.txt",
        ".ssh/id_ed25519",
        "Library/Preferences/com.apple.finder.plist",
    ])
    func `rejects protected locations`(_ relative: String) {
        #expect(!guardian.isAllowed(home.appending(path: relative)))
    }

    @Test(arguments: ["Library/Caches", "Library/Logs", "Downloads", ".cache"])
    func `rejects the allowed root itself`(_ relative: String) {
        #expect(throws: SafetyGuard.Rejection.isRoot(home.appending(path: relative).standardizedFileURL.path)) {
            try guardian.validate(home.appending(path: relative))
        }
    }

    @Test func `rejects paths outside home`() {
        #expect(!guardian.isAllowed(URL(filePath: "/System/Library/Caches/x")))
        #expect(!guardian.isAllowed(URL(filePath: "/usr/local/lib")))
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/Xcode.app")))
    }

    @Test func `rejects dot-dot escapes`() {
        let escape = home.appending(path: "Library/Caches/../Application Support/Claude")
        #expect(!guardian.isAllowed(escape))
    }

    @Test func `rejects a symlinked parent that points to a protected folder`() throws {
        let fakeHome = try TempDir()
        let caches = fakeHome.url.appending(path: "Library/Caches")
        let support = fakeHome.url.appending(path: "Library/Application Support/App")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let link = caches.appending(path: "sneaky")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: support)

        let g = SafetyGuard(home: fakeHome.url)
        #expect(g.isAllowed(link))                                   // the link itself may go
        #expect(!g.isAllowed(link.appending(path: "important.db")))  // but not what it points into
    }
}

struct SafetyGuardCaseTests {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let guardian = SafetyGuard()

    // APFS ignores case: a wrongly cased URL is still the protected folder itself.
    @Test(arguments: ["LIBRARY", "library", "documents", "DESKTOP", ".SSH", ".trash"])
    func `user files refuse protected folders spelled in another case`(_ name: String) {
        #expect(!guardian.isAllowed(home.appending(path: name), policy: .userFile))
    }

    @Test func `library packages are protected whatever the extension's case`() {
        #expect(!guardian.isAllowed(home.appending(path: "Pictures/Foo.PHOTOSLIBRARY"), policy: .userFile))
        #expect(!guardian.isAllowed(home.appending(path: "Music/Lib.MusicLibrary/x"), policy: .userFile))
    }

    @Test func `Apple group and team-prefixed containers are refused`() {
        #expect(!guardian.isAllowed(home.appending(path: "Library/Group Containers/group.com.apple.notes"), policy: .appLeftover))
        #expect(!guardian.isAllowed(home.appending(path: "Library/Application Support/AddressBook"), policy: .appLeftover))
        #expect(!guardian.isAllowed(home.appending(path: "Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Caches/x"),
                                    policy: .containerCache))
        #expect(guardian.isAllowed(home.appending(path: "Library/Group Containers/ABC.com.example.app/Library/Caches/x"),
                                   policy: .containerCache))
    }

    @Test func `an app whose bundle cannot be read is refused`() throws {
        let dir = try TempDir()
        let fake = try dir.file("Applications/Ghost.app/readme", bytes: 1).deletingLastPathComponent()
        let g = SafetyGuard(home: dir.url)
        #expect(!g.isAllowed(fake, policy: .application))
    }
}

/// A temporary directory removed when the value goes away.
final class TempDir {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "TemizleTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relative: String, bytes: Int, modified: Date? = nil) throws -> URL {
        let file = url.appending(path: relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: file)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        }
        return file
    }
}
