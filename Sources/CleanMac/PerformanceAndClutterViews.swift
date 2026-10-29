import SwiftUI
import CleanMacCore

// MARK: - Performance: maintenance + startup items

struct PerformanceView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            GlassTabs(selection: $tab, items: [(String(localized: "Bakım görevleri"), 0), (String(localized: "Başlangıç öğeleri"), 1), (String(localized: "Enerji"), 2)])
                .onAppear { if let requested = app.takeRequestedTab() { tab = requested } }
            .padding(.top, 40)
            Group {
                switch tab {
                case 0: MaintenanceView()
                case 1: StartupView()
                default: PowerView()
                }
            }
            .id(tab)
            .transition(.blurFade)
        }
        .animation(.easeInOut(duration: 0.3), value: tab)
    }
}

@Observable
final class MaintenanceModel {
    var selected: Set<String> = ["quicklook"]
    var running: String?
    var outcomes: [String: Maintenance.Outcome] = [:]

    var isRunning: Bool { running != nil }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func runSelected() {
        let tasks = Maintenance.tasks.filter { selected.contains($0.id) }
        outcomes = [:]
        Task {
            for task in tasks {
                running = task.id
                outcomes[task.id] = await Maintenance.run(task)
            }
            running = nil
        }
    }
}

struct MaintenanceView: View {
    @Environment(AppModel.self) private var app
    private var model: MaintenanceModel { app.maintenance }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Bakım görevleri"),
                       subtitle: String(localized: "Mac'i tazeleyen tek seferlik işler. Kilitli olanlar yönetici parolası ister; parolayı macOS'un kendi penceresine sen girersin."))
            ScrollView {
                Card {
                    ForEach(Maintenance.tasks) { task in
                        HStack(alignment: .top, spacing: 12) {
                            CheckBox(state: model.selected.contains(task.id) ? .on : .off) { model.toggle(task.id) }
                            Image(systemName: task.symbol).frame(width: 22).foregroundStyle(Theme.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(task.title).font(.system(size: 13, weight: .semibold))
                                    if task.needsAdmin {
                                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                                            .help(String(localized: "Yönetici parolası ister"))
                                    }
                                }
                                Text(task.explanation).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            status(for: task)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 32)
            }
            HStack {
                Text(String(localized: "\(model.selected.count) görev seçili")).font(.system(size: 13, weight: .medium))
                Spacer()
                if model.isRunning { ProgressView().controlSize(.small) }
                PrimaryButton(title: String(localized: "Çalıştır"), enabled: !model.selected.isEmpty && !model.isRunning) { model.runSelected() }
            }
            .padding(.horizontal, 32).padding(.vertical, 16)
            .background(Color.black.opacity(0.18))
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    @ViewBuilder private func status(for task: Maintenance.Task) -> some View {
        if model.running == task.id {
            ProgressView().controlSize(.small)
        } else if let outcome = model.outcomes[task.id] {
            Label(outcome.message, systemImage: outcome.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(outcome.ok ? Theme.safe : Theme.review)
                .lineLimit(2)
                .frame(maxWidth: 160, alignment: .trailing)
        }
    }
}

// MARK: - Clutter: large & old files, duplicates, old downloads

struct ClutterView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            GlassTabs(selection: $tab, items: [(String(localized: "Büyük ve eski"), 0), (String(localized: "Kopyalar"), 1), (String(localized: "Benzer görseller"), 3), (String(localized: "Eski indirilenler"), 2)])
                .onAppear { if let requested = app.takeRequestedTab() { tab = requested } }
            .padding(.top, 40)
            Group {
                switch tab {
                case 0: RuleItemsView(model: app.largeFiles, showsFilters: true, emptyTitle: String(localized: "100 MB üstü dosya yok"))
                case 1: DuplicatesView()
                case 3: SimilarImagesView()
                default: RuleItemsView(model: app.oldDownloads, showsFilters: true, emptyTitle: String(localized: "İndirilenler derli toplu"))
                }
            }
            .id(tab)
            .transition(.blurFade)
        }
        .animation(.easeInOut(duration: 0.3), value: tab)
    }
}

// MARK: - Applications: uninstaller, leftovers, installers

struct ApplicationsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            GlassTabs(selection: $tab, items: [(String(localized: "Kaldırıcı"), 0), (String(localized: "Güncellemeler"), 3), (String(localized: "Artık dosyalar"), 1), (String(localized: "Kurulum dosyaları"), 2)])
                .onAppear { if let requested = app.takeRequestedTab() { tab = requested } }
            .padding(.top, 40)
            Group {
                switch tab {
                case 0: UninstallerView()
                case 1: RuleItemsView(model: app.orphans, emptyTitle: String(localized: "Kaldırılmış uygulamalardan artık yok"))
                case 3: UpdaterView()
                default: RuleItemsView(model: app.installers, emptyTitle: String(localized: "Kurulum dosyası yok"))
                }
            }
            .id(tab)
            .transition(.blurFade)
        }
        .animation(.easeInOut(duration: 0.3), value: tab)
    }
}
