import AppKit
import SwiftUI
import CleanMacCore

// MARK: - Startup items

@Observable
final class StartupModel {
    var items: [StartupItems.Item] = []
    var isLoading = false
    var error: String?

    func load() {
        isLoading = true
        Task {
            items = await StartupItems.list()
            isLoading = false
        }
    }

    func setEnabled(_ enabled: Bool, _ item: StartupItems.Item) {
        Task {
            let ok = await StartupItems.setEnabled(enabled, item)
            error = ok ? nil : String(localized: "\(item.label) değiştirilemedi.")
            load()
        }
    }

    func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct StartupView: View {
    @Environment(AppModel.self) private var app
    private var model: StartupModel { app.startup }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Başlangıç öğeleri"),
                       subtitle: String(localized: "Mac açılınca arka planda çalışan servisler. Senin hesabındakileri buradan kapatıp açabilirsin (geri alınabilir). Sistem genelindekiler yönetici izni ister; onları Sistem Ayarları'ndan yönet.")) {
                Button(String(localized: "Giriş öğeleri ayarları")) { model.openLoginItemsSettings() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
            }
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.review).padding(.bottom, 8)
            }
            if model.isLoading && model.items.isEmpty {
                ProgressView().frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        section(String(localized: "Senin hesabın"), model.items.filter(\.isUserAgent))
                        section(String(localized: "Tüm kullanıcılar (salt okunur)"), model.items.filter { !$0.isUserAgent })
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { model.load() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [StartupItems.Item]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            Card {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.isRunning ? Theme.safe : Theme.tertiary.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .help(item.isRunning ? String(localized: "Çalışıyor") : String(localized: "Çalışmıyor"))
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.owningApp?.path ?? item.plist.path))
                            .resizable().frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.owningApp.map { $0.deletingPathExtension().lastPathComponent } ?? item.label)
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(item.owningApp == nil ? item.program : item.label).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if item.isBroken {
                            Text(String(localized: "Bozuk")).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.review.opacity(0.25)))
                                .help(String(localized: "Başlatacağı program artık yok. Sistem Çöpü taramasında temizlenebilir."))
                        }
                        RevealButton(url: item.plist)
                        if item.isUserAgent {
                            Toggle("", isOn: Binding(get: { !item.isDisabled }, set: { model.setEnabled($0, item) }))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .tint(Theme.glow)
                        } else {
                            Text(item.isDisabled ? String(localized: "Kapalı") : String(localized: "Açık")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Trash

@Observable
final class TrashModel {
    var count: Int?
    var size: Int64 = 0
    var message: String?
    var confirm = false
    var isEmptying = false
    var bins: [TrashBins.Bin] = []

    func load() {
        Task {
            bins = await Task.detached { TrashBins.list() }.value
            if let result = await Self.finder("count of items of trash") { count = Int(result) }
            else { message = Self.permissionHint }
            // Readable only when CleanMac has Full Disk Access; otherwise stays 0 and is hidden.
            size = await Task.detached {
                Scanner.allocatedSize(of: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
            }.value
        }
    }

    func empty() {
        isEmptying = true
        let before = DiskSpace.current().available
        Task {
            if await Self.finder("empty trash") == nil {
                message = Self.permissionHint
            } else {
                let freed = DiskSpace.current().available - before
                message = freed > 0 ? String(localized: "Çöp boşaltıldı · \(freed.bytes) yer açıldı.") : String(localized: "Çöp boşaltıldı.")
            }
            isEmptying = false
            load()
        }
    }

    static let permissionHint = String(localized: "Finder'a erişim izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'dan CleanMac için Finder'ı aç.")

    /// Runs a Finder command in a separate process so a permission prompt never freezes the window;
    /// nil when it fails or Automation permission is denied.
    static func finder(_ command: String) async -> String? {
        let result = await Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to \(command)"])
        return result.status == 0 ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
}

struct TrashView: View {
    @Environment(AppModel.self) private var app
    private var model: TrashModel { app.trash }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: (model.count ?? 0) > 0 ? "trash.fill" : "trash")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [Theme.glow, Theme.glowDeep], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(String(localized: "CleanMac dosyaları önce Çöp'e taşır; disk alanı Çöp boşaltılınca açılır. Boşaltılan dosyalar geri alınamaz. (Araç önbellekleri ve simülatörler kendi komutlarıyla hemen silinir.)"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            if model.bins.count > 1 || model.bins.contains(where: { $0.size > 0 }) {
                VStack(spacing: 0) {
                    ForEach(model.bins) { bin in
                        HStack(spacing: 12) {
                            Image(systemName: bin.isExternal ? "externaldrive.fill" : "trash.fill")
                                .frame(width: 22).foregroundStyle(Theme.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bin.isExternal ? String(localized: "\(bin.name) çöpü") : String(localized: "Ana Çöp")).font(.system(size: 13, weight: .medium))
                                Text(String(localized: "\(bin.count) öğe")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            Text(bin.size > 0 ? bin.size.bytes : "—").font(.system(size: 13).monospacedDigit())
                            Button {
                                NSWorkspace.shared.open(bin.url)
                            } label: { Image(systemName: "arrow.right.circle") }
                                .buttonStyle(.plain).help(String(localized: "Finder'da göster"))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if bin != model.bins.last { Divider().opacity(0.3) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
                .frame(maxWidth: 460)
            }
            if let message = model.message {
                Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.safe)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            HStack(spacing: 14) {
                Button(String(localized: "Çöp'ü aç")) { app.openTrash() }
                PrimaryButton(title: String(localized: "Çöp'ü boşalt"), enabled: (model.count ?? 0) > 0 && !model.isEmptying) { model.confirm = true }
            }
            Spacer()
        }
        .padding(40)
        .onAppear { model.load() }
        .glassConfirm(isPresented: $model.confirm, symbol: "trash.slash", title: String(localized: "Çöp kalıcı olarak boşaltılsın mı?"),
                      message: model.bins.count > 1 ? String(localized: "Bağlı disklerin çöpleri de boşalır. Bu işlem geri alınamaz.") : String(localized: "Bu işlem geri alınamaz."),
                      confirm: String(localized: "Çöp'ü boşalt")) { model.empty() }
    }

    private var title: String {
        guard let count = model.count else { return String(localized: "Çöp") }
        if count == 0 { return String(localized: "Çöp boş") }
        return model.size > 0 ? String(localized: "Çöp'te \(count) öğe · \(model.size.bytes)") : String(localized: "Çöp'te \(count) öğe")
    }
}
