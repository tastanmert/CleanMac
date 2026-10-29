import AppKit
import SwiftUI
import CleanMacCore

@Observable
final class UpdaterModel {
    var updates: [Updater.Update] = []
    var isChecking = false
    var hasChecked = false
    var working: Set<String> = []
    var message: String?
    /// A Homebrew upgrade downloads and installs right away: it waits for a yes.
    var pendingBrew: Updater.Update?
    var confirmBrew = false

    func check() {
        isChecking = true
        Task {
            updates = await Updater.check()
            isChecking = false
            hasChecked = true
        }
    }

    func update(_ update: Updater.Update) {
        switch update.source {
        case .sparkle:
            if let app = update.app { NSWorkspace.shared.open(app) }
            message = String(localized: "\(update.name) açıldı. Uygulamanın menüsünden \"Güncellemeleri Denetle\"yi seç; güncellemeyi uygulama kendisi kurar.")
        case .system:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") { NSWorkspace.shared.open(url) }
        case .homebrew:
            guard let token = update.token else { return }
            working.insert(update.id)
            Task {
                let result = await Shell.run("/bin/zsh", ["-lc", "brew upgrade --cask \(Shell.quote(token))"], timeout: Shell.actionTimeout)
                working.remove(update.id)
                if result.status == 0 {
                    updates.removeAll { $0 == update }
                    message = String(localized: "\(update.name) güncellendi.")
                } else {
                    message = String(localized: "\(update.name) güncellenemedi: \(result.output.suffix(160))")
                }
            }
        }
    }
}

struct UpdaterView: View {
    @Environment(AppModel.self) private var app
    private var model: UpdaterModel { app.updater }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Güncellemeler"),
                       subtitle: String(localized: "Sparkle ile güncellenen uygulamaların kendi duyuru akışlarını, Homebrew uygulamalarını ve macOS'u denetler. CleanMac kendisi indirme yapmaz: Homebrew uygulamalarını onayınla Homebrew günceller, diğerlerini uygulamanın kendisi ya da Sistem Ayarları.")) {
                Button(model.hasChecked ? String(localized: "Yeniden denetle") : String(localized: "Denetle")) { model.check() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
                    .disabled(model.isChecking)
            }
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.safe).padding(.horizontal, 32).padding(.bottom, 8)
            }
            if model.isChecking {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "Güncellemeler denetleniyor…")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if !model.hasChecked {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.app").font(.system(size: 44)).foregroundStyle(Theme.secondary)
                    PrimaryButton(title: String(localized: "Güncellemeleri denetle")) { model.check() }
                }
                .frame(maxHeight: .infinity)
            } else if model.updates.isEmpty {
                EmptyStateView(title: String(localized: "Her şey güncel"), message: String(localized: "Denetlenen uygulamaların ve macOS'un yeni sürümü yok."), symbol: "checkmark.seal")
            } else {
                ScrollView {
                    Card {
                        ForEach(model.updates) { update in
                            HStack(spacing: 12) {
                                Image(nsImage: icon(update)).resizable().frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(update.name).font(.system(size: 13, weight: .medium))
                                    Text("\(update.current) → \(update.latest) · \(sourceName(update.source))")
                                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                                }
                                Spacer()
                                if model.working.contains(update.id) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button(update.source == .homebrew ? String(localized: "Güncelle") : String(localized: "Aç")) {
                                        if update.source == .homebrew { model.pendingBrew = update; model.confirmBrew = true } else { model.update(update) }
                                    }.controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 9)
                        }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 20)
                }
            }
        }
        .onAppear { if !model.hasChecked && !model.isChecking { model.check() } }
        .glassConfirm(isPresented: Bindable(model).confirmBrew, symbol: "arrow.down.circle",
                      title: String(localized: "\(model.pendingBrew?.name ?? String(localized: "Uygulama")) güncellensin mi?"),
                      message: String(localized: "Homebrew yeni sürümü indirip kurar (\(model.pendingBrew.map { "\($0.current) → \($0.latest)" } ?? "")). Uygulama açıksa önce kapat."),
                      confirm: String(localized: "Güncelle"), destructive: false) { if let update = model.pendingBrew { model.update(update) } }
    }

    private func icon(_ update: Updater.Update) -> NSImage {
        if let app = update.app { return NSWorkspace.shared.icon(forFile: app.path) }
        if update.source == .system { return NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app") }
        if let url = NSWorkspace.shared.urlsForApplications(toOpen: URL(filePath: "/")).first(where: {
            $0.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-") == update.token
        }) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func sourceName(_ source: Updater.Source) -> String {
        switch source {
        case .sparkle: String(localized: "uygulamanın kendi güncelleyicisi")
        case .homebrew: "Homebrew"
        case .system: "macOS"
        }
    }
}
