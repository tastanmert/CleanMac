import SwiftUI
import CleanMacCore

/// What an in-window dialog shows. CleanMac draws its own glass cards for these instead of macOS alerts;
/// so does CleanMac: a dimmed window, one glass card, rounded pill buttons in the module's colour.
struct GlassDialogModel: Identifiable {
    struct Action: Identifiable {
        enum Role { case primary, destructive, cancel }
        let id = UUID()
        let title: String
        var role: Role = .primary
        var run: () -> Void = {}
    }
    let id = UUID()
    var symbol: String
    var title: String
    var message: String?
    var actions: [Action]
}

extension View {
    /// A drop-in for `.confirmationDialog` that shows the glass card instead of the system alert.
    func glassConfirm(isPresented: Binding<Bool>, symbol: String = "questionmark", title: String, message: String? = nil,
                      confirm: String, destructive: Bool = true, cancel: String = String(localized: "Vazgeç"),
                      action: @escaping () -> Void) -> some View {
        modifier(GlassConfirm(isPresented: isPresented, symbol: symbol, title: title, message: message,
                              confirm: confirm, destructive: destructive, cancel: cancel, action: action))
    }
}

private struct GlassConfirm: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    let symbol: String, title: String, message: String?, confirm: String, destructive: Bool, cancel: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { _, on in
            guard on else { return }
            isPresented = false
            app.dialog = GlassDialogModel(symbol: symbol, title: title, message: message, actions: [
                .init(title: cancel, role: .cancel),
                .init(title: confirm, role: destructive ? .destructive : .primary, run: action),
            ])
        }
    }
}

/// Sits over the whole window: shows `AppModel.dialog` (or the clean confirmation) on a dimmed backdrop.
struct GlassDialogHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modulePalette) private var palette

    private var visible: Bool { model.dialog != nil || model.showConfirm || model.showFDA || model.panel != nil }

    var body: some View {
        ZStack {
            if visible {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { dismissOnBackdrop() }
                Group {
                    if let dialog = model.dialog {
                        DialogCard(dialog: dialog, palette: palette) { model.dialog = nil }
                    } else if let panel = model.panel {
                        Group {
                            switch panel {
                            case .permissions: PermissionsView()
                            case .wifi: WiFiNetworksView()
                            case .log(let title, let lines): LogPanel(title: title, lines: lines)
                            case .update: SelfUpdatePanel()
                            }
                        }
                        .glassCard(palette: palette)
                    } else if model.showFDA {
                        FullDiskAccessCard(palette: palette) { model.showFDA = false }
                    } else {
                        ConfirmCard(palette: palette)
                    }
                }
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.dialog?.id)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.showConfirm)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.showFDA)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.panel)
        .allowsHitTesting(visible)
    }

    private func dismissOnBackdrop() {
        if model.dialog != nil { model.dialog = nil } else if model.panel != nil { model.panel = nil } else if model.showFDA { model.showFDA = false } else { model.showConfirm = false }
    }
}

private struct DialogCard: View {
    let dialog: GlassDialogModel
    let palette: Palette
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            OrbBadge(symbol: dialog.symbol, palette: palette)
            VStack(spacing: 6) {
                Text(dialog.title).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
                if let message = dialog.message {
                    Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                ForEach(dialog.actions) { action in
                    DialogButton(title: action.title, role: action.role, palette: palette) {
                        close()
                        action.run()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 340)
        .glassCard(palette: palette)
    }
}

/// The big clean confirmation keeps its content list; only the frame around it is the glass card.
private struct ConfirmCard: View {
    let palette: Palette
    var body: some View {
        ConfirmSheet()
            .frame(width: 480)
            .glassCard(palette: palette)
    }
}

private struct OrbBadge: View {
    let symbol: String
    let palette: Palette
    var body: some View {
        ZStack {
            Circle().fill(palette.orb).frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: palette.glow.opacity(0.5), radius: 14, y: 6)
            Image(systemName: symbol).font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
        }
    }
}

struct DialogButton: View {
    let title: String
    var role: GlassDialogModel.Action.Role = .primary
    let palette: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let button = Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 6).frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Capsule().fill(fill).brightness(hovering ? 0.08 : 0))
                .overlay(Capsule().strokeBorder(.white.opacity(role == .cancel ? 0.16 : 0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        if role == .cancel { button.keyboardShortcut(.cancelAction) } else { button.keyboardShortcut(.defaultAction) }
    }

    private var fill: AnyShapeStyle {
        switch role {
        case .cancel: AnyShapeStyle(Color.white.opacity(0.09))
        case .destructive: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF7A59), Color(hex: 0xE5484D)], startPoint: .top, endPoint: .bottom))
        case .primary: AnyShapeStyle(palette.orb)
        }
    }
}

extension View {
    /// Thick dark glass: frosted material under a module-tinted wash, bright rim, soft coloured shadow.
    func glassCard(palette: Palette) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: palette.orbA).opacity(0.28), Color.black.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: palette.glow.opacity(0.28), radius: 40, y: 18)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}


/// Asks for Full Disk Access on a start screen of its own: what it unlocks, one button to the
/// Settings page, a way to skip, and a success state that appears as soon as the permission is on.
private struct FullDiskAccessCard: View {
    let palette: Palette
    let close: () -> Void
    @State private var granted = FullDiskAccess.isGranted

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(palette.orb).frame(width: 78, height: 78)
                    .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                    .shadow(color: palette.glow.opacity(0.55), radius: 20, y: 8)
                Image(systemName: granted ? "checkmark" : "lock.open.fill")
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(spacing: 8) {
                Text(granted ? String(localized: "Tam Disk Erişimi verildi!") : String(localized: "Tam Disk Erişimi ver"))
                    .font(.system(size: 20, weight: .bold))
                Text(granted
                     ? String(localized: "Daha derin temizlik, daha eksiksiz tarama ve depolama üzerinde daha fazla denetim artık açık.")
                     : String(localized: "CleanMac'in gizli sistem çöpünü, sandbox uygulama önbelleklerini ve Mail eklerini bulabilmesi için izin ver. Hiçbir şey sen onaylamadan silinmez."))
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !granted {
                HStack(spacing: 8) {
                    ForEach([String(localized: "Tam koruma"), String(localized: "Daha çok çöp"), String(localized: "Dosya denetimi")], id: \.self) { tag in
                        Text(tag).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    }
                }
            }
            if granted {
                DialogButton(title: String(localized: "Başla"), palette: palette) { close() }
            } else {
                VStack(spacing: 8) {
                    DialogButton(title: String(localized: "Tam Disk Erişimi ver"), palette: palette) { PermissionsModel.openFullDiskAccess() }
                    DialogButton(title: String(localized: "Şimdilik geç"), role: .cancel, palette: palette) { close() }
                }
            }
        }
        .padding(28)
        .frame(width: 400)
        .glassCard(palette: palette)
        // Granting happens in System Settings; the card flips to its success state when the app is active again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            withAnimation(.smooth) { granted = FullDiskAccess.isGranted }
        }
        .task {
            // Also poll while the card is open: the switch in Settings may be flipped without leaving the app.
            while !Task.isCancelled && !granted {
                try? await Task.sleep(for: .seconds(1.5))
                if FullDiskAccess.isGranted { withAnimation(.smooth) { granted = true } }
            }
        }
    }
}


/// What a cleanup did, item by item, with a copy button.
struct LogPanel: View {
    let title: String
    let lines: [AppModel.LogLine]
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 20, weight: .bold))
                    Text(String(localized: "\(lines.filter(\.ok).count) tamam · \(lines.filter { !$0.ok }.count) hata"))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { model.panel = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(.borderless).foregroundStyle(Theme.secondary).keyboardShortcut(.cancelAction)
            }
            .padding(20)
            if lines.isEmpty {
                EmptyStateView(title: String(localized: "Kayıt yok"), message: String(localized: "Bu çalıştırmada işlenen öğe olmadı."), symbol: "doc.text")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: line.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(line.ok ? Theme.safe : Theme.review)
                                Text(line.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(line.note).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            HStack {
                Button(String(localized: "Günlük klasörünü aç")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CleanMac"))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button(copied ? String(localized: "Kopyalandı") : String(localized: "Panoya kopyala")) {
                    let text = lines.map { "\($0.ok ? "✓" : "✗") \($0.title) — \($0.note)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .buttonStyle(.borderless).font(.system(size: 12, weight: .semibold))
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
    }
}
