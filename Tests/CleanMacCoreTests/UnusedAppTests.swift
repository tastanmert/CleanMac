import Testing
import Foundation
@testable import CleanMacCore

@Suite struct UnusedAppTests {
    private func app(_ id: String, used: Int? = nil, installedDaysAgo: Int = 90, background: Bool = false) -> Uninstaller.App {
        Uninstaller.App(url: URL(filePath: "/Applications/\(id).app"), name: id, bundleID: id, size: 0,
                        lastUsed: used.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }, isAppStore: false,
                        installed: Date.now.addingTimeInterval(-Double(installedDaysAgo) * 86_400), isBackground: background)
    }

    @Test func oldAndNeverOpenedAppsAreUnused() {
        #expect(app("com.x.old", used: 300).isUnused(runningBundleIDs: []))
        #expect(app("com.x.never", installedDaysAgo: 30).isUnused(runningBundleIDs: []))
        #expect(!app("com.x.fresh", installedDaysAgo: 3).isUnused(runningBundleIDs: []))
        #expect(!app("com.x.recent", used: 20).isUnused(runningBundleIDs: []))
    }

    @Test func backgroundHelpersAndRunningFamiliesAreNeverUnused() {
        #expect(!app("com.x.handler", background: true).isUnused(runningBundleIDs: []))
        #expect(!app("com.x.tool").isUnused(runningBundleIDs: ["com.x.tool"]))
        #expect(!app("org.pqrs.Karabiner-Elements.Settings").isUnused(runningBundleIDs: ["org.pqrs.Karabiner-Menu"]))
        #expect(!app("com.vendor.settings").isUnused(runningBundleIDs: ["com.vendor.daemon"]))
        #expect(app("com.apple.dt.Xcode").isUnused(runningBundleIDs: ["com.apple.finder"]))
    }
}

struct AppSourceTests {
    @Test func `sources come from receipt, folder and bundle id`() {
        #expect(Uninstaller.source(of: URL(filePath: "/Applications/X.app"), bundleID: "a.b", isAppStore: true) == .appStore)
        #expect(Uninstaller.source(of: URL(filePath: "/Applications/Setapp/X.app"), bundleID: "a.b", isAppStore: false) == .setapp)
        #expect(Uninstaller.source(of: URL(filePath: "/Users/u/Library/Application Support/Steam/steamapps/common/G/G.app"),
                                   bundleID: "a.b", isAppStore: false) == .steam)
        #expect(Uninstaller.source(of: URL(filePath: "/Applications/Battle.net.app"), bundleID: "net.battle.app", isAppStore: false) == .battleNet)
        #expect(Uninstaller.source(of: URL(filePath: "/Applications/X.app"), bundleID: "a.b", isAppStore: false) == .other)
    }

    @Test func `system apps carry a trusted signature`() {
        #expect(Uninstaller.hasTrustedSignature(URL(filePath: "/System/Applications/Calculator.app")))
    }

    @Test func `apps one plain folder down are allowed, deeper or inside bundles are not`() {
        let guardian = SafetyGuard()
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/A.app/Contents/B.app"), policy: .application))
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/a/b/C.app"), policy: .application))
    }
}
