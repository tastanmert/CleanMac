import Foundation

public enum Risk: Sendable {
    /// Rebuilt automatically when needed; selected by default.
    case safe
    /// Worth a look before removing; never selected by default.
    case review
}

public enum CleanAction: Sendable, Hashable {
    /// Move this file or folder to the Trash.
    case trash(URL)
    /// `xcrun simctl delete <udid>`.
    case deleteSimulator(udid: String)
    /// Run a tool's own cleanup command through a login shell. When `measure` is given it is
    /// re-sized afterwards to report what was really freed; otherwise the item's size is reported.
    case shell(command: String, measure: URL?)
    /// Move everything inside this folder to the Trash, keeping the folder (sandboxed apps expect it to exist).
    case trashContents(URL)
    /// Move a root-owned file or folder to the Trash; all such items share one administrator prompt.
    case adminTrash(URL)
}

public struct CleanItem: Identifiable, Sendable, Hashable {
    public var id: CleanAction { action }
    public let title: String
    public let detail: String?
    public let size: Int64
    public let action: CleanAction
    public var isSelected: Bool
    /// Which safety rule allows removing this item (see `SafetyGuard.Policy`).
    public let policy: SafetyGuard.Policy
    /// Last modification (or use) date, when it helps the user decide.
    public let date: Date?
    /// For downloads: the site the file came from (Spotlight's "where from"), e.g. "github.com".
    public var origin: String? = nil
    /// Belongs to an app that was open during the scan: listed, never ticked automatically.
    public var appIsOpen = false
    /// The scanner's own suggestion, kept so bulk selection can restore it (e.g. installers on the Desktop stay unticked).
    public internal(set) var isRecommended = false

    public init(title: String, detail: String? = nil, size: Int64, action: CleanAction, isSelected: Bool,
                policy: SafetyGuard.Policy = .junk, date: Date? = nil, origin: String? = nil, appIsOpen: Bool = false) {
        self.origin = origin
        self.appIsOpen = appIsOpen
        self.title = title
        self.detail = detail
        self.size = size
        self.action = action
        self.isSelected = isSelected
        self.policy = policy
        self.date = date
    }

    public var url: URL? {
        switch action {
        case .trash(let url), .trashContents(let url), .adminTrash(let url): url
        case .shell(_, let measure): measure
        case .deleteSimulator: nil
        }
    }
}

public enum Category: String, CaseIterable, Sendable, Identifiable {
    case xcode, appCaches, logs, broken, aiClutter, localModels, mail, simulators, devCaches, system, appLeftovers, largeFiles, threats, privacy
    public var id: String { rawValue }
}

public struct CategoryResult: Identifiable, Sendable {
    public var id: String { rule.id }
    public let rule: CleanRule
    public var items: [CleanItem]

    public init(rule: CleanRule, items: [CleanItem]) {
        self.rule = rule
        // "Review" findings and open apps' caches are never ticked for the user, whatever the strategy suggested.
        self.items = items.map {
            var item = $0
            item.isSelected = item.isSelected && Self.autoSelectable(item, risk: rule.risk)
            item.isRecommended = item.isSelected
            return item
        }
    }

    /// What a "select" in bulk (category, group, smart selection) may tick.
    public static func autoSelectable(_ item: CleanItem, risk: Risk) -> Bool {
        risk == .safe && !item.appIsOpen
    }

    /// Bulk selection (category, group, smart selection): on ticks exactly what the scanner recommended;
    /// review items, open apps' caches and the like stay a manual choice in the rule's list.
    public mutating func select(_ on: Bool) {
        for i in items.indices { items[i].isSelected = on && items[i].isRecommended }
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
}

extension Array where Element == CleanItem {
    /// The ticked copies of one group of duplicates, never all of them: when every copy is ticked,
    /// the one at `keep` (the oldest, or the best photo) stays where it is.
    public func selectedLeavingOne(keep: Int = 0) -> [CleanItem] {
        let chosen = filter(\.isSelected)
        guard chosen.count == count, indices.contains(keep) else { return chosen }
        return chosen.filter { $0.id != self[keep].id }
    }
}

extension String {
    /// Text that is data rather than a literal (enum raw values, stored names) in the user's language.
    /// English lives in the app's en.lproj; the Turkish text is its own key.
    public var localized: String { Bundle.main.localizedString(forKey: self, value: self, table: nil) }
}
