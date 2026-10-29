import AppKit
import SwiftUI
import CleanMacCore

// MARK: - Energy & performance check-up

@Observable
final class PowerModel {
    var findings: [PowerAudit.Finding] = []
    var score: Int?
    var history: [PowerAudit.Snapshot] = PowerAudit.history()
    var isScanning = false
    var busy: String?
    /// Findings fixed in this session, so they can be undone.
    var applied: Set<String> = []
    var messages: [String: String] = [:]
    var reminderOn = PowerAudit.isReminderOn

    var lastScan: Date? { history.first?.date }

    func scan() {
        isScanning = true
        Task {
            let readings = await PowerAudit.read()
            findings = PowerAudit.findings(readings)
            let score = PowerAudit.score(findings)
            self.score = score
            PowerAudit.save(.init(date: .now, score: score, swapUsedMB: readings.swapUsedMB,
                                  darkWakes24h: readings.darkWakes24h, findingIDs: findings.map(\.id)))
            history = PowerAudit.history()
            isScanning = false
        }
    }

    func apply(_ finding: PowerAudit.Finding) {
        guard let fix = finding.fix else { return }
        switch fix {
        case .copy(let command):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            messages[finding.id] = String(localized: "Kopyalandı — Terminal'e yapıştır")
        case .openSettings(let url):
            NSWorkspace.shared.open(url)
        default:
            busy = finding.id
            Task {
                let ok = await PowerAudit.apply(fix)
                PowerAudit.log("\(ok ? "applied" : "failed") \(finding.id): \(fix)")
                if ok { applied.insert(finding.id) }
                messages[finding.id] = ok ? String(localized: "Uygulandı") : String(localized: "Olmadı")
                busy = nil
            }
        }
    }

    func undo(_ finding: PowerAudit.Finding) {
        guard let fix = finding.fix else { return }
        busy = finding.id
        Task {
            let ok = await PowerAudit.undo(fix)
            PowerAudit.log("\(ok ? "undone" : "undo failed") \(finding.id): \(fix)")
            if ok { applied.remove(finding.id) }
            messages[finding.id] = ok ? String(localized: "Geri alındı") : String(localized: "Geri alınamadı")
            busy = nil
        }
    }

    func setReminder(_ on: Bool) {
        Task {
            _ = await PowerAudit.setReminder(on)
            reminderOn = PowerAudit.isReminderOn
        }
    }
}

struct PowerView: View {
    @Environment(AppModel.self) private var app
    private var model: PowerModel { app.power }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: String(localized: "Enerji ve performans"),
                       subtitle: String(localized: "Uyku engelleri, güç ayarları, pil sağlığı ve arka planda enerji harcayanlar. Hiçbir şey sen basmadan değişmez; kilitli olanlar yönetici parolasını macOS'un kendi penceresinde ister.")) {
                Toggle(String(localized: "Haftalık hatırlat"), isOn: Binding(get: { model.reminderOn }, set: { model.setReminder($0) }))
                    .toggleStyle(.switch).controlSize(.small).tint(Theme.glow)
                    .help(String(localized: "Pazar 20:00'de, son tarama 6 günden eskiyse bildirim gösterir"))
            }
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    if !model.findings.isEmpty {
                        Card {
                            ForEach(model.findings) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
            }
            HStack {
                Text(lastScanText).font(.system(size: 13, weight: .medium))
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                PrimaryButton(title: model.score == nil ? String(localized: "Tara") : String(localized: "Yeniden tara"), enabled: !model.isScanning) { model.scan() }
            }
            .padding(.horizontal, 32).padding(.vertical, 16)
            .background(Color.black.opacity(0.18))
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    private var lastScanText: String {
        guard let date = model.lastScan else { return String(localized: "Henüz tarama yok") }
        return String(localized: "Son tarama: ") + date.formatted(.relative(presentation: .named))
    }

    @ViewBuilder private var summary: some View {
        if let score = model.score {
            HStack(spacing: 18) {
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(score >= 80 ? Theme.safe : score >= 50 ? Theme.glow : Theme.glowDeep)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Enerji puanı")).font(.system(size: 13, weight: .semibold))
                    Text(String(localized: "\(model.findings.count) bulgu")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                trend
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.row))
        } else if model.isScanning {
            VStack(spacing: 10) {
                ProgressView()
                Text(String(localized: "Güç ayarları, pil ve süreçler okunuyor…")).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 80)
        } else {
            EmptyStateView(title: String(localized: "Taramaya hazır"),
                           message: String(localized: "Birkaç saniye sürer; sonuç ~/Library/Logs/CleanMac/power altına kaydedilir."),
                           symbol: "bolt.batteryblock")
                .padding(.top, 40)
        }
    }

    /// Scores of the last five check-ups, oldest on the left.
    private var trend: some View {
        let recent = Array(model.history.prefix(5).reversed())
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, snap in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.glow.opacity(0.8))
                    .frame(width: 10, height: max(4, CGFloat(snap.score) * 0.4))
                    .help("\(snap.date.formatted(date: .abbreviated, time: .omitted)): \(snap.score)")
            }
        }
        .frame(height: 40, alignment: .bottom)
    }

    private func row(_ f: PowerAudit.Finding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(f.severity))
                .foregroundStyle(color(f.severity))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title).font(.system(size: 13, weight: .semibold))
                Text(f.detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.messages[f.id] {
                    Text(message).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.safe)
                }
            }
            Spacer(minLength: 8)
            actions(f)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private func actions(_ f: PowerAudit.Finding) -> some View {
        if model.busy == f.id {
            ProgressView().controlSize(.small)
        } else if let fix = f.fix {
            if model.applied.contains(f.id) {
                if case .kill = fix {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.safe)
                } else {
                    Button(String(localized: "Geri al")) { model.undo(f) }.buttonStyle(.borderless).foregroundStyle(Theme.secondary)
                }
            } else {
                Button(label(fix)) { model.apply(f) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.glow)
                    .help(help(fix))
            }
        }
    }

    private func label(_ fix: PowerAudit.Fix) -> String {
        switch fix {
        case .admin: String(localized: "Düzelt 🔒")
        case .disableAgent: String(localized: "Kapat")
        case .kill: String(localized: "Sonlandır")
        case .copy: String(localized: "Komutu kopyala")
        case .openSettings: String(localized: "Ayarları aç")
        }
    }

    private func help(_ fix: PowerAudit.Fix) -> String {
        switch fix {
        case .admin(let command, _): String(localized: "Çalışacak: sudo \(command)")
        case .disableAgent(let label, _): String(localized: "launchctl disable \(label) — geri alınabilir")
        case .kill(let pids): "PID \(pids.map(String.init).joined(separator: ", "))"
        case .copy(let command): command
        case .openSettings: String(localized: "Sistem Ayarları'nda ilgili bölümü açar")
        }
    }

    private func icon(_ s: PowerAudit.Severity) -> String {
        switch s {
        case .warning: "exclamationmark.triangle.fill"
        case .suggestion: "lightbulb.fill"
        case .info: "info.circle"
        }
    }

    private func color(_ s: PowerAudit.Severity) -> Color {
        switch s {
        case .warning: Theme.glowDeep
        case .suggestion: Theme.glow
        case .info: Theme.tertiary
        }
    }
}
