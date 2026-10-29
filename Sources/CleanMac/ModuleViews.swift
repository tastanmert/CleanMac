import SwiftUI
import CleanMacCore

// MARK: - Landing

/// A module's front page: glass orb on the left, what it does on the right, the action at the bottom.
struct ModuleLanding: View {
    let module: Module
    @Environment(AppModel.self) private var model
    /// Where the pointer is over the page, -1…1 on each axis; the object leans towards it.
    @State private var pointer: CGSize = .zero
    @State private var pageSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            HStack(spacing: 56) {
                GlassOrb(module: module, size: 250, tilt: pointer)
                VStack(alignment: .leading, spacing: 14) {
                    Text(module.title).font(.system(size: 40, weight: .regular))
                    Text(module.subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 340, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(module.bullets, id: \.text) { bullet in
                            HStack(spacing: 12) {
                                Image(systemName: bullet.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(module.palette.orb))
                                Text(bullet.text).font(.system(size: 14, weight: .medium))
                            }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 20)
            // A full disc standing on the window's lower edge.
            OrbButton(title: module.actionTitle, palette: module.palette) { model.start() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 6)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let x = point.x / max(pageSize.width, 1) * 2 - 1
                let y = point.y / max(pageSize.height, 1) * 2 - 1
                withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8)) { pointer = CGSize(width: x, height: y) }
            case .ended:
                withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { pointer = .zero }
            }
        }
    }
}

// MARK: - Glass orb

/// CleanMac's illustration: a tilted glass object in the module's own silhouette and colours,
/// gently floating; while `spinning` it turns slowly around its vertical axis. Drawn in SwiftUI.
struct GlassOrb: View {
    let module: Module
    var size: CGFloat = 250
    var floating = true
    var spinning = false
    /// Pointer direction, -1…1 on each axis: the object turns and drifts a little towards it.
    var tilt: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var swing = false

    var body: some View {
        // The heavy artwork (a dozen gradient layers, blurs, shadows) is rasterised once; only a cached
        // bitmap is turned and tilted, so nothing re-lays out the artwork while it moves.
        let lift: Double = 0
        let turn: Double = spinning ? (swing ? 28 : -28) : 0
        let palette = module.palette
        ZStack {
            Ellipse()
                .fill(palette.glow.opacity(0.5))
                .frame(width: size * 0.85, height: size * 0.18)
                .blur(radius: 24)
                .offset(y: size * 0.58)
                .scaleEffect(1 - 0.1 * lift)

            OrbArtwork(module: module, size: size)
                .equatable()
                .rotation3DEffect(.degrees(turn + tilt.width * 16), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(-tilt.height * 10), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                .rotation3DEffect(.degrees(22), axis: (x: 1, y: -0.25, z: 0), perspective: 0.55)
                .offset(x: tilt.width * size * 0.05, y: -10 * lift + tilt.height * size * 0.04)
        }
        .frame(width: size * 1.1, height: size * 1.25)
        .accessibilityHidden(true)
        .onAppear { setMotion(running: appearsActive) }
        .onChange(of: appearsActive) { _, active in setMotion(running: active) }
        .onChange(of: spinning) { _, _ in setMotion(running: appearsActive) }
    }

    private func setMotion(running: Bool) {
        // Only the scanning orb sways; an idle page stays still until the pointer moves it.
        if running && !reduceMotion && spinning {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { swing = true }
        } else {
            withAnimation(.smooth) { swing = false }
        }
    }
}

/// The glass slab itself: static, so SwiftUI can flatten it into one texture.
private struct OrbArtwork: View, Equatable {
    let module: Module
    let size: CGFloat

    var body: some View {
        let palette = module.palette
        let shape = module.orbShape
        let depth = size * 0.11            // how thick the glass slab is
        let layers = 12
        ZStack {
            // The slab's side: the silhouette repeated downwards, darker towards the bottom edge.
            ForEach(0..<layers, id: \.self) { i in
                let f = Double(i) / Double(layers - 1)
                shape.fill(LinearGradient(colors: [Color(hex: palette.orbA).mix(with: .black, by: 0.25 + 0.35 * f),
                                                   Color(hex: palette.orbB).mix(with: .black, by: 0.35 + 0.35 * f)],
                                          startPoint: .leading, endPoint: .trailing))
                    .offset(y: depth * (1 - f))
            }
            // Rim light where the side meets the top face.
            shape.stroke(Color(hex: palette.orbB).mix(with: .white, by: 0.5).opacity(0.7), lineWidth: 2)
                .offset(y: 1)

            // Top face: glossy gradient, frosted inner panel, specular highlight.
            shape.fill(LinearGradient(colors: [Color(hex: palette.orbA).mix(with: .white, by: 0.25), Color(hex: palette.orbA),
                                               Color(hex: palette.orbB)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(.white.opacity(0.08)).padding(size * 0.12)
            shape.stroke(.white.opacity(0.25), lineWidth: 1).padding(size * 0.12)
            Ellipse()
                .fill(.white.opacity(0.45))
                .frame(width: size * 0.7, height: size * 0.28)
                .blur(radius: 20)
                .offset(x: -size * 0.12, y: -size * 0.3)
                .mask(shape)
            shape.stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1), .white.opacity(0.35)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.6)

            // The symbol sits on the glass like a frosted inlay with its own shadow.
            Image(systemName: module.symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: palette.orbA).mix(with: .black, by: 0.5).opacity(0.6), radius: 1, y: 2)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .frame(width: size, height: size * 0.92)
        .padding(30)               // room for the symbol's soft shadow inside the texture
        .drawingGroup()
        .padding(-30)
        .shadow(color: palette.glow.opacity(0.55), radius: 34, y: 22)
    }
}

// MARK: - Orb button

/// The round action at the bottom of every module. While working it shows a progress ring and stops.
struct OrbButton: View {
    let title: String
    let palette: Palette
    var progress: Double? = nil      // nil: idle; 0…1: ring
    var indeterminate = false
    let action: () -> Void
    @State private var hovering = false
    @State private var spin = false
    @State private var pressed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                // A slow breath of light behind the button. It runs in Core Animation, off the main thread:
                // a SwiftUI repeat-forever animation would re-render the whole window every frame.
                BreathingGlow(color: palette.glow)
                    .frame(width: 200, height: 200)
                    .opacity(hovering ? 1.4 : 1)
                    .allowsHitTesting(false)
                Circle()
                    .fill(palette.orb)
                    .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                    .frame(width: 104, height: 104)
                if progress != nil || indeterminate {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4).frame(width: 122, height: 122)
                    Circle()
                        .trim(from: 0, to: indeterminate ? 0.25 : max(0.02, progress ?? 0))
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 122, height: 122)
                        .rotationEffect(.degrees(indeterminate ? (spin ? 270 : -90) : -90))
                }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 150, height: 150)
            .scaleEffect(hovering ? 1.04 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { pressed = true; if isEnabled { Sounds.shared.play(.pressDown) } } }
            .onEnded { _ in pressed = false; if isEnabled { Sounds.shared.play(.pressUp) } })
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.3), value: hovering)
        .animation(.smooth, value: progress)
        .onChange(of: indeterminate, initial: true) { _, on in
            guard on, !reduceMotion else { spin = false; return }
            spin = false
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

// MARK: - Working (scanning / cleaning)

struct WorkingView: View {
    enum Mode { case scanning, cleaning }
    let mode: Mode
    @Environment(AppModel.self) private var model

    var body: some View {
        let module = model.module
        VStack(spacing: 0) {
            Text(module.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 14)
            if mode == .scanning && model.sessionModule == .smart {
                SmartScanGrid()
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            } else {
            Spacer()
            GlassOrb(module: module, size: 190, spinning: true)
            VStack(spacing: 10) {
                Text(headline)
                    .font(.system(size: 30, weight: .semibold))
                    .contentTransition(.numericText())
                TimelineView(.periodic(from: .now, by: 0.12)) { _ in
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 560)
                        .transaction { $0.animation = nil }   // a live path swaps, never cross-fades
                }
            }
            .padding(.top, 8)
            Spacer()
            }
            OrbButton(title: mode == .scanning ? String(localized: "Durdur") : "\(Int(model.progress * 100))%",
                      palette: module.palette,
                      progress: mode == .cleaning ? model.progress : nil,
                      indeterminate: mode == .scanning) {
                model.showStopConfirm = true
            }
            .padding(.bottom, 6)
        }
        .animation(.smooth, value: model.foundSize)
        .glassConfirm(isPresented: Bindable(model).showStopConfirm, symbol: "stop.fill",
                      title: mode == .scanning ? String(localized: "Tarama bitmeden durdurulsun mu?") : String(localized: "Çalışan işlemler durdurulsun mu?"),
                      message: mode == .scanning ? String(localized: "Şimdiye kadar bulunanlar atılır.")
                                                 : String(localized: "İşlemi yarıda kesmek, temizlenmemiş öğeler ve yapılmamış görevler bırakır. Çöp'e taşınanlar yerinde kalır."),
                      confirm: String(localized: "Durdur"), cancel: mode == .scanning ? String(localized: "Taramaya devam et") : String(localized: "Devam et")) {
            if mode == .scanning { model.stop() } else { model.stopCleaning() }
        }
    }

    private var headline: String {
        switch mode {
        case .scanning: model.foundSize > 0 ? String(localized: "\(model.foundSize.bytes) bulundu") : String(localized: "Çöp aranıyor…")
        case .cleaning: String(localized: "Temizleniyor…")
        }
    }

    private var detail: String {
        switch mode {
        case .cleaning:
            return String(localized: "Seçilenler Çöp'e taşınıyor, araç önbellekleri kendi komutlarıyla temizleniyor")
        case .scanning:
            let pending = model.pendingRules
            if pending.count <= 2, !pending.isEmpty {
                let names = pending.joined(separator: ", ")
                return String(localized: "Son kontrol: \(names) · macOS izin soruyorsa İzin Ver'e bas")
            }
            let path = model.livePath.current
            return path.isEmpty ? String(localized: "Hazırlanıyor…") : path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        }
    }
}

// MARK: - Shared controls

enum CheckState { case on, off, mixed }

struct CheckBox: View {
    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.circle.fill" : state == .mixed ? "minus.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(state == .off ? Theme.tertiary : Theme.glow)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? String(localized: "Seçili") : state == .mixed ? String(localized: "Kısmen seçili") : String(localized: "Seçili değil"))
    }
}

extension CategoryResult {
    var checkState: CheckState {
        let selected = items.filter(\.isSelected).count
        return selected == 0 ? .off : selected == items.count ? .on : .mixed
    }
}


/// The soft glow and slowly expanding ring behind an orb button, animated by Core Animation.
private struct BreathingGlow: NSViewRepresentable {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> GlowView { GlowView() }
    func updateNSView(_ view: GlowView, context: Context) {
        view.apply(NSColor(color), animated: !reduceMotion)
    }

    final class GlowView: NSView {
        private let glow = CAGradientLayer()
        private let ring = CAShapeLayer()
        private var animated = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.locations = [0.25, 1]
            ring.fillColor = nil
            ring.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
            ring.lineWidth = 1
            layer?.addSublayer(glow)
            layer?.addSublayer(ring)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func apply(_ color: NSColor, animated: Bool) {
            glow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
            self.animated = animated
            startIfNeeded()
        }

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); startIfNeeded() }

        override func layout() {
            super.layout()
            glow.frame = bounds
            let side: CGFloat = 122
            ring.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        }

        private func startIfNeeded() {
            glow.removeAllAnimations(); ring.removeAllAnimations()
            guard animated, window != nil else { return }
            func pulse(_ key: String, _ from: Double, _ to: Double, _ duration: Double, reverse: Bool) -> CABasicAnimation {
                let a = CABasicAnimation(keyPath: key)
                a.fromValue = from; a.toValue = to; a.duration = duration
                a.autoreverses = reverse; a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                return a
            }
            glow.add(pulse("transform.scale", 0.94, 1.08, 1.6, reverse: true), forKey: "scale")
            glow.add(pulse("opacity", 0.6, 0.95, 1.6, reverse: true), forKey: "opacity")
            ring.add(pulse("transform.scale", 1, 1.22, 3.2, reverse: false), forKey: "scale")
            ring.add(pulse("opacity", 1, 0, 3.2, reverse: false), forKey: "opacity")
        }
    }
}
