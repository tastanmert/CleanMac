import Foundation
import Testing
@testable import CleanMacCore

struct UpdaterTests {
    @Test func `compares versions numerically`() {
        #expect(Updater.isNewer("1.10", than: "1.9"))
        #expect(Updater.isNewer("2.0.1", than: "2.0"))
        #expect(!Updater.isNewer("2.0", than: "2.0.0"))
        #expect(!Updater.isNewer("109", than: "110"))
    }

    @Test func `picks the newest stable appcast item this macOS can run`() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>110</sparkle:version><sparkle:shortVersionString>2.0.3</sparkle:shortVersionString>
          <sparkle:deltas><enclosure sparkle:version="999" url="x"/></sparkle:deltas></item>
        <item><sparkle:version>120</sparkle:version><sparkle:channel>beta</sparkle:channel></item>
        <item><enclosure url="y" sparkle:version="130" sparkle:shortVersionString="3.0"/><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion></item>
        <item><enclosure url="z" sparkle:version="105" sparkle:shortVersionString="1.9"/></item>
        </channel></rss>
        """
        let latest = Appcast.latest(in: Data(xml.utf8), system: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
        #expect(latest?.build == "110")
        #expect(latest?.short == "2.0.3")
    }

    @Test func `reads homebrew and softwareupdate output`() {
        let brew = #"Warning: x\n{"formulae":[],"casks":[{"name":"iina","installed_versions":["1.3.4"],"current_version":"1.3.5"}]}"#
        #expect(Updater.parseBrew(Data(brew.utf8)).map(\.latest) == ["1.3.5"])
        let su = "Software Update Tool\n* Label: macOS Tahoe 27.0.2-26A500\n\tTitle: macOS Tahoe 27.0.2, Version: 27.0.2, Size: 1234KiB, Recommended: YES, Action: restart,\n"
        #expect(Updater.parseSoftwareUpdate(su).map(\.latest) == ["27.0.2"])
    }
}
