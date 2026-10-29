import AppKit
import SwiftUI
import CleanMacCore

/// CleanMac updating itself from the team's GitHub releases (see `SelfUpdate`): checked at launch and once a day
/// when "Güncellemeleri otomatik denetle" is on; a new version always waits for the user's "Güncelle".
@Observable
final class SelfUpdateModel {
    enum Phase: Equatable {
        case idle, checking
        case upToDate(String)
        case available(SelfUpdate.Release)
        case downloading(SelfUpdate.Release)
        case failed(String)
        case unavailable(String)
    }

    static let autoKey = "autoUpdateCheck"
    static let lastCheckKey = "lastUpdateCheck"
    var phase: Phase = .idle

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    /// `swift run` has no app bundle to replace.
    var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var isBusy: Bool {
        switch phase { case .checking, .downloading: true; default: false }
    }

    /// Checks GitHub; returns true when a newer version is waiting.
    @discardableResult
    func check() async -> Bool {
        guard !isBusy else { return false }
        phase = .checking
        UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        switch await SelfUpdate.check(current: current) {
        case .upToDate(let latest): phase = .upToDate(latest)
        case .available(let release): phase = .available(release); return true
        case .unavailable(let why): phase = .unavailable(why)
        }
        return false
    }

    func install(_ release: SelfUpdate.Release) {
        guard canInstall, !isBusy, let bundleID = Bundle.main.bundleIdentifier else { return }
        phase = .downloading(release)
        Task {
            do {
                let staged = try await SelfUpdate.prepare(release, bundleID: bundleID)
                try SelfUpdate.install(staged, replacing: Bundle.main.bundleURL)
                NSApp.terminate(nil)   // the install script waits for this, then swaps the app and opens it
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    /// Launch and every hour after: a check when the last one is a day old and automatic checks are on.
    /// Only a new version opens the card; quiet otherwise.
    func runAutomaticChecks(show: @escaping () -> Void) async {
        while !Task.isCancelled {
            let on = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
            let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
            if on, canInstall, Date.now.timeIntervalSince(last) > 86_400, await check() { show() }
            try? await Task.sleep(for: .seconds(3_600))
        }
    }
}

/// The glass panel for CleanMac's own update: what is new, and one button to install and relaunch.
struct SelfUpdatePanel: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SelfUpdateModel.autoKey) private var automatic = true
    private var model: SelfUpdateModel { app.selfUpdate }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 20, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { app.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary).keyboardShortcut(.cancelAction)
                    .disabled(isDownloading)
            }
            if let notes {
                ScrollView {
                    Text(notes).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
            }
            HStack {
                Toggle(String(localized: "Otomatik denetle"), isOn: $automatic)
                    .toggleStyle(.switch).controlSize(.small).tint(Theme.glow).fixedSize()
                    .help(String(localized: "Açılışta ve günde bir kez yeni sürüm var mı diye bakar; kurmadan önce sorar."))
                Spacer()
                actions
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var isDownloading: Bool { if case .downloading = model.phase { true } else { false } }

    @ViewBuilder private var actions: some View {
        switch model.phase {
        case .available(let release):
            Button(String(localized: "Sonra")) { app.panel = nil }.buttonStyle(.borderless).foregroundStyle(Theme.secondary)
            Button(String(localized: "Güncelle ve yeniden başlat")) { model.install(release) }
                .buttonStyle(.borderedProminent).tint(Theme.glow)
                .disabled(!model.canInstall)
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        default:
            Button(String(localized: "Yeniden denetle")) { Task { await model.check() } }.buttonStyle(.borderless).foregroundStyle(Theme.secondary)
        }
    }

    private var title: String {
        switch model.phase {
        case .available(let r): String(localized: "CleanMac \(r.version) hazır")
        case .downloading(let r): String(localized: "CleanMac \(r.version) kuruluyor…")
        case .checking, .idle: String(localized: "Güncellemeler denetleniyor…")
        case .upToDate: String(localized: "CleanMac güncel")
        case .failed: String(localized: "Güncelleme kurulamadı")
        case .unavailable: String(localized: "Güncellemeler denetlenemedi")
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .available(let r):
            (r.date.map { String(localized: "Şu an \(model.current) kullanıyorsun; \($0.formatted(date: .abbreviated, time: .omitted)) tarihinde yayınlandı.") }
                ?? String(localized: "Şu an \(model.current) kullanıyorsun."))
                + (model.canInstall ? String(localized: " Eski sürüm Çöp'e taşınır.") : String(localized: " Bu kopya buradan güncellenemez."))
        case .downloading: String(localized: "İndirilip doğrulanıyor; bitince CleanMac kapanıp yeni sürümle açılır.")
        case .upToDate(let latest): String(localized: "Kullandığın \(model.current), en son sürüm \(latest).")
        case .failed(let why), .unavailable(let why): why
        case .checking, .idle: String(localized: "GitHub'daki son sürüme bakılıyor.")
        }
    }

    /// Release notes as plain text: Markdown headings and bold marks dropped.
    private var notes: String? {
        guard case .available(let r) = model.phase, !r.notes.isEmpty else { return nil }
        return r.notes.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
