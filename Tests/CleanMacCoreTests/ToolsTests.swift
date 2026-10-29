import Foundation
import Testing
@testable import CleanMacCore

struct PolicyTests {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let guardian = SafetyGuard()

    @Test(arguments: ["Documents/Projects/old.zip", "Desktop/copy.png", "Downloads/x.dmg", ".ollama/models", "Movies/clip.mov"])
    func `user files inside home are allowed`(_ relative: String) {
        #expect(guardian.isAllowed(home.appending(path: relative), policy: .userFile))
    }

    @Test(arguments: ["Documents", "Desktop", "Library", "Library/Caches/x", ".ssh/id_ed25519", ".Trash/a",
                      "Pictures/Photos Library.photoslibrary", "Pictures/Photos Library.photoslibrary/database/x.db"])
    func `user files refuse system and library packages`(_ relative: String) {
        #expect(!guardian.isAllowed(home.appending(path: relative), policy: .userFile))
    }

    @Test func `whole-disk paths are judged like their usual form`() {
        let viaData = URL(filePath: "/System/Volumes/Data" + home.appending(path: "Downloads/x.dmg").path)
        #expect(guardian.isAllowed(viaData, policy: .userFile))
        #expect(!guardian.isAllowed(URL(filePath: "/System/Volumes/Data/Library/Preferences/x.plist"), policy: .userFile))
        #expect(guardian.isAllowed(URL(filePath: "/System/Volumes/Data/Users/Shared/Epic Games"), policy: .userFile))
    }

    @Test func `user files refuse anything outside home`() {
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/Xcode.app"), policy: .userFile))
    }

    @Test func `applications policy refuses Apple apps and non-apps`() {
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/Safari.app"), policy: .application))
        #expect(!guardian.isAllowed(URL(filePath: "/Applications/Utilities/Terminal.app"), policy: .application))
        #expect(!guardian.isAllowed(home.appending(path: "Downloads/Some.app"), policy: .application))
    }

    @Test func `leftovers must be direct children of support folders`() {
        #expect(guardian.isAllowed(home.appending(path: "Library/Application Support/SomeApp"), policy: .appLeftover))
        #expect(guardian.isAllowed(home.appending(path: "Library/Preferences/com.example.app.plist"), policy: .appLeftover))
        #expect(!guardian.isAllowed(home.appending(path: "Library/Application Support/SomeApp/deep"), policy: .appLeftover))
        #expect(!guardian.isAllowed(home.appending(path: "Library/Preferences/com.apple.finder.plist"), policy: .appLeftover))
        #expect(!guardian.isAllowed(home.appending(path: "Library/Keychains/login.keychain-db"), policy: .appLeftover))
    }

    @Test func `junk policy is unchanged by the new policies`() {
        #expect(!guardian.isAllowed(home.appending(path: "Documents/Projects/old.zip")))
    }
}

struct ToolDataTests {
    @Test func `parses ollama list`() {
        let output = """
        NAME          ID              SIZE      MODIFIED
        qwen3.5:4b    d8b0f5e9760c    3.3 GB    40 hours ago
        tiny:latest   aaaaaaaaaaaa    512 MB    2 days ago
        """
        #expect(ToolData.parseOllama(output) == [
            .init(name: "qwen3.5:4b", size: 3_300_000_000),
            .init(name: "tiny:latest", size: 512_000_000),
        ])
    }

    @Test func `parses simctl runtime list`() throws {
        let json = """
        {"ABC": {"identifier": "ABC", "version": "26.5", "sizeBytes": 8494282293, "deletable": true,
                 "lastUsedAt": "2026-10-17T10:06:41Z", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5"}}
        """
        let runtimes = ToolData.parseRuntimes(Data(json.utf8))
        let r = try #require(runtimes.first)
        #expect(r.name == "iOS 26.5")
        #expect(r.size == 8_494_282_293)
        #expect(r.deletable)
        #expect(r.lastUsedAt != nil)
    }

    @Test func `reads launchctl disabled state`() {
        let output = """
        disabled services = {
            "com.example.helper" => disabled
            "com.example.other" => enabled
        }
        """
        #expect(StartupItems.isDisabled("com.example.helper", in: output))
        #expect(!StartupItems.isDisabled("com.example.other", in: output))
    }
}

struct DuplicateFinderTests {
    @Test func `finds identical files, keeps the oldest, ignores different content`() async throws {
        let home = try TempDir()
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let a = try home.file("Downloads/a.bin", bytes: 2_000)
        try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: a.path)
        try home.file("Downloads/copy of a.bin", bytes: 2_000)
        try home.file("Documents/project/a.bin", bytes: 2_000)
        try Data(repeating: 9, count: 2_000).write(to: home.url.appending(path: "Downloads/different.bin"))
        try home.file("Documents/node_modules/a.bin", bytes: 2_000)   // skipped folder
        try home.file("Documents/App/Assets.xcassets/a.imageset/a.bin", bytes: 2_000)   // asset catalog, skipped

        let finder = DuplicateFinder(home: home.url,
                                     roots: [home.url.appending(path: "Downloads"), home.url.appending(path: "Documents")],
                                     autoSelectRoots: [home.url.appending(path: "Downloads")],
                                     minBytes: 1_000)
        let groups = await finder.find()
        let group = try #require(groups.first)
        #expect(groups.count == 1)
        #expect(group.items.count == 3)
        #expect(group.items.first?.title == "a.bin")              // oldest kept
        #expect(group.items.first?.isSelected == false)
        let selected = group.items.filter(\.isSelected).compactMap(\.detail)
        #expect(selected.count == 1 && selected[0].hasSuffix("Downloads/copy of a.bin"))  // Documents copy left alone
    }
}

struct UninstallerTests {
    @Test func `finds leftovers by bundle id and distinctive name only`() throws {
        let home = try TempDir()
        for path in ["Library/Application Support/com.example.Editor/data",
                     "Library/Application Support/Editor/x",
                     "Library/Caches/com.example.Editor/blob",
                     "Library/Preferences/com.example.Editor.plist",
                     "Library/Containers/ABCDE.com.example.Editor/x",
                     "Library/Application Support/com.example.EditorPro/keep",
                     "Library/Application Support/Other/keep"] {
            try home.file(path, bytes: 10)
        }
        let found = Uninstaller(home: home.url).leftovers(bundleID: "com.example.Editor", appName: "Editor")
            .map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: home.url.resolvingSymlinksInPath().path + "/Library/", with: "") }
            .sorted()
        #expect(found == [
            "Application Support/Editor",
            "Application Support/com.example.Editor",
            "Caches/com.example.Editor",
            "Containers/ABCDE.com.example.Editor",
            "Preferences/com.example.Editor.plist",
        ])
    }

    @Test func `only the app's own id comes ticked; siblings and name matches wait for the user`() {
        let id = "com.google.Chrome"
        #expect(Uninstaller.isExactly(URL(filePath: "/L/com.google.Chrome"), bundleID: id))
        #expect(Uninstaller.isExactly(URL(filePath: "/L/com.google.Chrome.plist"), bundleID: id))
        #expect(Uninstaller.isExactly(URL(filePath: "/L/EQHXZ8M8AV.com.google.Chrome"), bundleID: id))
        #expect(!Uninstaller.isExactly(URL(filePath: "/L/com.google.Chrome.canary"), bundleID: id))
        #expect(!Uninstaller.isExactly(URL(filePath: "/L/Chrome"), bundleID: id))
    }
}

struct SpaceMapTests {
    @Test func `lists children largest first`() async throws {
        let home = try TempDir()
        try home.file("big/a.bin", bytes: 300_000)
        try home.file("small.bin", bytes: 10_000)
        let nodes = await SpaceMap.children(of: home.url)
        #expect(nodes.map(\.name) == ["big", "small.bin"])
        #expect(nodes.first?.isFolder == true)
    }
}

struct NewRuleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `app support caches take known cache folders only, open apps unticked`() async throws {
        let home = try TempDir()
        try home.file("Library/Application Support/Cursor/logs/main.log", bytes: 5_000)
        try home.file("Library/Application Support/Cursor/CachedData/a", bytes: 5_000)
        try home.file("Library/Application Support/Cursor/User/settings.json", bytes: 5_000)       // user data: never
        try home.file("Library/Application Support/Cursor/blob_storage/x", bytes: 5_000)          // not a cache
        try home.file("Library/Application Support/Claude/Cache/c", bytes: 5_000)                 // app is running
        try home.file("Library/Application Support/com.apple.foo/Cache/c", bytes: 5_000)          // Apple
        let rule = try #require(CleanRule.catalog.first { $0.id == "aiAppCaches" })
        let result = await Scanner(home: home.url, runningApps: ["Claude"], now: now).scan(rule)
        #expect(Set(result.items.map(\.title)) == ["Cursor · logs", "Cursor · CachedData", "Claude · Cache"])
        #expect(Set(result.items.filter(\.isSelected).map(\.title)) == ["Cursor · logs", "Cursor · CachedData"])
        #expect(result.items.allSatisfy { $0.policy == .appSupportCache })
    }

    @Test func `app support cache policy is narrow`() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let g = SafetyGuard()
        #expect(g.isAllowed(home.appending(path: "Library/Application Support/Cursor/logs"), policy: .appSupportCache))
        #expect(!g.isAllowed(home.appending(path: "Library/Application Support/Cursor/User"), policy: .appSupportCache))
        #expect(!g.isAllowed(home.appending(path: "Library/Application Support/Cursor"), policy: .appSupportCache))
        #expect(!g.isAllowed(home.appending(path: "Library/Application Support/Cursor/x/logs"), policy: .appSupportCache))
        #expect(!g.isAllowed(home.appending(path: "Library/Caches/logs"), policy: .appSupportCache))
    }

    @Test func `broken preferences are found, valid ones left alone`() async throws {
        let home = try TempDir()
        let good = home.url.appending(path: "Library/Preferences/com.example.good.plist")
        let bad = home.url.appending(path: "Library/Preferences/com.example.bad.plist")
        try FileManager.default.createDirectory(at: good.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["a": 1], format: .binary, options: 0).write(to: good)
        try Data("not a plist <<<".utf8).write(to: bad)
        let rule = try #require(CleanRule.catalog.first { $0.id == "brokenPrefs" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["com.example.bad.plist"])
        #expect(result.items.first?.isSelected == false)
    }

    @Test func `apple caches are listed but not selected`() async throws {
        let home = try TempDir()
        try home.file("Library/Caches/com.apple.e5rt.e5bundlecache/x", bytes: 5_000)
        try home.file("Library/Caches/com.example.app/x", bytes: 5_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "appleCaches" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["com.apple.e5rt.e5bundlecache"])
        #expect(result.items.allSatisfy { !$0.isSelected })
    }

    @Test func `nested models are listed per model folder`() async throws {
        let home = try TempDir()
        try home.file(".lmstudio/models/lmstudio-community/qwen-7b/model.gguf", bytes: 5_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "localModels" })
        let result = await Scanner(home: home.url, now: now).scan(rule)
        #expect(result.items.map(\.title) == ["qwen-7b"])
    }
}

struct LeftoverTests {
    @Test(arguments: [
        ("com.unity3d.UnityEditor5.x.plist", "com.unity3d.unityeditor5.x"),
        ("ABCDE12345.com.vendor.app", "com.vendor.app"),
        ("group.com.vendor.app.shared", "com.vendor.app.shared"),
        ("com.example.App.savedState", "com.example.app"),
    ])
    func `reads identifiers from leftover names`(_ name: String, _ expected: String) {
        #expect(Leftovers.identifier(from: name) == expected)
    }

    @Test(arguments: ["AnySwitch", "Google", "com.apple", "WeTransfer", "org.x"])
    func `ignores names that are not bundle identifiers`(_ name: String) {
        #expect(Leftovers.identifier(from: name) == nil)
    }

    @Test func `orphans skip installed apps, their parts and Apple`() throws {
        let home = try TempDir()
        for path in ["Library/Application Support/com.gone.Editor/x",
                     "Library/Preferences/com.gone.Editor.plist",
                     "Library/Preferences/com.kept.Other.plist",   // another product's settings: listed
                     "Library/Application Support/com.kept.Helper/x",   // vendor data folder: kept
                     "Library/Group Containers/group.com.kept.family/x",   // vendor app group: kept
                     "Library/Application Support/com.kept.mainapp.Widgets/x",   // part of an installed app
                     "Library/Preferences/com.kept.mainapp.plist",
                     "Library/Application Support/org.sparkle-project.Downloader/x",   // shared framework
                     "Library/Caches/com.apple.Something/x",
                     "Library/Application Support/AnySwitch/x"] {    // not an identifier: left alone
            try home.file(path, bytes: 10)
        }
        let found = Leftovers.orphans(home: home.url, installed: ["com.kept.mainapp"]).map(\.lastPathComponent).sorted()
        #expect(found == ["com.gone.Editor", "com.gone.Editor.plist", "com.kept.Other.plist"])
    }

    @Test func `an open vendor's leftovers are marked open and never ticked`() async throws {
        let home = try TempDir()
        try home.file("Library/Preferences/com.busy.Old.plist", bytes: 10)
        try home.file("Library/Preferences/com.gone.Old.plist", bytes: 10)
        var scanner = Scanner(home: home.url, runningApps: ["com.busy.App"])
        scanner.installedBundleIDs = []
        let rule = try #require(CleanRule.catalog.first { $0.id == "orphans" })
        let result = await scanner.scan(rule)
        let open = Dictionary(uniqueKeysWithValues: result.items.map { ($0.title, $0.appIsOpen) })
        #expect(open == ["com.busy.Old.plist": true, "com.gone.Old.plist": false])
        #expect(result.items.allSatisfy { !$0.isSelected })
    }

    @Test func `installers are found and pre-selected only in Downloads`() async throws {
        let home = try TempDir()
        try home.file("Downloads/Tool-1.0.dmg", bytes: 5_000)
        try home.file("Desktop/Setup.pkg", bytes: 5_000)
        try home.file("Downloads/notes.txt", bytes: 5_000)
        let rule = try #require(CleanRule.catalog.first { $0.id == "installers" })
        let result = await Scanner(home: home.url).scan(rule)
        let byName = Dictionary(uniqueKeysWithValues: result.items.map { ($0.title, $0.isSelected) })
        #expect(byName == ["Tool-1.0.dmg": true, "Setup.pkg": false])
    }

}
