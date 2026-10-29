import SwiftUI

/// CleanMac's mark: an open mint "C" ring with a coral dot by its upper tip, in flat colours on ink.
/// Drawn in code so the app icon (scripts/make-icon.swift) and the in-app logo stay identical.
struct AppMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color(hex: 0x161A2C))
            Circle()
                .trim(from: 0.12, to: 0.88)
                .stroke(Color(hex: 0x5EE6C0), style: StrokeStyle(lineWidth: size * 0.136, lineCap: .round))
                .frame(width: size * 0.583, height: size * 0.583)
            Circle()
                .fill(Color(hex: 0xFF7A59))
                .frame(width: size * 0.127, height: size * 0.127)
                .offset(x: size * (0.234 * cos(.pi * 0.24) + 0.09), y: -size * (0.234 * sin(.pi * 0.24) + 0.0625))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A regular polygon with rounded corners (hexagon, octagon…).
nonisolated struct RoundedPolygon: Shape {
    let sides: Int
    var cornerRadius: CGFloat = 0.18     // fraction of the radius
    var rotation: Double = 0             // degrees

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { i -> CGPoint in
            let angle = (Double(i) / Double(sides)) * 2 * .pi + rotation * .pi / 180 - .pi / 2
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        let r = radius * cornerRadius
        var path = Path()
        for i in 0..<sides {
            let prev = points[(i - 1 + sides) % sides], cur = points[i], next = points[(i + 1) % sides]
            let a = cur.moved(toward: prev, by: r), b = cur.moved(toward: next, by: r)
            if i == 0 { path.move(to: a) } else { path.addLine(to: a) }
            path.addQuadCurve(to: b, control: cur)
        }
        path.closeSubpath()
        return path
    }
}

/// A soft blob with `lobes` bulges (clover-like), used for the AI and clutter objects.
nonisolated struct Blob: Shape {
    let lobes: Int
    var depth: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 * (1 - depth)
        var path = Path()
        let steps = 180
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let r = base * (1 + depth * cos(Double(lobes) * t))
            let p = CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// A rounded shield (performance).
nonisolated struct Shield: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02))
        p.addCurve(to: CGPoint(x: x + w * 0.98, y: y + h * 0.2),
                   control1: CGPoint(x: x + w * 0.72, y: y + h * 0.12), control2: CGPoint(x: x + w * 0.9, y: y + h * 0.12))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.98),
                   control1: CGPoint(x: x + w * 1.0, y: y + h * 0.62), control2: CGPoint(x: x + w * 0.78, y: y + h * 0.86))
        p.addCurve(to: CGPoint(x: x + w * 0.02, y: y + h * 0.2),
                   control1: CGPoint(x: x + w * 0.22, y: y + h * 0.86), control2: CGPoint(x: x + w * 0.0, y: y + h * 0.62))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02),
                   control1: CGPoint(x: x + w * 0.1, y: y + h * 0.12), control2: CGPoint(x: x + w * 0.28, y: y + h * 0.12))
        p.closeSubpath()
        return p
    }
}

nonisolated private extension CGPoint {
    func moved(toward other: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = other.x - x, dy = other.y - y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        return CGPoint(x: x + dx / length * distance, y: y + dy / length * distance)
    }
}

extension Module {
    /// The silhouette of the module's glass object.
    var orbShape: AnyShape {
        switch self {
        case .smart: AnyShape(Circle())
        case .junk: AnyShape(RoundedRectangle(cornerRadius: 70, style: .continuous))
        case .developer: AnyShape(RoundedPolygon(sides: 6, cornerRadius: 0.2, rotation: 30))
        case .ai: AnyShape(Blob(lobes: 4, depth: 0.1))
        case .protection: AnyShape(Shield())
        case .applications: AnyShape(RoundedPolygon(sides: 8, cornerRadius: 0.16, rotation: 22.5))
        case .performance: AnyShape(RoundedPolygon(sides: 3, cornerRadius: 0.3))
        case .clutter: AnyShape(Blob(lobes: 3, depth: 0.08))
        case .spaceLens: AnyShape(RoundedRectangle(cornerRadius: 80, style: .continuous))
        case .trash: AnyShape(RoundedPolygon(sides: 5, cornerRadius: 0.22))
        case .tools: AnyShape(RoundedPolygon(sides: 4, cornerRadius: 0.24, rotation: 45))
        case .activity: AnyShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
    }
}

/// The same thick-glass language as the module objects, for any shape: a darker side edge showing
/// below the face, a tinted glossy face, a soft specular bloom at the top and a bright rim.
/// `strength` 0…1 goes from frosted (barely tinted) to fully coloured glass.
struct GlassSlab<S: Shape>: View {
    let shape: S
    let tintA: Color
    let tintB: Color
    var depth: CGFloat = 8
    var strength: Double = 1
    var highlight: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Side edge: a few copies stepping down, darkening towards the bottom.
                // Only the part below the face shows, so a see-through face never reveals the edge behind it.
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        let f = Double(i) / 4
                        shape.fill(LinearGradient(colors: [tintA.mix(with: .black, by: 0.35 + 0.3 * f), tintB.mix(with: .black, by: 0.45 + 0.3 * f)],
                                                  startPoint: .leading, endPoint: .trailing))
                            .opacity(0.35 + 0.55 * strength)
                            .offset(y: depth * (1 - f))
                    }
                }
                .mask {
                    ZStack {
                        Rectangle().padding(-depth * 2)
                        shape.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                // Face.
                shape.fill(Color.black.opacity(0.25))
                shape.fill(LinearGradient(colors: [tintA.mix(with: .white, by: 0.2), tintA, tintB],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.12 + 0.68 * strength)
                if highlight {
                    // Light falling on the upper part of the face, fading out downwards and to the right.
                    shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.08 + 0.22 * strength), location: 0),
                                                      .init(color: .white.opacity(0), location: min(0.55, 90 / max(size.height, 1)))],
                                              startPoint: .top, endPoint: .bottom))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.06 * strength), .clear], startPoint: .topLeading, endPoint: .center))
                }
                shape.stroke(LinearGradient(colors: [.white.opacity(0.55 + 0.3 * strength), .white.opacity(0.06), .white.opacity(0.22)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
            }
            .compositingGroup()
        }
    }
}
