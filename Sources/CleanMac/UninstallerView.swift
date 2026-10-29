import AppKit
import SwiftUI
import CleanMacCore

@Observable
final class UninstallerModel {
    enum Filter: Hashable {
        case all, unused, unsigned, selected, source(Uninstaller.Source), vendor(String)
    }

    var apps: [Uninstaller.App] = []
    var isLoading = false
    var filter: Filter = .all
    var sortKey: SortKey = .name
    var search = ""
    var selected: Set<URL> = []
    var expanded: URL?
    var files: [URL: [CleanItem]] = [:]
    var report: CleanReport?
    var confirm = false
    var isRemoving = false
    private let uninstaller = Uninstaller()

    func count(_ filter: Filter) -> Int { apps.filter { matches($0, filter) }.count }

    /// Sources that actually have apps on this Mac, in a fixed order.
    var sources: [(source: Uninstaller.Source, count: Int)] {
        Uninstaller.Source.allCases.map { s in (s, apps.filter { $0.source == s }.count) }.filter { $0.count > 0 }
    }

    var vendors: [(name: String, count: Int)] {
        Dictionary(grouping: apps, by: \.vendor).map { ($0.key, $0.value.count) }
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
    }

    var visible: [Uninstaller.App] {
        let list = apps.filter { matches($0, filter) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
        return switch sortKey {
        case .name: list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size: list.sorted { $0.size > $1.size }
        case .date: list.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }   // least recently used first
        }
    }

    var selectedApps: [Uninstaller.App] { apps.filter { selected.contains($0.url) } }
    var selectedSize: Int64 { selectedApps.reduce(0) { $0 + $1.size } }

    func matches(_ app: Uninstaller.App, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .unused: app.isUnused(runningBundleIDs: runningIDs)
        case .selected: selected.contains(app.url)
        case .unsigned: app.isUnsigned
        case .source(let source): app.source == source
        case .vendor(let v): app.vendor == v
        }
    }

    var runningIDs: Set<String> { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }

    func isRunning(_ app: Uninstaller.App) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    func load() {
        isLoading = true
        Task {
            apps = await uninstaller.installedApps()
            isLoading = false
            await withTaskGroup(of: (URL, Int64).self) { group in
                var pending = apps[...]
                func next() {
                    guard let app = pending.popFirst() else { return }
                    group.addTask { (app.url, await Uninstaller.size(of: app)) }
                }
                for _ in 0..<6 { next() }
                for await (url, size) in group {
                    if let i = apps.firstIndex(where: { $0.url == url }) { apps[i].size = size }
                    next()
                }
            }
        }
    }

    func toggle(_ app: Uninstaller.App) {
        if selected.contains(app.url) { selected.remove(app.url) } else { selected.insert(app.url) }
    }

    func expand(_ app: Uninstaller.App) {
        expanded = expanded == app.url ? nil : app.url
        guard files[app.url] == nil else { return }
        Task { files[app.url] = await uninstaller.items(for: app) }
    }

    func uninstallSelected() {
        let chosen = selectedApps.filter { !isRunning($0) }
        isRemoving = true
        Task {
            var items: [CleanItem] = []
            for app in chosen {
                if let known = files[app.url] { items += known } else { items += await uninstaller.items(for: app) }
            }
            report = await Cleaner.live().clean(items.filter(\.isSelected), source: String(localized: "Kaldırıcı"))
            selected = []
            files = [:]
            expanded = nil
            isRemoving = false
            load()
        }
    }
}

struct UninstallerView: View {
    @Environment(AppModel.self) private var app
    private var model: UninstallerModel { app.uninstaller }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let report = model.report {
                ReportBanner(report: report) { model.report = nil }.padding(.top, 14)
            }
            HStack(spacing: 12) {
                filters.frame(width: 210).glassPanel(strength: 0.08)
                list.padding(.top, 10).frame(maxWidth: .infinity).glassPanel(strength: 0.12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            ToolActionBar(selectedSize: model.selectedSize, selectedCount: model.selected.count, actionTitle: String(localized: "Kaldır"),
                          busy: model.isRemoving, countLabel: String(localized: "\(model.selected.count) uygulama seçili"),
                          note: model.selectedApps.contains(where: model.isRunning) ? String(localized: "Açık uygulamalar atlanır; önce kapat.") : nil) {
                model.confirm = true
            }
        }
        .onAppear { if model.apps.isEmpty { model.load() } }
        .glassConfirm(isPresented: $model.confirm, symbol: "xmark.app", title: String(localized: "\(model.selected.count) uygulama kaldırılsın mı?"),
                      message: String(localized: "Uygulamalar ve ~/Library'deki destek dosyaları Çöp'e taşınır. Çöp'ü boşaltana kadar geri alınabilir."),
                      confirm: String(localized: "Çöp'e taşı")) { model.uninstallSelected() }
    }

    private var filters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                FilterRow(title: String(localized: "Tüm uygulamalar"), count: model.count(.all), isActive: model.filter == .all) { model.filter = .all }
                FilterRow(title: String(localized: "Kullanılmayan"), count: model.count(.unused), isActive: model.filter == .unused) { model.filter = .unused }
                    .help(String(localized: "6 aydır açılmamış ya da kurulduğundan beri iki hafta hiç açılmamış uygulamalar"))
                if model.count(.unsigned) > 0 {
                    FilterRow(title: String(localized: "Şüpheli"), count: model.count(.unsigned), isActive: model.filter == .unsigned) { model.filter = .unsigned }
                        .help(String(localized: "Apple'ın tanıdığı bir geliştirici imzası olmayan uygulamalar: imzasız, kendi imzalı ya da imzası bozuk. Zararlı olmak zorunda değil; nereden geldiğine bak."))
                }
                FilterRow(title: String(localized: "Seçili"), count: model.selected.count, isActive: model.filter == .selected) { model.filter = .selected }
                Text(String(localized: "Kaynak")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary).padding(.horizontal, 10).padding(.top, 14)
                ForEach(model.sources, id: \.source) { item in
                    FilterRow(title: item.source.rawValue.localized, count: item.count, isActive: model.filter == .source(item.source)) {
                        model.filter = .source(item.source)
                    }
                }
                if !model.vendors.isEmpty {
                    Text(String(localized: "Geliştiriciler")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary).padding(.horizontal, 10).padding(.top, 14)
                    ForEach(model.vendors, id: \.name) { vendor in
                        FilterRow(title: vendor.name, count: vendor.count, isActive: model.filter == .vendor(vendor.name)) {
                            model.filter = .vendor(vendor.name)
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    private var list: some View {
        @Bindable var model = model
        let visible = model.visible
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                SelectMenu(selected: visible.filter { model.selected.contains($0.url) }.count, total: visible.count,
                           onAll: { model.selected.formUnion(visible.map(\.url)) },
                           onNone: { model.selected.subtract(visible.map(\.url)) })
                Spacer()
                TextField(String(localized: "Uygulama ara"), text: $model.search).textFieldStyle(.roundedBorder).frame(width: 170)
                SortMenu(key: $model.sortKey)
            }
            .padding(.horizontal, 18).padding(.bottom, 8)
            if model.isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if visible.isEmpty {
                EmptyStateView(title: String(localized: "Bu filtrede uygulama yok"), message: String(localized: "Başka bir filtre seç."), symbol: "square.grid.2x2")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { app in
                            AppRow(app: app, isSelected: model.selected.contains(app.url), isExpanded: model.expanded == app.url,
                                   isRunning: model.isRunning(app),
                                   onToggle: { model.toggle(app) }, onExpand: { model.expand(app) })
                            if model.expanded == app.url {
                                AppFiles(items: model.files[app.url])
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

struct FilterRow: View {
    let title: String
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13, weight: isActive ? .semibold : .regular)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .rowPill(active: isActive)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppRow: View {
    let app: Uninstaller.App
    let isSelected: Bool
    let isExpanded: Bool
    let isRunning: Bool
    let onToggle: () -> Void
    let onExpand: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: isSelected ? .on : .off, action: onToggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if isRunning {
                        Text(String(localized: "app.running", defaultValue: "Açık")).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.review)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.review.opacity(0.15)))
                    }
                    if app.isAppStore {
                        Image(systemName: "bag.fill").font(.system(size: 9)).foregroundStyle(Theme.tertiary).help("App Store")
                    }
                    if app.isUnsigned {
                        Text(String(localized: "İmzasız")).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.review)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.review.opacity(0.15)))
                            .help(String(localized: "Apple'ın tanıdığı bir geliştirici imzası yok"))
                    }
                    if app.source != .appStore && app.source != .other {
                        Text(app.source.rawValue.localized).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.08)))
                    }
                }
                Text(app.vendor).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 8)
            Text(app.lastUsed.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String(localized: "Kullanılmamış"))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(app.isUnused() ? Theme.review : Theme.tertiary)
                .frame(width: 100, alignment: .trailing)
                .help(String(localized: "Son kullanım"))
            Text(app.size > 0 ? app.size.bytes : "…").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                .frame(width: 72, alignment: .trailing)
            Button(action: onExpand) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(Theme.secondary)
            .accessibilityLabel(isExpanded ? String(localized: "Dosyaları gizle") : String(localized: "Dosyaları göster"))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering || isExpanded ? Color.white.opacity(0.05) : .clear))
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: isExpanded)
    }
}

/// An app's files grouped like Finder would think of them: the app, its settings, its support files.
struct AppFiles: View {
    let items: [CleanItem]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let items {
                ForEach(groups(items), id: \.0) { title, groupItems in
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        .padding(.leading, 58).padding(.top, 8)
                    ForEach(groupItems) { item in
                        HStack {
                            Text(item.detail ?? item.title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let url = item.url { RevealButton(url: url) }
                            Text(item.size.bytes).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                        }
                        .padding(.leading, 58).padding(.trailing, 44).padding(.vertical, 3)
                    }
                }
            } else {
                ProgressView().controlSize(.small).padding(.leading, 58).padding(.vertical, 8)
            }
        }
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private func groups(_ items: [CleanItem]) -> [(String, [CleanItem])] {
        let order = [String(localized: "Uygulama"), String(localized: "Ayarlar"), String(localized: "Destek dosyaları"), String(localized: "Önbellekler"), String(localized: "Başlangıç öğeleri"), String(localized: "Diğer")]
        let grouped = Dictionary(grouping: items) { item -> String in
            let path = item.detail ?? ""
            if path.hasSuffix(".app") { return String(localized: "Uygulama") }
            if path.contains("/Preferences/") { return String(localized: "Ayarlar") }
            if path.contains("/Caches/") || path.contains("/HTTPStorages/") || path.contains("/WebKit/") { return String(localized: "Önbellekler") }
            if path.contains("/LaunchAgents/") { return String(localized: "Başlangıç öğeleri") }
            if path.contains("/Application Support/") || path.contains("/Containers/") || path.contains("Saved Application State") { return String(localized: "Destek dosyaları") }
            return String(localized: "Diğer")
        }
        return order.compactMap { key in grouped[key].map { (key, $0) } }
    }
}
