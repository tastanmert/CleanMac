import Foundation
import Testing
@testable import CleanMacCore

struct PrivacyTests {
    @Test func `finds browser traces, skips open browsers, never bookmarks or passwords`() async throws {
        let home = try TempDir()
        try home.file("Library/Safari/History.db", bytes: 4_000)
        try home.file("Library/Safari/History.db-wal", bytes: 2_000)
        try home.file("Library/Safari/Bookmarks.plist", bytes: 1_000)
        try home.file("Library/Application Support/Google/Chrome/Default/History", bytes: 4_000)
        try home.file("Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4_000)
        try home.file("Library/Application Support/Google/Chrome/Default/Login Data", bytes: 4_000)
        try home.file("Library/Application Support/Firefox/Profiles/abc.default/cookies.sqlite", bytes: 4_000)
        try home.file("Library/Application Support/Firefox/Profiles/abc.default/places.sqlite", bytes: 4_000)
        try home.file("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3", bytes: 500)

        let rule = try #require(CleanRule.catalog.first { $0.id == "privacy" })
        let result = await Scanner(home: home.url, runningApps: ["Google Chrome"]).scan(rule)
        let titles = Set(result.items.map(\.title))
        #expect(titles == ["Safari · tarama geçmişi", "Firefox · çerezler", "Son belgeler"])
        #expect(result.items.allSatisfy { !$0.isSelected && $0.policy == .privacy })
        #expect(try #require(result.items.first { $0.title == "Safari · tarama geçmişi" }).size >= 6_000)
    }

    @Test func `privacy policy accepts only known trace files`() throws {
        let home = try TempDir()
        let guardian = SafetyGuard(home: home.url)
        let h = home.url
        #expect(guardian.isAllowed(h.appending(path: "Library/Safari/History.db"), policy: .privacy))
        #expect(guardian.isAllowed(h.appending(path: "Library/Application Support/Google/Chrome/Profile 1/Cookies"), policy: .privacy))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Safari/Bookmarks.plist"), policy: .privacy))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Application Support/Google/Chrome/Default/Login Data"), policy: .privacy))
        #expect(!guardian.isAllowed(h.appending(path: "Library/Application Support/Firefox/Profiles/x/places.sqlite"), policy: .privacy))
    }

    @Test func `parses the privacy database`() {
        let output = "kTCCServiceCamera\tus.zoom.xos\t2\t1790000000\nkTCCServiceMicrophone\tcom.x\t0\t1790000000\nkTCCServiceUnknownThing\tcom.y\t2\t1\n"
        let grants = Permissions.parse(output)
        #expect(grants.map(\.client) == ["us.zoom.xos", "com.x"])
        #expect(grants.map(\.allowed) == [true, false])
    }
}

struct WiFiParsingTests {
    @Test func `finds the wifi device and saved networks`() {
        let ports = "Hardware Port: Ethernet\nDevice: en1\n\nHardware Port: Wi-Fi\nDevice: en0\nEthernet Address: aa\n"
        #expect(WiFiNetworks.parseInterface(ports) == "en0")
        #expect(WiFiNetworks.parseInterface("Hardware Port: Ethernet\nDevice: en1\n") == nil)
        let saved = "Preferred networks on en0:\n\tHome\n\tCafe Free WiFi\n\n"
        #expect(WiFiNetworks.parseSaved(saved) == ["Home", "Cafe Free WiFi"])
    }
}
