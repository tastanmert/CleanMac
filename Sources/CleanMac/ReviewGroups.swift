import AppKit
import CleanMacCore
import UniformTypeIdentifiers

/// One finding together with the rule it came from (selection and ignoring go through the rule).
struct ReviewEntry: Identifiable {
    let ruleID: String
    let item: CleanItem
    var id: CleanAction { item.id }
}

/// A row of the manager's item column: caches and logs are listed per app
/// ("Telegram", "Raycast") and open up to show their folders; other findings are listed per rule.
struct OwnerGroup: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let symbol: String
    let entries: [ReviewEntry]

    var size: Int64 { entries.reduce(0) { $0 + $1.item.size } }
    var selectedSize: Int64 { entries.filter(\.item.isSelected).reduce(0) { $0 + $1.item.size } }
    var checkState: CheckState {
        let selected = entries.filter(\.item.isSelected).count
        return selected == 0 ? .off : selected == entries.count ? .on : .mixed
    }
    /// Every item is something the scanner would tick: marked as recommended.
    var isRecommended: Bool { entries.allSatisfy(\.item.isRecommended) }
    var latestDate: Date? { entries.compactMap(\.item.date).max() }
}

enum OwnerGroups {
    /// Folders whose direct children are named after the app that owns them. Containers come first:
    /// their path also contains `Library/Caches`.
    static let anchors = ["/Library/Containers/", "/Library/Group Containers/", "/Library/Caches/", "/Library/Logs/",
                          "/Application Support/", "/C/"]

    static func groups(_ results: [CategoryResult], category: CleanMacCore.Category) -> [OwnerGroup] {
        let entries = results.flatMap { result in result.items.map { ReviewEntry(ruleID: result.rule.id, item: $0) } }
        var order: [String] = []
        var byKey: [String: (name: String, icon: NSImage?, symbol: String, entries: [ReviewEntry])] = [:]
        for entry in entries {
            let rule = results.first { $0.rule.id == entry.ruleID }!.rule
            let owner = owner(of: entry, rule: rule, category: category)
            if byKey[owner.key] == nil {
                order.append(owner.key)
                byKey[owner.key] = (owner.name, owner.icon, owner.symbol, [])
            }
            byKey[owner.key]!.entries.append(entry)
        }
        return order.map { key in
            let g = byKey[key]!
            return OwnerGroup(id: key, name: g.name, icon: g.icon, symbol: g.symbol, entries: g.entries)
        }
    }

    private static func owner(of entry: ReviewEntry, rule: CleanRule, category: CleanMacCore.Category)
        -> (key: String, name: String, icon: NSImage?, symbol: String) {
        switch category {
        case .appCaches, .logs:
            if let folder = ownerFolder(entry.item.url) { return app(named: folder) }
        case .aiClutter:
            if rule.id.hasPrefix("claude") { return app(named: "Claude Code") }
            if let tool = entry.item.title.components(separatedBy: " · ").first, entry.item.title.contains(" · ") {
                return app(named: tool)
            }
        case .threats:
            // Each suspicious app or service is its own row, named after itself.
            if let url = entry.item.url {
                let isApp = url.pathExtension == "app"
                return ("item:\(url.path)", entry.item.title, isApp ? NSWorkspace.shared.icon(forFile: url.path) : nil,
                        isApp ? "app" : "gearshape.2")
            }
        default:
            break
        }
        return ("rule:\(rule.id)", rule.title, nil, rule.symbol)
    }

    /// "~/Library/Caches/com.raycast.macos/x" → "com.raycast.macos".
    static func ownerFolder(_ url: URL?) -> String? {
        guard let path = url?.path else { return nil }
        for anchor in anchors {
            guard let range = path.range(of: anchor) else { continue }
            let rest = path[range.upperBound...]
            return rest.split(separator: "/").first.map(String.init)
        }
        return nil
    }

    @MainActor private static var resolved: [String: (key: String, name: String, icon: NSImage?, symbol: String)] = [:]

    /// The installed app a folder name stands for, so its caches in different places share one row:
    /// "com.google.Chrome.helper" → Google Chrome, "Telegram Desktop" → Telegram Desktop.app.
    @MainActor static func app(named folder: String) -> (key: String, name: String, icon: NSImage?, symbol: String) {
        if let hit = resolved[folder] { return hit }
        var result: (key: String, name: String, icon: NSImage?, symbol: String) =
            ("folder:\(folder.lowercased())", folder, NSWorkspace.shared.icon(for: .folder), "folder")
        if let url = appURL(for: folder) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let id = Bundle(url: url)?.bundleIdentifier?.lowercased() ?? url.path
            result = ("app:\(id)", name, NSWorkspace.shared.icon(forFile: url.path), "app")
        }
        resolved[folder] = result
        return result
    }

    private static func appURL(for folder: String) -> URL? {
        var parts = folder.split(separator: ".").map(String.init)
        if parts.first == "group" { parts.removeFirst() }
        if let first = parts.first, first.count == 10, first == first.uppercased(), parts.count > 3 { parts.removeFirst() }
        // A bundle identifier, or one of its parts (helpers, ShipIt, widgets): drop components until an app answers.
        while parts.count >= 2 {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) { return url }
            parts.removeLast()
        }
        for root in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            let url = URL(filePath: "\(root)/\(folder).app")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
