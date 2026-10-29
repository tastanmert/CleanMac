import AppKit
import Darwin
import SwiftUI
import CleanMacCore

/// Quick facts for the menu bar: disk, memory, Trash and a simple health score.
@Observable
final class MacHealth {
    var disk = DiskSpace.current()
    var memoryUsed: Double = 0          // 0…1, app + wired + compressed memory
    var trashBytes: Int64 = 0
    var lastSmartScan: Date? { UserDefaults.standard.object(forKey: "lastSmartScan") as? Date }

    func refresh() {
        disk = DiskSpace.current()
        memoryUsed = Self.memoryUse()
        Task {
            trashBytes = await Task.detached {
                Scanner.allocatedSize(of: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
            }.value
        }
    }

    /// Points off for a full disk, tight memory, a heavy Trash and a long time since the last smart scan.
    var score: Int {
        var score = 100
        if disk.fraction > 0.9 { score -= 35 } else if disk.fraction > 0.8 { score -= 15 }
        if memoryUsed > 0.9 { score -= 20 } else if memoryUsed > 0.8 { score -= 10 }
        if trashBytes > 5_000_000_000 { score -= 10 }
        if let last = lastSmartScan { if Date.now.timeIntervalSince(last) > 14 * 86_400 { score -= 10 } } else { score -= 10 }
        return max(score, 0)
    }

    var verdict: String {
        switch score {
        case 90...: String(localized: "Mükemmel")
        case 75..<90: String(localized: "İyi")
        case 50..<75: String(localized: "Orta")
        default: String(localized: "Dikkat")
        }
    }

    static func memoryUse() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = Double(getpagesize())
        let used = (Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var health = MacHealth()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Mac sağlığı: \(health.verdict)")).font(.system(size: 13, weight: .semibold))
                    Text(health.lastSmartScan.map { String(localized: "Son Akıllı Tarama: \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Henüz Akıllı Tarama yapılmadı"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(health.score)").font(.system(size: 22, weight: .bold).monospacedDigit())
            }
            meter("Disk", value: health.disk.fraction, detail: String(localized: "\(health.disk.available.bytes) boş"))
            meter(String(localized: "Bellek"), value: health.memoryUsed, detail: String(localized: "%\(Int(health.memoryUsed * 100)) kullanımda"))
            HStack {
                Label(health.trashBytes > 0 ? String(localized: "Çöp: \(health.trashBytes.bytes)") : String(localized: "Çöp"), systemImage: "trash")
                    .font(.system(size: 12))
                Spacer()
                Button(String(localized: "Aç")) { model.openTrash() }.controlSize(.small)
            }
            Divider()
            Button {
                open(.smart)
                if !model.isBusy { model.requestScan() }
            } label: { Label(String(localized: "Akıllı Tarama'yı başlat"), systemImage: "desktopcomputer") }
            Button { open(.spaceLens) } label: { Label(String(localized: "Alan Haritası"), systemImage: "chart.pie") }
            Divider()
            HStack {
                Button(String(localized: "CleanMac'i aç")) { open(nil) }
                Spacer()
                Button(String(localized: "Çık")) { NSApp.terminate(nil) }
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 290)
        .onAppear { health.refresh() }
    }

    private func open(_ module: Module?) {
        openWindow(id: "main")
        NSApp.activate()
        if let module { model.select(module) }
    }

    private func meter(_ title: String, value: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: value).tint(value > 0.9 ? .red : value > 0.8 ? .orange : Theme.glow)
        }
    }
}

/// The menu bar mark: the app's open "C" ring with its spark, as a template image so it follows the menu bar's colour.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let ring = NSBezierPath()
            ring.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: 6.2, startAngle: 43, endAngle: 317)
            ring.lineWidth = 2.4
            ring.lineCapStyle = .round
            NSColor.black.setStroke()
            ring.stroke()
            let tip = NSPoint(x: rect.midX + 6.2 * cos(.pi / 4.2), y: rect.midY + 6.2 * sin(.pi / 4.2))
            NSBezierPath(ovalIn: NSRect(x: tip.x - 1.8, y: tip.y - 1.8, width: 3.6, height: 3.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// Top-right pill on every page: the Mac's health at a glance; opens the same panel as the menu bar.
struct HealthPill: View {
    @Environment(AppModel.self) private var model
    @State private var health = MacHealth()
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(health.score >= 75 ? Theme.safe : health.score >= 50 ? Theme.review : .red)
                    .frame(width: 8, height: 8)
                    .shadow(color: health.score >= 75 ? Theme.safe : Theme.review, radius: 4)
                Text(String(localized: "Mac sağlığı: \(health.verdict)")).font(.system(size: 12, weight: .medium))
                Text(String(localized: "\(health.disk.available.bytes) boş")).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.1)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) { MenuBarContent().environment(model) }
        .onAppear { health.refresh() }
        .onChange(of: model.disk.available) { health.refresh() }
    }
}
