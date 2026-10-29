import SwiftUI
import CleanMacCore

@Observable
final class DuplicatesModel {
    var groups: [DuplicateFinder.Group] = []
    var isScanning = false
    var isRemoving = false   // one removal at a time: a second tap would clean the same files again
    var hasScanned = false
    var progress = ""
    var report: CleanReport?
    var confirm = false

    var sortKey: SortKey = .size
    var allItems: [CleanItem] { groups.flatMap(\.items) }
    /// What a removal takes: the ticked copies, always leaving one of each group.
    var chosen: [CleanItem] { groups.flatMap { $0.items.selectedLeavingOne() } }

    var sortedGroups: [DuplicateFinder.Group] {
        switch sortKey {
        case .name: groups.sorted { ($0.items.first?.title ?? "").localizedCaseInsensitiveCompare($1.items.first?.title ?? "") == .orderedAscending }
        default: groups.sorted { $0.wasted > $1.wasted }
        }
    }

    /// Keep the first (oldest) copy of every group, select the rest.
    func selectAllButOldest() {
        for g in groups.indices { for i in groups[g].items.indices { groups[g].items[i].isSelected = i > 0 } }
    }

    func selectNone() {
        for g in groups.indices { groups[g].items.setAll(false) }
    }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() {
        isScanning = true
        report = nil
        Task {
            groups = await DuplicateFinder().find { folder in
                await MainActor.run { self.progress = folder }
            }
            isScanning = false
            hasScanned = true
        }
    }

    func toggle(_ item: CleanItem, in group: DuplicateFinder.Group) {
        guard let g = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[g].items.toggle(item)
    }

    func removeSelected() {
        let chosen = self.chosen
        guard !isRemoving, !chosen.isEmpty else { return }
        isRemoving = true
        Task {
            report = await Cleaner.live().clean(chosen, source: String(localized: "Kopyalar"))
            isRemoving = false
            scan()
        }
    }
}

struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    private var model: DuplicatesModel { app.duplicates }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Kopya dosyalar"),
                       subtitle: model.hasScanned
                           ? String(localized: "\(model.groups.count) grup, \(model.wasted.bytes) gereksiz. Her grupta en eski dosya korunur. Yalnız İndirilenler'deki kopyalar seçili gelir; Masaüstü ve Belgeler'dekilere (projeler) sen karar ver.")
                           : String(localized: "İndirilenler, Masaüstü, Belgeler, Resimler, Filmler ve Müzik'te birebir aynı olan 1 MB üstü dosyaları bulur.")) {
                Button(model.hasScanned ? String(localized: "Yeniden tara") : String(localized: "Tara")) { model.scan() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
                    .disabled(model.isScanning)
            }
            if let report = model.report {
                ReportBanner(report: report) { model.report = nil }
            }
            if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "Taranıyor: \(model.progress)")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if !model.hasScanned {
                VStack(spacing: 16) {
                    Image(systemName: "doc.on.doc").font(.system(size: 44)).foregroundStyle(Theme.secondary)
                    PrimaryButton(title: String(localized: "Kopyaları bul")) { model.scan() }
                }
                .frame(maxHeight: .infinity)
            } else if model.groups.isEmpty {
                EmptyStateView(title: String(localized: "Kopya dosya yok"))
            } else {
                HStack(spacing: 14) {
                    SelectMenu(selected: model.allItems.selectedCount, total: model.allItems.count - model.groups.count,
                               onAll: { model.selectAllButOldest() }, onNone: { model.selectNone() })
                        .help(String(localized: "Tümünü seç: her gruptan en eski kopya kalır"))
                    Spacer()
                    SortMenu(key: $model.sortKey, options: [.size, .name])
                }
                .padding(.horizontal, 32).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.sortedGroups) { group in
                            Card {
                                HStack {
                                    Text(String(localized: "\(group.items.count) kopya · her biri \(group.size.bytes)"))
                                        .font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                ForEach(group.items) { item in
                                    ItemRowWithDate(item: item) { model.toggle(item, in: group) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            ToolActionBar(selectedSize: model.allItems.selectedSize, selectedCount: model.allItems.selectedCount,
                          actionTitle: String(localized: "Çöp'e taşı"), busy: model.isRemoving || model.isScanning) { model.confirm = true }
        }
        .glassConfirm(isPresented: $model.confirm, symbol: "trash", title: String(localized: "\(model.chosen.count) kopya Çöp'e taşınsın mı?"),
                      message: String(localized: "Her gruptan en az bir dosya kalır. Çöp'ü boşaltana kadar geri alınabilir."), confirm: String(localized: "Çöp'e taşı")) { model.removeSelected() }
    }
}
