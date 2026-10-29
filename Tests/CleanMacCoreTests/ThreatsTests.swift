import Foundation
import Testing
@testable import CleanMacCore

/// The protection scan flags what Gatekeeper would not vouch for, and nothing it can't safely move.
struct ThreatsTests {
    private func plist(_ dict: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
    }

    @Test func `unsigned apps and adware style launch items are flagged`() throws {
        let home = try TempDir()
        let apps = home.url.appending(path: "Applications")
        try plist(["CFBundleIdentifier": "com.shady.App"], at: apps.appending(path: "Shady.app/Contents/Info.plist"))
        try plist(["CFBundleIdentifier": "com.apple.Fake"], at: apps.appending(path: "Fake.app/Contents/Info.plist"))

        let hidden = try home.file(".hidden/updater", bytes: 64)
        let plain = try home.file("tools/bin/server", bytes: 64)
        let agents = home.url.appending(path: "Library/LaunchAgents")
        try plist(["Label": "com.wizard.update", "ProgramArguments": [hidden.path]], at: agents.appending(path: "com.wizard.update.plist"))
        try plist(["Label": "com.wizard.script", "ProgramArguments": ["/bin/sh", hidden.path]], at: agents.appending(path: "com.wizard.script.plist"))
        try plist(["Label": "homebrew.mxcl.server", "Program": plain.path], at: agents.appending(path: "homebrew.mxcl.server.plist"))
        try plist(["Label": "com.apple.thing", "Program": hidden.path], at: agents.appending(path: "com.apple.thing.plist"))
        try plist(["Label": "com.gone.agent", "Program": "/nowhere/agent"], at: agents.appending(path: "com.gone.agent.plist"))

        let findings = Threats.scan(home: home.url, appFolders: [apps], launchFolders: [(agents, false)])
        #expect(Set(findings.map(\.title)) == ["Shady", "com.wizard.update", "com.wizard.script"])
        #expect(findings.allSatisfy { !$0.needsAdmin })
    }

    @Test func `hidden and shared locations`() {
        let home = "/Users/me"
        #expect(Threats.isHiddenLocation("/Users/me/.x7f2/agent", home: home))
        #expect(!Threats.isHiddenLocation("/Users/me/.local/bin/meld", home: home))
        #expect(Threats.isHiddenLocation("/Users/Shared/agent", home: home))
        #expect(Threats.isHiddenLocation("/Users/me/Library/Application Support/abc/agent", home: home))
        #expect(Threats.isHiddenLocation("/private/tmp/agent", home: home))
        #expect(!Threats.isHiddenLocation("/opt/homebrew/opt/redis/bin/redis-server", home: home))
        #expect(!Threats.isHiddenLocation("/Applications/App.app/Contents/MacOS/helper", home: home))
        #expect(Threats.isHiddenLocation("/Library/Application Support/x/agent", home: home))
        #expect(!Threats.isHiddenLocation("/Library/Application Support/Vpn/vpnd", home: home, system: true))
        #expect(Threats.isHiddenLocation("/Library/.x/vpnd", home: home, system: true))
    }

    @Test func `system launch items are moved only with the launch item policy`() {
        let guardian = SafetyGuard()
        #expect(guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/com.vendor.helper.plist"), policy: .launchItem))
        #expect(guardian.isAllowed(URL(filePath: "/Library/LaunchAgents/com.vendor.agent.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/com.apple.thing.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/x/com.vendor.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/com.vendor.helper"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/System/Library/LaunchDaemons/com.vendor.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/com.vendor.helper.plist"), policy: .systemAdmin))
        #expect(guardian.isAllowed(URL(filePath: "/System/Volumes/Data/Library/LaunchDaemons/com.vendor.helper.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/../Preferences/com.vendor.plist"), policy: .launchItem))
        #expect(!guardian.isAllowed(URL(filePath: "/Library/LaunchDaemons/COM.APPLE.thing.plist"), policy: .launchItem))
    }

    @Test func `threat findings are never ticked`() async throws {
        let rule = try #require(CleanRule.catalog.first { $0.id == "threats" })
        #expect(rule.risk == .review)
        #expect(rule.category == .threats)
        let home = try TempDir()
        let hidden = try home.file(".hidden/updater", bytes: 64)
        try plist(["Label": "com.wizard.update", "Program": hidden.path],
                  at: home.url.appending(path: "Library/LaunchAgents/com.wizard.update.plist"))
        var scanner = Scanner(home: home.url)
        scanner.threatFolders = ([], [(home.url.appending(path: "Library/LaunchAgents"), false)])
        let result = await scanner.scan(rule)
        let agent = try #require(result.items.first { $0.title == "com.wizard.update" })
        #expect(agent.policy == .appLeftover)
        #expect(result.items.allSatisfy { !$0.isSelected && !$0.isRecommended })
    }

    @Test func `admin trash refuses items whose policy is not an admin one`() async {
        let item = CleanItem(title: "x", size: 1, action: .adminTrash(URL(filePath: "/Library/LaunchDaemons/com.vendor.x.plist")),
                             isSelected: true, policy: .appLeftover)
        let result = await Cleaner().adminTrash([item])
        guard case .failure = result else { Issue.record("an appLeftover item must not reach the admin prompt"); return }
    }
}
