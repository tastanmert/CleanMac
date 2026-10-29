import AppKit
import SwiftUI
import CleanMacCore

// MARK: - Summary

struct ResultsSummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.sessionModule == .smart {
            SmartResultsView()
        } else {
            moduleSummary
        }
    }

    private var moduleSummary: some View {
        let module = model.module
        return VStack(spacing: 0) {
            HStack {
                Button { model.showResetConfirm = true } label: {
                    Label(String(localized: "Baştan başla"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
                Spacer()
                if model.sessionModule == .protection {
                    Button { model.panel = .wifi } label: { Label(String(localized: "Wi‑Fi ağları"), systemImage: "wifi") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.secondary)
                    Button { model.panel = .permissions } label: { Label(String(localized: "Uygulama izinleri"), systemImage: "hand.raised") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
                FullDiskAccessBanner().padding(.top, 8)

            GlassOrb(module: module, size: 84, floating: false)
            VStack(spacing: 8) {
                Text(model.foundSize > 0 ? String(localized: "\(model.foundSize.bytes) temizlenebilir alan bulundu") : String(localized: "Temizlenecek bir şey yok"))
                    .font(.system(size: 26, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(model.selectedSize > 0
                     ? String(localized: "\(model.selectedSize.bytes) güvenli olarak seçildi. Gözden geçir etiketliler sen seçmedikçe silinmez.")
                     : model.foundSize > 0 ? String(localized: "Hiçbiri seçili gelmedi: gözden geçir, istediklerini kendin seç.")
                     : String(localized: "Mac'in bu açıdan temiz görünüyor."))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                if model.foundSize > 0 {
                    Button(String(localized: "Ayrıntıları incele")) { model.review() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 40)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(model.resultCategories, id: \.category) { entry in
                        BentoCard(title: entry.category.title,
                                  value: model.size(of: entry.category).bytes,
                                  caption: String(localized: "\(model.selectedSize(of: entry.category).bytes) seçili"),
                                  module: module,
                                  checkState: model.hasBulkChoice(model.results.filter { $0.rule.category == entry.category })
                                      ? model.checkState(of: entry.category) : nil,
                                  onToggle: { model.setSelected(model.checkState(of: entry.category) == .off, category: entry.category) },
                                  onReview: { model.review(entry.category) })
                            .frame(height: 170)
                    }
                    if model.sessionModule == .junk, model.trashSize > 0 {
                        BentoCard(title: String(localized: "Çöp Kutuları"), value: model.trashSize.bytes,
                                  caption: String(localized: "Çöp ekranında onayınla boşaltılır"), module: module,
                                  checkState: nil, onToggle: {}, onReview: { model.open(.trash) })
                            .frame(height: 170)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 130)   // the last row scrolls clear of the button
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82),
                                         .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .padding(.bottom, -96)

            OrbButton(title: model.sessionModule == .smart ? String(localized: "Çalıştır") : String(localized: "Temizle"), palette: module.palette) { model.showConfirm = true }
                .disabled(!model.hasWork)
                .opacity(model.hasWork ? 1 : 0.45)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 6)
        }
    }
}

// MARK: - Smart scan results

/// "Your tasks are ready": the same 3 + 2 grid as the scan, each card with what it found, a checkbox
/// for what "Çalıştır" will do, and İncele, which opens that area's manager over the results.
struct SmartResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.scanGroups
        let rows = [Array(groups.prefix(3)), Array(groups.dropFirst(3))]
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button { model.showResetConfirm = true } label: { Label(String(localized: "Baştan başla"), systemImage: "chevron.left") }
                        .buttonStyle(.borderless).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(String(localized: "Akıllı Tarama")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button { model.panel = .permissions } label: { Label(String(localized: "Uygulama izinleri"), systemImage: "hand.raised") }
                        .buttonStyle(.borderless).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                FullDiskAccessBanner().padding(.top, 10)
                Text(model.hasWork ? String(localized: "Görevlerin hazır. Bulduklarımız:") : String(localized: "Her şey yolunda. Bulduklarımız:"))
                    .font(.system(size: 26, weight: .regular))
                    .padding(.top, 18).padding(.bottom, 18)
                VStack(spacing: 14) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 14) {
                            ForEach(rows[r]) { group in card(group) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 130)
            }
            .blur(radius: model.smartManager == nil ? 0 : 14)
            .overlay(alignment: .bottom) {
                OrbButton(title: String(localized: "Çalıştır"), palette: Module.smart.palette) { model.showConfirm = true }
                    .disabled(!model.hasWork)
                    .opacity(model.hasWork ? 1 : 0.45)
                    .keyboardShortcut(.defaultAction)
                    .padding(.bottom, 6)
                    .opacity(model.smartManager == nil ? 1 : 0)
            }

            if let manager = model.smartManager {
                SmartManagerPanel(group: manager)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: model.smartManager)
    }

    private func card(_ group: Module) -> some View {
        let summary = model.cardSummary(group)
        return BentoCard(title: group == .junk ? String(localized: "Temizlik") : group.title,
                         value: summary.value, caption: summary.caption, module: group,
                         checkState: model.isSelectable(group) ? model.checkState(of: group) : nil,
                         onToggle: { model.setSelected(model.checkState(of: group) == .off, group: group) },
                         onReview: (group == .junk || group == .protection) && model.size(in: group) == 0
                            ? nil : { model.reviewGroup(group) })
    }
}

/// A module's manager opened from a smart scan card: an inset glass panel with Back, over the results.
struct SmartManagerPanel: View {
    let group: Module
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.smartManager = nil } label: { Label(String(localized: "Geri"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary)
                Spacer()
                Text(String(localized: "\(group.title) Yöneticisi")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 18).padding(.top, 14)
            Group {
                switch group {
                case .performance: PerformanceView()
                case .applications: ApplicationsView()
                case .clutter: ClutterView()
                default: EmptyView()
                }
            }
            .padding(.top, -26)   // the tool views leave room for a title bar the panel already has
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: group.palette.top).opacity(0.92))
                GlassSlab(shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
                          tintA: Color(hex: group.palette.orbA), tintB: Color(hex: group.palette.orbB), depth: 8, strength: 0.18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .environment(\.modulePalette, group.palette)
    }
}

// MARK: - Review manager

/// Three columns: section (Sistem Çöpü, AI Dağınıklığı…) → subcategory → items,
/// with items gathered per app and opened in place.
struct ReviewManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var sortKey: SortKey = .size
    @State private var search = ""
    @State private var expanded: Set<String> = []

    private var sections: [String] {
        var seen: [String] = []
        for entry in model.reviewCategories where !seen.contains(entry.category.section) { seen.append(entry.category.section) }
        return seen
    }

    private var currentSection: String? { model.reviewCategory?.section }

    private var sectionCategories: [(category: CleanMacCore.Category, results: [CategoryResult])] {
        model.reviewCategories.filter { $0.category.section == currentSection }
    }

    private var categoryResults: [CategoryResult] {
        model.reviewCategories.first { $0.category == model.reviewCategory }?.results ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 12) {
                sectionColumn.frame(width: 156).glassPanel(strength: 0.08)
                categoryColumn.frame(width: 268).glassPanel(strength: 0.08)
                itemColumn.frame(maxWidth: .infinity).glassPanel(strength: 0.12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { model.backToSummary() } label: { Label(String(localized: "Geri"), systemImage: "chevron.left") }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(model.reviewTitle).font(.system(size: 14, weight: .semibold))
            Spacer()
            TextField(String(localized: "Ara"), text: $search).textFieldStyle(.roundedBorder).frame(width: 160)
            SortMenu(key: $sortKey)
        }
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 12)
    }

    private var sectionColumn: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(sections, id: \.self) { section in
                    let active = section == currentSection
                    Button {
                        model.reviewCategory = model.reviewCategories.first { $0.category.section == section }?.category
                        expanded = []
                    } label: {
                        Text(section).font(.system(size: 13, weight: active ? .semibold : .regular)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .rowPill(active: active)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private var categoryColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let section = currentSection {
                    Text(section).font(.system(size: 15, weight: .semibold)).padding(.horizontal, 10)
                    Text(sectionBlurb(section)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.bottom, 8)
                }
                ForEach(sectionCategories, id: \.category) { entry in
                    let active = entry.category == model.reviewCategory
                    let selected = model.selectedSize(of: entry.category)
                    Button {
                        model.reviewCategory = entry.category
                        expanded = []
                    } label: {
                        HStack(spacing: 12) {
                            CategoryTile(category: entry.category)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.category.title).font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text(model.size(of: entry.category).bytes).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                            }
                            Spacer(minLength: 0)
                            if selected > 0 {
                                Text(selected.bytes).font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .lineLimit(1).fixedSize()
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.glow.opacity(0.85)))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .rowPill(active: active)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private func sectionBlurb(_ section: String) -> String {
        switch section {
        case String(localized: "Sistem Çöpü"): String(localized: "Sistemin ve uygulamaların biriktirdiği, işe yaramayan dosyalar.")
        case String(localized: "AI Dağınıklığı"): String(localized: "AI uygulamalarının geçici dosyaları ve indirilmiş modeller. Kullanmadığını kaldır.")
        case String(localized: "Mail Ekleri"): String(localized: "Mail'in indirdiği ek kopyaları.")
        default: sectionCategories.first?.category.blurb ?? ""
        }
    }

    private var itemColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let category = model.reviewCategory, !categoryResults.isEmpty {
                let groups = groups(of: category)
                let entries = groups.flatMap(\.entries)
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title).font(.system(size: 17, weight: .semibold))
                    Text(category.blurb).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SelectMenu(selected: entries.filter(\.item.isSelected).count, total: entries.count,
                               onAll: { categoryResults.forEach { model.setAllSelected(true, in: $0.rule.id) } },
                               onNone: { categoryResults.forEach { model.setAllSelected(false, in: $0.rule.id) } },
                               extra: [(String(localized: "Akıllı seçimi uygula"), { categoryResults.forEach { model.applySmartSelection(in: $0.rule.id) } })])
                        .padding(.top, 4)
                }
                .padding(16)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            OwnerGroupRow(group: group, expanded: expanded.contains(group.id) || !search.isEmpty,
                                          onExpand: { toggle(group.id) },
                                          onToggle: { toggle(group) })
                            if expanded.contains(group.id) || !search.isEmpty, group.entries.count > 1 || group.icon != nil {
                                ForEach(sorted(group.entries)) { entry in
                                    ToolItemRow(item: entry.item, indent: 52, onIgnore: { model.ignore(entry.item, in: entry.ruleID) }) {
                                        model.setSelected(!entry.item.isSelected, item: entry.item, in: entry.ruleID)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            } else {
                EmptyStateView(title: String(localized: "Bu kategori boş"))
            }
        }
    }

    private func groups(of category: CleanMacCore.Category) -> [OwnerGroup] {
        let groups = OwnerGroups.groups(categoryResults, category: category).compactMap { group -> OwnerGroup? in
            guard !search.isEmpty else { return group }
            if group.name.localizedCaseInsensitiveContains(search) { return group }
            let hits = Set(group.entries.map(\.item).matching(search).map(\.id))
            let entries = group.entries.filter { hits.contains($0.id) }
            return entries.isEmpty ? nil : OwnerGroup(id: group.id, name: group.name, icon: group.icon, symbol: group.symbol, entries: entries)
        }
        switch sortKey {
        case .size: return groups.sorted { $0.size > $1.size }
        case .name: return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date: return groups.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
        }
    }

    private func sorted(_ entries: [ReviewEntry]) -> [ReviewEntry] {
        let order = entries.map(\.item).sorted(by: sortKey).map(\.id)
        return entries.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    /// The group's checkbox ticks only what the scanner recommends; "review" items and open apps' files stay a
    /// choice made on their own row, so a group that has only those opens to show them instead.
    private func toggle(_ group: OwnerGroup) {
        let recommended = group.entries.filter(\.item.isRecommended)
        let turnOn = group.checkState == .off
        if turnOn, recommended.isEmpty {
            if !expanded.contains(group.id) { toggle(group.id) }
            return
        }
        for entry in turnOn ? recommended : group.entries where entry.item.isSelected != turnOn {
            model.setSelected(turnOn, item: entry.item, in: entry.ruleID)
        }
    }

    private var footer: some View {
        ToolActionBar(selectedSize: model.selectedSize, selectedCount: model.selectedCount, actionTitle: String(localized: "Temizle")) {
            model.showConfirm = true
        }
    }
}

/// The colored square a subcategory carries in the manager's middle column.
struct CategoryTile: View {
    let category: CleanMacCore.Category

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(LinearGradient(colors: [category.tint, category.tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 36, height: 36)
            .overlay(Image(systemName: category.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
            .shadow(color: category.tint.opacity(0.35), radius: 6, y: 2)
    }
}

/// One app (or rule) in the item column: checkbox, icon, name, size, and a chevron that opens its files in place.
struct OwnerGroupRow: View {
    let group: OwnerGroup
    let expanded: Bool
    let onExpand: () -> Void
    let onToggle: () -> Void
    @State private var hovering = false

    private var canExpand: Bool { group.entries.count > 1 || group.icon != nil }

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state: group.checkState, action: onToggle)
            Group {
                if let icon = group.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: group.symbol).font(.system(size: 16)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                if group.entries.count > 1 {
                    Text(String(localized: "\(group.entries.count) öğe")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                } else if let detail = group.entries.first?.item.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if group.isRecommended {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Theme.safe)
                    .help(String(localized: "Güvenle temizlenebilir; akıllı seçim bunu seçer"))
            } else if group.entries.contains(where: \.item.appIsOpen) {
                Text(String(localized: "app.running", defaultValue: "Açık")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.review)
                    .help(String(localized: "Uygulama açık; kapatınca seçilebilir"))
            }
            Text(group.size.bytes).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
                .frame(minWidth: 64, alignment: .trailing)
            Button(action: onExpand) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(canExpand ? Theme.glow : .clear)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(hovering ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if canExpand { onExpand() } }
        .onHover { hovering = $0 }
    }
}

// MARK: - Confirm

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modulePalette) private var palette

    private var rows: [(CleanRule, Int, Int64)] {
        model.results.compactMap { r in
            let items = r.items.filter(\.isSelected)
            return items.isEmpty ? nil : (r.rule, items.count, items.reduce(0) { $0 + $1.size })
        }
    }

    /// Selections that deserve a second look, with the reason, asked about before anything is removed.
    private var warnings: [String] {
        let selected = Set(model.results.filter { $0.items.contains(where: \.isSelected) }.map(\.rule.id))
        var notes: [String] = []
        if !selected.isDisjoint(with: ["ollama", "localModels", "hfCache"]) {
            notes.append(String(localized: "Seçtiğin yapay zekâ modelleri projelerinde hâlâ kullanılıyor olabilir. Silersen yeniden indirene kadar hata alabilirsin."))
        }
        if selected.contains("iosBackups") {
            notes.append(String(localized: "Seçimde bir cihazın en son yedeği olabilir. Silersen o cihazı mevcut durumuna geri yükleyemezsin."))
        }
        if selected.contains("claudeVM") {
            notes.append(String(localized: "Claude'un sanal makine paketleri silinirse Cowork ilk kullanımda birkaç GB'ı yeniden indirir."))
        }
        return notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedSize > 0 ? String(localized: "\(model.selectedSize.bytes) temizlensin mi?") : String(localized: "Seçili görevler çalıştırılsın mı?"))
                    .font(.system(size: 20, weight: .bold))
                Text(String(localized: "Dosyalar Çöp'e taşınır; Çöp'ü boşaltana kadar geri alabilirsin. Simülatörler, iOS sürümleri, modeller ve paket yöneticisi önbellekleri kendi komutlarıyla hemen silinir."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.0.id) { rule, count, size in
                        HStack {
                            Image(systemName: rule.symbol).frame(width: 20).foregroundStyle(.secondary)
                            Text(rule.title)
                            Text(String(localized: "\(count) öğe")).foregroundStyle(.tertiary)
                            Spacer()
                            Text(size.bytes).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 6)
                        Divider()
                    }
                    ForEach(model.selectedTaskList) { task in
                        HStack {
                            Image(systemName: task.symbol).frame(width: 20).foregroundStyle(.secondary)
                            Text(task.title)
                            Spacer()
                            Text(task.needsAdmin ? String(localized: "parola ister") : String(localized: "bakım")).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 260)
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warnings, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.review)
                            .labelStyle(.titleAndIcon)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.review.opacity(0.12)))
            }
            HStack(spacing: 10) {
                DialogButton(title: String(localized: "Vazgeç"), role: .cancel, palette: palette) { model.showConfirm = false }
                DialogButton(title: warnings.isEmpty ? String(localized: "Temizle") : String(localized: "Yine de temizle"), role: warnings.isEmpty ? .primary : .destructive,
                             palette: palette) { model.clean() }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Done

struct DoneView: View {
    let report: CleanReport
    @Environment(AppModel.self) private var model
    @State private var appeared = false
    @State private var counted: Double = 0

    private var total: Int64 { report.freedBytes + report.trashedBytes }

    var body: some View {
        let module = model.module
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            HStack(spacing: 56) {
                GlassOrb(module: module, size: 220)
                    .overlay(alignment: .bottomTrailing) {
                        let stopped = report.skippedCount > 0 || report.cleanedCount == 0
                        Image(systemName: stopped ? "stop.fill" : "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(stopped ? Theme.review : Theme.safe)
                                .shadow(color: (stopped ? Theme.review : Theme.safe).opacity(0.6), radius: 12))
                            .scaleEffect(appeared ? 1 : 0.2)
                            .opacity(appeared ? 1 : 0)
                            .offset(x: -18, y: -30)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .offset(y: appeared ? 0 : 40)
                    .opacity(appeared ? 1 : 0)
                VStack(alignment: .leading, spacing: 14) {
                    Text(report.skippedCount > 0 ? String(localized: "Durduruldu") : report.cleanedCount == 0 ? String(localized: "Temizlenemedi")
                         : report.failures.isEmpty ? String(localized: "İş tamam!") : String(localized: "Büyük kısmı tamam"))
                        .font(.system(size: 40, weight: .regular))
                    CountingBytes(value: counted)
                        .font(.system(size: 54, weight: .semibold).monospacedDigit())
                    Text((report.trashedBytes > 0
                          ? String(localized: "\(report.cleanedCount) öğe temizlendi. \(report.trashedBytes.bytes) Çöp'te bekliyor; Çöp'ü boşaltınca alan açılır.")
                          : report.cleanedCount > 0 ? String(localized: "\(report.cleanedCount) öğe temizlendi. Mac'inde artık daha fazla yer var.")
                          : String(localized: "Hiçbir öğe temizlenmedi."))
                         + (report.skippedCount > 0 ? String(localized: " Durdurduğun için \(report.skippedCount) öğeye dokunulmadı; yeniden tarayıp devam edebilirsin.") : ""))
                        .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340, alignment: .leading)
                    if !report.failures.isEmpty {
                        DisclosureGroup(String(localized: "\(report.failures.count) öğe temizlenemedi")) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(report.failures) { f in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(f.title): \(f.reason)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                        if let url = f.revealURL {
                                            Button(String(localized: "Finder'da göster")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                                .buttonStyle(.borderless).font(.system(size: 11, weight: .semibold))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12))
                        .frame(maxWidth: 340)
                    }
                    HStack(spacing: 16) {
                        if report.trashedBytes > 0 {
                            Button(String(localized: "Çöp'e git")) {
                                model.openedTools.insert(.trash)
                                model.select(.trash)
                            }
                        }
                        Button(String(localized: "Günlüğü göster")) {
                            model.panel = .log(String(localized: "\(model.sessionModule.title) günlüğü"),
                                               report.entries.map { AppModel.LogLine(ok: $0.ok, title: $0.title, note: $0.note) })
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 4)
                }
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : 24)
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            OrbButton(title: String(localized: "Bitti"), palette: module.palette) { model.reset() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeOut(duration: 1.4).delay(0.25)) { counted = Double(total) }
        }
    }
}

/// A byte count that runs up through every value while it animates.
struct CountingBytes: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { Text(Int64(value).bytes) }
}
