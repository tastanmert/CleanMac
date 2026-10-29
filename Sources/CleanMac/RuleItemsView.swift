import SwiftUI
import CleanMacCore

/// One rule scanned on its own, listed with search, filters, sort and select — the building block
/// for the large-file, leftover, installer and old-download screens.
@Observable
final class RuleItemsModel {
    let ruleID: String
    var items: [CleanItem] = []
    var isScanning = false
    var isRemoving = false   // one removal at a time: a second tap would clean the same files again
    var hasScanned = false
    var report: CleanReport?
    var confirm = false
    var sortKey: SortKey = .size
    var search = ""
    var kind: FileKind = .all
    var age: FileAge = .all
    /// nil: every source; otherwise only downloads from this site.
    var origin: String?

    init(ruleID: String) { self.ruleID = ruleID }

    var rule: CleanRule? { CleanRule.catalog.first { $0.id == ruleID } }

    var visible: [CleanItem] {
        items.filter { kind.matches($0.title) && age.matches($0.date) && (origin == nil || $0.origin == origin) }
            .matching(search).sorted(by: sortKey)
    }

    func scan() {
        guard let rule, !isScanning else { return }
        isScanning = true
        Task {
            items = await Scanner().scan(rule).items
            isScanning = false
            hasScanned = true
        }
    }

    /// Download sites that appear in the list, most files first.
    var origins: [(site: String, count: Int)] {
        Dictionary(grouping: items.compactMap(\.origin), by: { $0 }).map { ($0.key, $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.site < $1.site }
    }

    func toggle(_ item: CleanItem) { items.toggle(item) }

    func setVisible(_ selected: Bool) {
        let ids = Set(visible.map(\.id))
        for i in items.indices where ids.contains(items[i].id) { items[i].isSelected = selected }
    }

    func removeSelected() {
        let chosen = items.filter(\.isSelected)
        guard !isRemoving, !chosen.isEmpty else { return }
        isRemoving = true
        Task {
            report = await Cleaner.live().clean(chosen, source: rule?.title ?? String(localized: "Dağınıklık"))
            isRemoving = false
            isScanning = false
            hasScanned = false
            scan()
        }
    }
}

enum FileKind: String, CaseIterable, Identifiable {
    case all = "Tümü", archives = "Arşivler", documents = "Belgeler", video = "Videolar", images = "Görseller", audio = "Ses", other = "Diğer"
    var id: String { rawValue }

    private static let map: [FileKind: Set<String>] = [
        .archives: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "pkg", "iso", "xip"],
        .video: ["mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv"],
        .images: ["jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "raw", "cr2", "nef", "gif", "webp"],
        .audio: ["mp3", "wav", "flac", "m4a", "aac", "aiff", "ogg"],
        .documents: ["pdf", "doc", "docx", "pages", "key", "numbers", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "md", "csv", "epub"],
    ]

    func matches(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        switch self {
        case .all: return true
        case .other: return !Self.map.values.contains { $0.contains(ext) }
        default: return Self.map[self]?.contains(ext) ?? false
        }
    }
}

enum FileAge: String, CaseIterable, Identifiable {
    case all = "Her zaman", month = "1 aydan eski", halfYear = "6 aydan eski", year = "1 yıldan eski"
    var id: String { rawValue }

    func matches(_ date: Date?) -> Bool {
        let days: Double = switch self { case .all: 0; case .month: 30; case .halfYear: 182; case .year: 365 }
        guard days > 0 else { return true }
        return (date ?? .distantPast) < Date.now.addingTimeInterval(-days * 86_400)
    }
}

struct RuleItemsView: View {
    let model: RuleItemsModel
    var showsFilters = false
    var emptyTitle = String(localized: "Bir şey bulunmadı")

    var body: some View {
        @Bindable var model = model
        let visible = model.visible
        VStack(spacing: 0) {
            ToolHeader(title: model.rule?.title ?? "", subtitle: model.rule?.explanation ?? "") {
                Button(model.hasScanned ? String(localized: "Yeniden tara") : String(localized: "Tara")) { model.scan() }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary).disabled(model.isScanning)
            }
            if let report = model.report { ReportBanner(report: report) { model.report = nil } }

            if model.isScanning {
                VStack(spacing: 12) { ProgressView(); Text(String(localized: "Taranıyor…")).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                    .frame(maxHeight: .infinity)
            } else if !model.hasScanned {
                VStack(spacing: 16) {
                    Image(systemName: model.rule?.symbol ?? "magnifyingglass").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.secondary)
                    PrimaryButton(title: String(localized: "Tara")) { model.scan() }
                }
                .frame(maxHeight: .infinity)
            } else if model.items.isEmpty {
                EmptyStateView(title: emptyTitle)
            } else {
                HStack(spacing: 14) {
                    SelectMenu(selected: visible.filter(\.isSelected).count, total: visible.count,
                               onAll: { model.setVisible(true) }, onNone: { model.setVisible(false) })
                    if showsFilters {
                        GlassMenu(prefix: String(localized: "Tür: "), value: model.kind.rawValue.localized) { close in
                            ForEach(FileKind.allCases) { kind in
                                GlassMenuRow(title: kind.rawValue.localized, checked: kind == model.kind) { model.kind = kind; close() }
                            }
                        }
                        GlassMenu(prefix: String(localized: "Yaş: "), value: model.age.rawValue.localized) { close in
                            ForEach(FileAge.allCases) { age in
                                GlassMenuRow(title: age.rawValue.localized, checked: age == model.age) { model.age = age; close() }
                            }
                        }
                    }
                    if !model.origins.isEmpty {
                        GlassMenu(prefix: String(localized: "Kaynak: "), value: model.origin ?? String(localized: "Tümü")) { close in
                            GlassMenuRow(title: String(localized: "Tümü"), checked: model.origin == nil) { model.origin = nil; close() }
                            Divider().padding(.vertical, 3)
                            ForEach(model.origins.prefix(12), id: \.site) { entry in
                                GlassMenuRow(title: "\(entry.site) (\(entry.count))", checked: model.origin == entry.site) {
                                    model.origin = entry.site; close()
                                }
                            }
                        }
                    }
                    Spacer()
                    TextField(String(localized: "Ara"), text: $model.search).textFieldStyle(.roundedBorder).frame(width: 150)
                    SortMenu(key: $model.sortKey)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 32)
                .padding(.bottom, 10)
                if visible.isEmpty {
                    EmptyStateView(title: String(localized: "Bu filtreyle eşleşen dosya yok"), message: String(localized: "Filtreleri değiştirip tekrar bak."), symbol: "line.3.horizontal.decrease.circle")
                } else {
                    ScrollView {
                        Card {
                            ForEach(visible) { item in
                                ItemRowWithDate(item: item) { model.toggle(item) }
                            }
                        }
                        .padding(.horizontal, 32).padding(.bottom, 20)
                    }
                }
            }
            ToolActionBar(selectedSize: model.items.selectedSize, selectedCount: model.items.selectedCount,
                          actionTitle: String(localized: "Çöp'e taşı"), busy: model.isRemoving || model.isScanning) { model.confirm = true }
        }
        .onAppear { if !model.hasScanned && !model.isScanning { model.scan() } }
        .glassConfirm(isPresented: $model.confirm, symbol: "trash", title: String(localized: "\(model.items.selectedCount) öğe Çöp'e taşınsın mı?"),
                      message: String(localized: "\(model.items.selectedSize.bytes). Çöp'ü boşaltana kadar geri alınabilir."), confirm: String(localized: "Çöp'e taşı")) { model.removeSelected() }
    }
}

/// A list row with the file's date next to its size, and its path as breadcrumbs.
struct ItemRowWithDate: View {
    let item: CleanItem
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: item.isSelected ? .on : .off, action: onToggle)
            if let url = item.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let detail = item.detail {
                    Text(Self.breadcrumbs(detail)).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let url = item.url, hovering { RevealButton(url: url) }
            if let origin = item.origin {
                Label(origin, systemImage: "arrow.down.circle").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    .lineLimit(1).frame(maxWidth: 130, alignment: .trailing)
                    .help(String(localized: "İndirildiği yer"))
            }
            if let date = item.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                    .frame(width: 90, alignment: .trailing)
            }
            Text(item.size.bytes).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .itemContextMenu(item)
    }

    /// "~/Downloads/a/b.zip" → "Ev › Downloads › a"
    static func breadcrumbs(_ detail: String) -> String {
        var parts = detail.split(separator: "/").map(String.init)
        if parts.first == "~" { parts[0] = "Ev" }
        if parts.count > 1 { parts.removeLast() }
        return parts.joined(separator: " › ")
    }
}
