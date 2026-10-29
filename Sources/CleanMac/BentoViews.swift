import SwiftUI
import CleanMacCore

// MARK: - Smart scan card grid

/// While a smart scan runs: two rows of cards (cleanup, protection, performance / applications, clutter).
/// The working card widens inside its row and fills with its colour, its object turning; waiting cards
/// show their big object rising from the bottom edge; finished cards tuck the object into the corner
/// and print what they found.
struct SmartScanGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = model.scanGroups
        let rows = groups.count > 3 ? [Array(groups.prefix(3)), Array(groups.dropFirst(3))] : [groups]
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            // The row being worked on takes most of the height; the other row slims down to its results.
            let activeRow = rows.firstIndex { $0.contains { $0 == model.activeGroup } }
            let topShare: CGFloat = activeRow == 0 ? 0.64 : activeRow == 1 ? 0.3 : 0.5
            let topHeight = rows.count > 1 ? (proxy.size.height - spacing) * topShare : proxy.size.height
            VStack(spacing: spacing) {
                ForEach(rows.indices, id: \.self) { r in
                    row(rows[r], width: proxy.size.width, spacing: spacing)
                        .frame(height: r == 0 ? topHeight : proxy.size.height - topHeight - spacing)
                }
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: model.activeGroup)
    }

    private func row(_ groups: [Module], width: CGFloat, spacing: CGFloat) -> some View {
        let units = groups.reduce(CGFloat(0)) { $0 + weight($1, in: groups) }
        let unit = (width - spacing * CGFloat(groups.count - 1)) / units
        return HStack(spacing: spacing) {
            ForEach(groups) { group in
                ScanCard(group: group, state: state(of: group))
                    .frame(width: unit * weight(group, in: groups))
            }
        }
    }

    private func weight(_ group: Module, in row: [Module]) -> CGFloat {
        guard group == model.activeGroup else { return 1 }
        return row.count >= 3 ? 3.2 : 2.3
    }

    private func state(of group: Module) -> ScanCard.State {
        if group == model.activeGroup { return .working }
        return model.isScanned(group) ? .done(model.cardSummary(group).value, model.cardSummary(group).caption) : .waiting
    }
}

struct ScanCard: View {
    enum State: Equatable { case waiting, working, done(String, String) }
    let group: Module
    let state: State
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                GlassSlab(shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                          tintA: Color(hex: group.palette.orbA), tintB: Color(hex: group.palette.orbB),
                          depth: state == .working ? 10 : 6,
                          strength: state == .working ? 0.9 : 0.1)
                    .id(state == .working)
                    .transition(.opacity)

                // The object: big and rising from the bottom while waiting, centred and turning while
                // working, small in the top-right corner once done. One view, so it glides between places.
                let orb = orbPlacement(in: size)
                GlassOrb(module: group, size: orb.size, floating: false, spinning: state == .working)
                    .position(orb.center)
                    .opacity(state == .waiting ? 0.75 : 1)

                switch state {
                case .working:
                    VStack(spacing: 0) {
                        Text(workingTitle)
                            .font(.system(size: 28, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.top, 18)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 0.12)) { _ in
                            Text(fileName)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1).truncationMode(.middle)
                                .transaction { $0.animation = nil }   // a live path swaps, never cross-fades
                        }
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 20)
                    .frame(width: size.width, height: size.height)
                    .transition(.blurFade)
                case .waiting, .done:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group == .junk ? String(localized: "Temizlik") : group.title)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Spacer()
                        if case .done(let value, let caption) = state {
                            Text(value).font(.system(size: 24, weight: .semibold).monospacedDigit())
                                .lineLimit(2).minimumScaleFactor(0.6)
                            Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                        }
                    }
                    .padding(14)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .transition(.blurFade)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .shadow(color: state == .working ? group.palette.glow.opacity(0.45) : .clear, radius: 28, y: 12)
    }

    private func orbPlacement(in size: CGSize) -> (size: CGFloat, center: CGPoint) {
        switch state {
        case .working:
            let d = min(size.width * 0.5, size.height * 0.5)
            return (d, CGPoint(x: size.width / 2, y: size.height * 0.56))
        case .waiting:
            // Big, and sitting low enough that the card's bottom edge cuts it, as if rising into view.
            let d = min(size.width * 0.9, size.height * 0.85)
            return (d, CGPoint(x: size.width / 2, y: size.height * 0.8))
        case .done:
            let d = min(size.width * 0.6, 120)
            return (d, CGPoint(x: size.width - d * 0.32, y: d * 0.28))
        }
    }

    private var workingTitle: String {
        switch group {
        case .junk: String(localized: "Çöp aranıyor…")
        case .protection: String(localized: "Tehditler ve izler aranıyor…")
        case .applications: String(localized: "Uygulamalar inceleniyor…")
        case .clutter: String(localized: "Büyük ve kopya dosyalar aranıyor…")
        case .performance: String(localized: "Bakım ihtiyacı denetleniyor…")
        default: String(localized: "Taranıyor…")
        }
    }

    /// Only the name of the file being looked at, not its whole path.
    private var fileName: String {
        let p = model.livePath.current
        return p.isEmpty ? String(localized: "Hazırlanıyor…") : (p as NSString).lastPathComponent
    }
}

// MARK: - Summary cards

/// A result card: optional checkbox and title, the module's object overflowing the top-right corner,
/// the finding in large type at the bottom left and İncele at the bottom right. Lifts on hover.
struct BentoCard: View {
    let title: String
    let value: String
    let caption: String
    let module: Module
    let checkState: CheckState?
    let onToggle: () -> Void
    /// nil when there is nothing to open: the card hides its "İncele" button.
    let onReview: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.height * 0.95, proxy.size.width * 0.55, 170)
            ZStack(alignment: .topLeading) {
                GlassSlab(shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                          tintA: Color(hex: module.palette.orbA), tintB: Color(hex: module.palette.orbB),
                          depth: hovering ? 10 : 7, strength: 0.16)
                // The module's colour pooling from the corner where its object sits.
                RadialGradient(colors: [Color(hex: module.palette.orbA, opacity: 0.45), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: proxy.size.width * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                GlassOrb(module: module, size: d, floating: false)
                    .position(x: proxy.size.width - d * 0.28, y: d * 0.22)
                    .scaleEffect(hovering ? 1.05 : 1, anchor: .topTrailing)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if let checkState { CheckBox(state: checkState, action: onToggle) }
                        Text(title).font(.system(size: 13, weight: .semibold))
                    }
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                    HStack(alignment: .bottom) {
                        Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
                        Spacer(minLength: 8)
                        if let onReview {
                            Button(String(localized: "İncele"), action: onReview)
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(0.14)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                        }
                    }
                }
                .padding(16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .offset(y: hovering ? -3 : 0)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
    }
}
