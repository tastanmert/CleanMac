import Foundation
import Testing
@testable import CleanMacCore

struct SelfUpdateTests {
    @Test func `reads github's latest release json`() throws {
        let json = """
        {"tag_name":"v1.2","body":"## Neler değişti","published_at":"2026-10-27T18:41:04Z",
         "assets":[{"name":"notes.txt","browser_download_url":"https://github.com/x/y/notes.txt"},
                   {"name":"CleanMac.dmg","browser_download_url":"https://github.com/tastanmert/CleanMac/releases/download/v1.2/CleanMac.dmg"}]}
        """
        let release = try #require(SelfUpdate.parse(Data(json.utf8)))
        #expect(release.version == "1.2")
        #expect(release.tag == "v1.2")
        #expect(release.notes == "## Neler değişti")
        #expect(release.date != nil)
        #expect(release.download?.lastPathComponent == "CleanMac.dmg")
    }

    @Test func `explains why github could not answer`() {
        #expect(SelfUpdate.reason(status: 404).contains("yayınlanmış sürüm yok"))
        #expect(SelfUpdate.reason(status: 403).contains("sonra"))
        #expect(SelfUpdate.reason(status: nil).contains("İnternet"))
    }

    @Test func `the install script swaps the app and keeps the old one in the Trash`() async throws {
        let dir = try TempDir()
        let current = try dir.file("Applications/CleanMac.app/Contents/old", bytes: 1)
            .deletingLastPathComponent().deletingLastPathComponent()
        let staged = try dir.file("stage/CleanMac.app/Contents/new", bytes: 1)
            .deletingLastPathComponent().deletingLastPathComponent()
        let trash = dir.url.appending(path: "Trash")
        // A process that has already exited: the script must not wait for it.
        let done = Process()
        done.executableURL = URL(filePath: "/usr/bin/true")
        try done.run()
        done.waitUntilExit()

        let script = SelfUpdate.installScript(staged: staged, current: current, trash: trash, pid: done.processIdentifier, relaunch: false)
        let result = await Shell.run("/bin/zsh", ["-c", script])
        #expect(result.status == 0)
        #expect(FileManager.default.fileExists(atPath: current.appending(path: "Contents/new").path))
        #expect(!FileManager.default.fileExists(atPath: current.appending(path: "Contents/old").path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        #expect(kept.count == 1 && kept[0].hasPrefix("CleanMac (eski)"))
        #expect(!FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
    }

    @Test func `refuses a package that is not this app's update`() async throws {
        let dir = try TempDir()
        let app = dir.url.appending(path: "CleanMac.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "com.other.app", "CFBundleShortVersionString": "9.9"]
        try info.write(to: app.appending(path: "Contents/Info.plist"))
        await #expect(throws: SelfUpdate.Failure.notAnUpdate("başka bir uygulama")) {
            try await SelfUpdate.verify(app, bundleID: "dev.merttastan.cleanmac", version: "9.9")
        }
    }
}
