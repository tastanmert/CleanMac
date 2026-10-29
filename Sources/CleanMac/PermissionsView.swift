import AppKit
import SwiftUI
import CleanMacCore

@Observable
final class PermissionsModel {
    var grants: [Permissions.Grant] = []
    var noAccess = false
    var isLoading = false
    var search = ""

    func load() {
        isLoading = true
        Task {
            switch await Permissions.list() {
            case .success(let grants):
                self.grants = grants.filter(\.allowed)
                noAccess = false
            case .failure:
                noAccess = true
            }
            isLoading = false
        }
    }

    func reset(_ grant: Permissions.Grant) {
        Task {
            if await Permissions.reset(grant) { grants.removeAll { $0 == grant } }
        }
    }

    var groups: [(service: String, grants: [Permissions.Grant])] {
        let visible = search.isEmpty ? grants : grants.filter {
            Self.appName($0.client).localizedCaseInsensitiveContains(search)
                || (Permissions.serviceNames[$0.service] ?? "").localizedCaseInsensitiveContains(search)
        }
        return Dictionary(grouping: visible, by: \.service)
            .map { ($0.key, $0.value) }
            .sorted { (Permissions.serviceNames[$0.service] ?? "") < (Permissions.serviceNames[$1.service] ?? "") }
    }

    static func appURL(_ client: String) -> URL? {
        client.hasPrefix("/") ? URL(filePath: client) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: client)
    }

    static func appName(_ client: String) -> String {
        appURL(client).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? client
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
    }
}

/// Which apps may use the camera, microphone, screen, files… with a way to take a permission back.
struct PermissionsView: View {
    @State private var model = PermissionsModel()
    @Environment(AppModel.self) private var app
    private func dismiss() { app.panel = nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Uygulama izinleri")).font(.system(size: 20, weight: .bold))
                    Text(String(localized: "İzni kaldırınca uygulama bir dahaki sefere yeniden sorar.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                TextField(String(localized: "Ara"), text: $model.search).textFieldStyle(.roundedBorder).frame(width: 160)
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            if model.isLoading && model.grants.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.noAccess {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(String(localized: "İzin listesini okumak için Tam Disk Erişimi gerekli")).font(.system(size: 15, weight: .semibold))
                    Text(String(localized: "Sistem Ayarları > Gizlilik ve Güvenlik > Tam Disk Erişimi'nde CleanMac'i aç, sonra bu pencereyi yeniden aç."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                    HStack {
                        Button(String(localized: "Tam Disk Erişimi ayarları")) { PermissionsModel.openFullDiskAccess() }
                        Button(String(localized: "Gizlilik ayarları")) { PermissionsModel.openSettings() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.groups, id: \.service) { group in
                        Section(Permissions.serviceNames[group.service] ?? group.service) {
                            ForEach(group.grants) { grant in
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: PermissionsModel.appURL(grant.client)?.path ?? "/System/Applications"))
                                        .resizable().frame(width: 22, height: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(PermissionsModel.appName(grant.client)).font(.system(size: 12, weight: .medium))
                                        if let changed = grant.changed {
                                            Text(String(localized: "izin: \(changed.formatted(date: .abbreviated, time: .omitted))"))
                                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    Spacer()
                                    Button(String(localized: "İzni kaldır")) { model.reset(grant) }.controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .frame(width: 560, height: 520)
        .onAppear { model.load() }
    }
}


/// A slim note on result pages: the scan could not see everything without Full Disk Access.
struct FullDiskAccessBanner: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fdaBannerDismissed") private var dismissed = false
    @State private var granted = FullDiskAccess.isGranted

    var body: some View {
        if !granted && !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "lock.open.trianglebadge.exclamationmark").foregroundStyle(Theme.review)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Tarama eksik olabilir")).font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Tam Disk Erişimi olmadan sandbox uygulama önbellekleri ve Mail ekleri görünmez."))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button(String(localized: "Ayarları aç")) { model.showFDA = true }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(Theme.glowDeep)
                Button { dismissed = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary)
                    .help(String(localized: "Bir daha gösterme"))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .padding(.horizontal, 28)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                granted = FullDiskAccess.isGranted
            }
            .onChange(of: model.showFDA) { _, _ in granted = FullDiskAccess.isGranted }
        }
    }
}


@Observable
final class WiFiModel {
    var interface: String?
    var networks: [String] = []
    var isLoading = false
    var message: String?

    func load() {
        isLoading = true
        Task {
            interface = await WiFiNetworks.interface()
            if let interface { networks = await WiFiNetworks.saved(on: interface) }
            isLoading = false
        }
    }

    func forget(_ name: String) {
        guard let interface else { return }
        Task {
            if await WiFiNetworks.forget(name, on: interface) {
                networks.removeAll { $0 == name }
                message = String(localized: "\(name) unutuldu.")
            } else {
                message = String(localized: "\(name) unutulamadı (parola penceresi iptal edilmiş olabilir).")
            }
        }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") { NSWorkspace.shared.open(url) }
    }
}

/// Networks this Mac joins on its own. Old hotel or café networks are a privacy and security risk:
/// anyone can name a network the same and the Mac connects to it.
struct WiFiNetworksView: View {
    @State private var model = WiFiModel()
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Wi‑Fi ağları")).font(.system(size: 20, weight: .bold))
                    Text(String(localized: "Mac'in kendiliğinden bağlandığı kayıtlı ağlar. Artık kullanmadığın halka açık ağları unut: aynı adla kurulan sahte bir ağa otomatik bağlanma riskini azaltır."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { app.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.interface == nil {
                EmptyStateView(title: String(localized: "Wi‑Fi bulunamadı"), message: String(localized: "Bu Mac'te Wi‑Fi donanımı görünmüyor."), symbol: "wifi.slash")
            } else if model.networks.isEmpty {
                EmptyStateView(title: String(localized: "Kayıtlı ağ yok"), message: String(localized: "Mac hiçbir Wi‑Fi ağını hatırlamıyor."), symbol: "wifi")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.networks, id: \.self) { name in
                            HStack(spacing: 10) {
                                Image(systemName: "wifi").foregroundStyle(Theme.secondary).frame(width: 20)
                                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Spacer()
                                Button(String(localized: "Unut")) { model.forget(name) }
                                    .buttonStyle(.borderless).font(.system(size: 12, weight: .semibold))
                                    .help(String(localized: "Yönetici parolası ister"))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .rowPill(active: false)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            HStack {
                Text(String(localized: "\(model.networks.count) kayıtlı ağ")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                Spacer()
                Button(String(localized: "Wi‑Fi ayarlarını aç")) { WiFiModel.openSettings() }.buttonStyle(.borderless)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .onAppear { model.load() }
    }
}
