import AppKit
import SwiftUI
import CleanMacCore

/// Shared pieces for the tool screens: header, selectable rows, action bar and result banner.

struct ToolHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 18)
    }
}

extension ToolHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct ToolItemRow: View {
    let item: CleanItem
    var indent: CGFloat = 16
    var onIgnore: (() -> Void)?
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: item.isSelected ? .on : .off, action: onToggle)
            ItemIcon(item: item)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let detail = item.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let url = item.url, hovering {
                RevealButton(url: url)
            }
            Text(item.size.bytes)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
        .padding(.leading, indent)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .itemContextMenu(item, onIgnore: onIgnore)
    }
}

/// Right-click actions every file row shares: Quick Look, Finder, Get Info, and leaving it out of future scans.
struct ItemContextMenu: ViewModifier {
    let item: CleanItem
    var onIgnore: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let url = item.url {
                Button(String(localized: "Hızlı Bakış")) { Self.quickLook(url) }
                Button(String(localized: "Finder'da göster")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button(String(localized: "Bilgi Al")) { Self.getInfo(url) }
                Divider()
                Button(String(localized: "Bunu yoksay")) {
                    IgnoreList.add(url)
                    onIgnore?()
                }
            }
        }
    }

    static func quickLook(_ url: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/qlmanage")
        process.arguments = ["-p", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func getInfo(_ url: URL) {
        // The path goes in as an argument, never into the script text: a file name can't inject AppleScript.
        Task {
            _ = await Shell.run("/usr/bin/osascript", ["-e", "on run argv",
                                                       "-e", "tell application \"Finder\" to open information window of (POSIX file (item 1 of argv) as alias)",
                                                       "-e", "tell application \"Finder\" to activate",
                                                       "-e", "end run", url.path])
        }
    }
}

extension View {
    func itemContextMenu(_ item: CleanItem, onIgnore: (() -> Void)? = nil) -> some View {
        modifier(ItemContextMenu(item: item, onIgnore: onIgnore))
    }
}

struct RevealButton: View {
    let url: URL
    var body: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.secondary)
        .help(String(localized: "Finder'da göster"))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .glassPanel(cornerRadius: 14)
            .padding(.bottom, 4)
    }
}

extension EnvironmentValues {
    /// The colour world of the module on screen; panels, pills and menus tint themselves with it.
    @Entry var modulePalette = Module.smart.palette
}

extension View {
    /// A frosted slab of the module's glass behind the content (lists, columns, cards).
    func glassPanel(cornerRadius: CGFloat = 16, depth: CGFloat = 4, strength: Double = 0.1) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, depth: depth, strength: strength))
    }

    /// The selection pill of a list row: coloured glass when active, a faint wash on hover.
    func rowPill(active: Bool, hovering: Bool = false, cornerRadius: CGFloat = 9) -> some View {
        modifier(RowPill(active: active, hovering: hovering, cornerRadius: cornerRadius))
    }
}

struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat
    let depth: CGFloat
    let strength: Double
    @Environment(\.modulePalette) private var palette

    func body(content: Content) -> some View {
        content.background {
            GlassSlab(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                      tintA: Color(hex: palette.orbA), tintB: Color(hex: palette.orbB),
                      depth: depth, strength: strength)
        }
    }
}

struct RowPill: ViewModifier {
    let active: Bool
    let hovering: Bool
    let cornerRadius: CGFloat
    @Environment(\.modulePalette) private var palette

    func body(content: Content) -> some View {
        content.background {
            if active {
                GlassSlab(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                          tintA: Color(hex: palette.orbA), tintB: Color(hex: palette.orbB),
                          depth: 2.5, strength: 0.5, highlight: false)
                    .transition(.opacity)
            } else if hovering {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.white.opacity(0.05))
            }
        }
        .animation(.smooth(duration: 0.22), value: active)
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 30)
                .padding(.vertical, 11)
                .background(Capsule().fill(LinearGradient(colors: [Theme.glow, Theme.glowDeep], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: Theme.glowDeep.opacity(0.5), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Bottom bar: what is selected and the one action that removes it.
struct ToolActionBar: View {
    let selectedSize: Int64
    let selectedCount: Int
    let actionTitle: String
    var busy = false
    var countLabel: String? = nil
    var note: String? = nil
    let action: () -> Void
    @Environment(\.modulePalette) private var palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(countLabel ?? String(localized: "\(selectedCount) öğe seçili")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                Text(selectedSize.bytes)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.smooth, value: selectedSize)
            }
            if let note {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.review)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14).padding(.bottom, 16 + 62)   // room for the round button below the summary
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom))
        // The action is the same round button as on every module page.
        .overlay(alignment: .bottom) {
            OrbButton(title: actionTitle, palette: palette, action: action)
                .disabled(selectedCount == 0 || busy)
                .opacity(selectedCount == 0 || busy ? 0.45 : 1)
                .padding(.bottom, 6)
        }
    }
}

/// One-line outcome of a removal, shown above the list until the next action.
struct ReportBanner: View {
    let report: CleanReport
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.failures.isEmpty ? Theme.safe : Theme.review)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary).font(.system(size: 13, weight: .semibold))
                ForEach(report.failures.prefix(4)) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(f.title): \(f.reason)").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(3)
                        if let url = f.revealURL {
                            Button(String(localized: "Finder'da göster")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .buttonStyle(.borderless).font(.system(size: 11, weight: .semibold))
                        }
                    }
                }
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11)) }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    private var summary: String {
        var parts: [String] = []
        if report.trashedBytes > 0 { parts.append(String(localized: "\(report.trashedBytes.bytes) Çöp'e taşındı")) }
        if report.freedBytes > 0 { parts.append(String(localized: "\(report.freedBytes.bytes) hemen boşaldı")) }
        if parts.isEmpty { parts.append(String(localized: "\(report.cleanedCount) öğe kaldırıldı")) }
        if !report.failures.isEmpty { parts.append(String(localized: "\(report.failures.count) öğe kaldırılamadı")) }
        return parts.joined(separator: " · ")
    }
}

extension Array where Element == CleanItem {
    var selectedSize: Int64 { filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { filter(\.isSelected).count }

    mutating func toggle(_ item: CleanItem) {
        guard let i = firstIndex(where: { $0.id == item.id }) else { return }
        self[i].isSelected.toggle()
    }
}

// MARK: - Sort and select menus (shared by every list)

enum SortKey: String, CaseIterable, Identifiable {
    case size = "Boyut", name = "Ad", date = "Tarih"
    var id: String { rawValue }
}

struct SortMenu: View {
    @Binding var key: SortKey
    var options: [SortKey] = SortKey.allCases

    var body: some View {
        GlassMenu(prefix: String(localized: "Sırala: "), value: key.rawValue.localized) { close in
            ForEach(options) { option in
                GlassMenuRow(title: option.rawValue.localized, checked: option == key) { key = option; close() }
            }
        }
    }
}

struct SelectMenu: View {
    let selected: Int
    let total: Int
    let onAll: () -> Void
    let onNone: () -> Void
    var extra: [(title: String, action: () -> Void)] = []

    var body: some View {
        GlassMenu(prefix: String(localized: "Seç: "), value: selected == 0 ? String(localized: "Hiçbiri") : selected == total ? String(localized: "Tümü") : "\(selected) / \(total)") { close in
            GlassMenuRow(title: String(localized: "Tümünü seç"), checked: total > 0 && selected == total) { onAll(); close() }
            GlassMenuRow(title: String(localized: "Hiçbirini seçme"), checked: selected == 0) { onNone(); close() }
            if !extra.isEmpty {
                Divider().padding(.vertical, 3)
                ForEach(extra.indices, id: \.self) { i in GlassMenuRow(title: extra[i].title, checked: false) { extra[i].action(); close() } }
            }
        }
    }
}

/// "Label: value ⌄" that opens a small glass panel of choices, tinted with the module's colour.
struct GlassMenu<Items: View>: View {
    let prefix: String
    let value: String
    @ViewBuilder let items: (_ close: @escaping () -> Void) -> Items
    @State private var open = false
    @State private var hovering = false
    @Environment(\.modulePalette) private var palette

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 4) {
                Text(prefix).foregroundStyle(Theme.secondary)
                Text(value).foregroundStyle(Color(hex: palette.orbA).mix(with: .white, by: 0.35))
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(open || hovering ? 0.1 : 0.0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: open)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) { items { open = false } }
                .padding(6)
                .frame(minWidth: 170)
                .environment(\.modulePalette, palette)
        }
        .fixedSize()
    }
}

struct GlassMenuRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).opacity(checked ? 1 : 0).frame(width: 12)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .rowPill(active: hovering, cornerRadius: 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension Array where Element == CleanItem {
    func sorted(by key: SortKey) -> [CleanItem] {
        switch key {
        case .size: sorted { $0.size > $1.size }
        case .name: sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .date: sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
    }

    func matching(_ search: String) -> [CleanItem] {
        guard !search.isEmpty else { return self }
        return filter { $0.title.localizedCaseInsensitiveContains(search) || ($0.detail ?? "").localizedCaseInsensitiveContains(search) }
    }

    mutating func setAll(_ selected: Bool) {
        for i in indices { self[i].isSelected = selected }
    }
}

/// A friendly empty state: icon, title and one reassuring line.
struct EmptyStateView: View {
    let title: String
    var message = String(localized: "Burada temizlenecek bir şey yok. Her şey yolunda.")
    var symbol = "checkmark.seal"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(Theme.secondary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Finder icon of the item (an app's own icon for its caches when the name matches an installed app),
/// or a symbol for things that are not files (simulators, tool commands).
struct ItemIcon: View {
    let item: CleanItem

    var body: some View {
        Group {
            if let image = Self.icon(for: item) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: Self.symbol(for: item.action)).font(.system(size: 14)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: 22, height: 22)
    }

    static func symbol(for action: CleanAction) -> String {
        switch action {
        case .deleteSimulator: "iphone"
        case .shell: "terminal"
        default: "doc"
        }
    }

    @MainActor static var cache: [String: NSImage] = [:]

    @MainActor static func icon(for item: CleanItem) -> NSImage? {
        guard let url = item.url else { return nil }
        let key = url.path
        if let cached = cache[key] { return cached }
        // Cache folders are named after the app's bundle id; show that app's icon when it is installed.
        let name = url.lastPathComponent
        let image: NSImage
        if name.contains("."), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            image = NSWorkspace.shared.icon(forFile: app.path)
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        cache[key] = image
        return image
    }
}

/// Tabs on a glass capsule; the selected one sits on a coloured glass pill that slides between them.
struct GlassTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(title: String, value: Value)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let active = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.title)
                        .font(.system(size: 12, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background {
                            if active {
                                Color.clear.rowPill(active: true, cornerRadius: 999)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.black.opacity(0.18)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selection)
        .fixedSize()
    }
}
