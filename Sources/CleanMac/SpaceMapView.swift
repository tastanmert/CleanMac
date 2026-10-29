import AppKit
import SwiftUI
import CleanMacCore

@Observable
final class SpaceMapModel {
    enum Root: String, CaseIterable, Identifiable {
        case home = "Ev klasörü", disk = "Macintosh HD"
        var id: String { rawValue }
        /// The whole disk is browsed through the data volume: /Users, /Applications, /Library… live there.
        var url: URL {
            switch self {
            case .home: FileManager.default.homeDirectoryForCurrentUser
            case .disk: URL(filePath: "/System/Volumes/Data")
            }
        }
    }

    var root: Root = .home
    var path: [URL] = []
    var nodes: [SpaceMap.Node] = []
    var isLoading = false
    var isRemoving = false   // one removal at a time: a second tap would clean the same files again
    var selected: Set<URL> = []
    var sortKey: SortKey = .size
    var report: CleanReport?
    var confirm = false
    /// Where the bubble that was opened sat, so the zoom grows out of it.
    var zoomAnchor: UnitPoint = .center
    private var task: Task<Void, Never>?
    private var cache: [URL: [SpaceMap.Node]] = [:]
    private let guardian = SafetyGuard()

    var current: URL { path.last ?? root.url }
    var totalSize: Int64 { nodes.reduce(0) { $0 + ($1.size ?? 0) } }

    func setRoot(_ root: Root) {
        guard root != self.root else { return }
        self.root = root
        path = []
        load()
    }

    func open(_ url: URL, anchor: UnitPoint = .center) {
        zoomAnchor = anchor
        path.append(url)
        load()
    }

    func goUp() {
        guard !path.isEmpty else { return }
        zoomAnchor = .center
        path.removeLast()
        load()
    }

    func go(toDepth depth: Int) {
        zoomAnchor = .center
        path = Array(path.prefix(depth))
        load()
    }

    func load(force: Bool = false) {
        task?.cancel()
        selected = []
        let folder = current
        if !force, let cached = cache[folder] {
            nodes = cached
            isLoading = false
            return
        }
        isLoading = true
        nodes = []
        task = Task {
            // Listing a big folder (or one macOS asks permission for) must not block the window.
            // The disk's top level is full of hidden system folders; hide them there, show them elsewhere (.ollama, .cache…).
            let showHidden = !(root == .disk && path.isEmpty)
            let entries = await Task.detached { SpaceMap.entries(of: folder, includeHidden: showHidden) }.value
            guard !Task.isCancelled, current == folder else { return }
            nodes = entries
            await SpaceMap.measure(entries) { measured in
                await MainActor.run {
                    guard self.current == folder, let i = self.nodes.firstIndex(where: { $0.url == measured.url }) else { return }
                    self.nodes[i] = measured
                }
            }
            guard !Task.isCancelled, current == folder else { return }
            nodes = nodes.filter { ($0.size ?? 0) > 0 }
            cache[folder] = nodes
            isLoading = false
        }
    }

    /// Measured items first, in the chosen order; the rest by name until their size arrives.
    var sortedNodes: [SpaceMap.Node] {
        nodes.sorted { a, b in
            switch (a.size, b.size) {
            case let (x?, y?): sortKey == .name ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending : x > y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    func canRemove(_ node: SpaceMap.Node) -> Bool { guardian.isAllowed(node.url, policy: .userFile) }

    /// Synced by iCloud or another sync app: removing it here removes it from the cloud and every linked device.
    func isCloudBacked(_ node: SpaceMap.Node) -> Bool {
        if (try? node.url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let synced = ["Dropbox", "OneDrive", "Google Drive", "Library/CloudStorage", "Library/Mobile Documents", "Box", "pCloud Drive"]
        return synced.contains { node.url.path == "\(home)/\($0)" || node.url.path.hasPrefix("\(home)/\($0)/") || node.url.path.hasPrefix("\(home)/\($0) ") }
    }
    var selectedCloudCount: Int { selectedNodes.filter(isCloudBacked).count }

    var removableNodes: [SpaceMap.Node] { nodes.filter(canRemove) }
    var selectedNodes: [SpaceMap.Node] { nodes.filter { selected.contains($0.url) } }
    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + ($1.size ?? 0) } }

    func toggle(_ node: SpaceMap.Node) {
        if selected.contains(node.url) { selected.remove(node.url) } else { selected.insert(node.url) }
    }

    func removeSelected() {
        let items = selectedNodes.map {
            CleanItem(title: $0.name, size: $0.size ?? Scanner.allocatedSize(of: $0.url), action: .trash($0.url),
                      isSelected: true, policy: .userFile)
        }
        guard !isRemoving, !items.isEmpty else { return }
        isRemoving = true
        selected = []
        Task {
            report = await Cleaner.live().clean(items, source: String(localized: "Alan Haritası"))
            isRemoving = false
            cache = [:]   // parent sizes are stale too
            load(force: true)
        }
    }
}

struct SpaceMapView: View {
    @Environment(AppModel.self) private var app
    private var model: SpaceMapModel { app.spaceMap }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            toolbar
            if let report = model.report { ReportBanner(report: report) { model.report = nil } }
            HStack(spacing: 0) {
                list.frame(width: 320)
                Rectangle().fill(Theme.hairline).frame(width: 1)
                BubbleMap(nodes: model.sortedNodes, current: model.current, anchor: model.zoomAnchor,
                          isLoading: model.isLoading) { node, anchor in
                    if node.isFolder { model.open(node.url, anchor: anchor) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ToolActionBar(selectedSize: model.selectedSize, selectedCount: model.selected.count,
                          actionTitle: String(localized: "Çöp'e taşı"), busy: model.isRemoving) { model.confirm = true }
        }
        .onAppear { if model.nodes.isEmpty && !model.isLoading { model.load() } }
        .glassConfirm(isPresented: $model.confirm, symbol: model.selectedCloudCount > 0 ? "icloud" : "trash",
                      title: String(localized: "\(model.selected.count) öğe Çöp'e taşınsın mı?"),
                      message: (model.selectedCloudCount > 0 ? String(localized: "Seçilen dosyalardan bazıları bulut depolamada. Silersen buluttan ve bağlı tüm cihazlarından da kaldırılır.\n\n") : "")
                          + model.selectedNodes.map(\.name).prefix(8).joined(separator: ", "),
                      confirm: model.selectedCloudCount > 0 ? String(localized: "Yine de Çöp'e taşı") : String(localized: "Çöp'e taşı")) { model.removeSelected() }
    }

    private var toolbar: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Button { model.goUp() } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.borderless).foregroundStyle(Theme.secondary).disabled(model.path.isEmpty)
                .help(String(localized: "Üst klasör"))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    crumb(model.root.rawValue.localized, depth: 0)
                    ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        crumb(url.lastPathComponent, depth: index + 1)
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer()
            GlassTabs(selection: Binding(get: { model.root }, set: { model.setRoot($0) }),
                      items: SpaceMapModel.Root.allCases.map { ($0.rawValue.localized, $0) })
            Button { model.load(force: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).foregroundStyle(Theme.secondary).help(String(localized: "Yeniden ölç"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 12)
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        Button(title) { model.go(toDepth: depth) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: depth == model.path.count ? .semibold : .regular))
            .foregroundStyle(depth == model.path.count ? Theme.text : Theme.secondary)
    }

    private var list: some View {
        @Bindable var model = model
        let sorted = model.sortedNodes
        let largest = max(sorted.compactMap(\.size).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.current.path)).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.path.last?.lastPathComponent ?? model.root.rawValue.localized).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(model.isLoading ? String(localized: "Ölçülüyor… \(model.nodes.filter { $0.size != nil }.count) / \(model.nodes.count)")
                                         : String(localized: "\(model.totalSize.bytes) · \(model.nodes.count) öğe"))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            // Space macOS frees on its own (iCloud copies, caches, snapshots), shown apart from used space.
            if model.root == .disk && model.path.isEmpty && app.disk.purgeable > 1_000_000_000 {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.3.trianglepath").foregroundStyle(Theme.safe)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Silinebilir alan · \(app.disk.purgeable.bytes)")).font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "macOS yer gerektiğinde kendisi boşaltır")).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    Button(String(localized: "Temizle")) { app.open(.performance, tab: 0) }
                        .buttonStyle(.borderless).font(.system(size: 12, weight: .semibold))
                        .help(String(localized: "Performans > Bakım görevleri'nde silinebilir alanı boşalt"))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .rowPill(active: false)
                .padding(.horizontal, 10).padding(.bottom, 6)
            }
            HStack {
                SelectMenu(selected: model.selected.count, total: model.removableNodes.count,
                           onAll: { model.selected = Set(model.removableNodes.map(\.url)) },
                           onNone: { model.selected = [] })
                Spacer()
                SortMenu(key: $model.sortKey, options: [.size, .name])
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
            if !model.isLoading && model.nodes.isEmpty {
                EmptyStateView(title: String(localized: "Bu klasör boş"), message: String(localized: "Ölçülecek bir şey yok."), symbol: "folder")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sorted) { node in
                            SpaceRow(node: node, fraction: Double(node.size ?? 0) / Double(largest),
                                     removable: model.canRemove(node), cloud: model.isCloudBacked(node),
                                     isSelected: model.selected.contains(node.url),
                                     onToggle: { model.toggle(node) }, onOpen: { model.open(node.url) })
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 12)
                }
                .id(model.current)   // a new folder starts scrolled to the top
            }
        }
    }
}

struct SpaceRow: View {
    let node: SpaceMap.Node
    let fraction: Double
    let removable: Bool
    var cloud = false
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false
    @State private var showLockInfo = false

    var body: some View {
        HStack(spacing: 10) {
            if removable {
                CheckBox(state: isSelected ? .on : .off, action: onToggle)
            } else {
                Button { showLockInfo.toggle() } label: {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.tertiary).frame(width: 17)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showLockInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Silinemez")).font(.system(size: 13, weight: .semibold))
                        Text(String(localized: "Bu, sistemin çalışması için gerekli ya da korumalı bir öğe. Sistem klasörlerini kaldırmak önerilmez; bu yüzden buradan silinemez."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14).frame(width: 260)
                }
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                GeometryReader { proxy in
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.glowDeep, Theme.glow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, proxy.size.width * fraction), height: 3)
                }
                .frame(height: 3)
            }
            if cloud {
                Image(systemName: "icloud").font(.system(size: 11)).foregroundStyle(Theme.review)
                    .help(String(localized: "Bulut depolamada: silersen buluttan ve bağlı cihazlardan da kaldırılır"))
            }
            Group {
                if let size = node.size { Text(size.bytes) } else { ProgressView().controlSize(.mini) }
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .frame(width: 64, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                .opacity(node.isFolder ? 1 : 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.white.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if node.isFolder { onOpen() } }
        .contextMenu { Button(String(localized: "Finder'da göster")) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } }
    }
}

// MARK: - Bubble map

/// Circles sized by disk use, packed around the largest one. Opening a folder zooms out of its bubble.
struct BubbleMap: View {
    let nodes: [SpaceMap.Node]
    let current: URL
    let anchor: UnitPoint
    let isLoading: Bool
    let onOpen: (SpaceMap.Node, UnitPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            let measured = Array(nodes.filter { ($0.size ?? 0) > 0 }.prefix(16))
            let layout = Self.pack(measured.map { Double($0.size ?? 0) }, in: proxy.size)
            ZStack {
                ForEach(Array(measured.enumerated()), id: \.element.id) { index, node in
                    let circle = layout[index]
                    Bubble(node: node, diameter: circle.diameter)
                        .position(circle.center)
                        .onTapGesture {
                            onOpen(node, UnitPoint(x: circle.center.x / proxy.size.width, y: circle.center.y / proxy.size.height))
                        }
                }
                if measured.isEmpty && isLoading {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .id(current)
            .transition(.asymmetric(insertion: .scale(scale: 0.25, anchor: anchor).combined(with: .opacity),
                                    removal: .scale(scale: 2.4, anchor: anchor).combined(with: .opacity)))
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: current)
        .animation(.smooth(duration: 0.4), value: nodes.map(\.size))
        .clipped()
    }

    struct Circle2: Equatable { var center: CGPoint; var diameter: CGFloat }

    /// Places circles (area ∝ value) one by one on an outward spiral at the first spot that does not overlap,
    /// then scales the cluster to fit `size`.
    static func pack(_ values: [Double], in size: CGSize) -> [Circle2] {
        guard let maxValue = values.max(), maxValue > 0, size.width > 0 else { return [] }
        let radii = values.map { max(0.16, sqrt($0 / maxValue)) * 100 }
        var placed: [(CGPoint, CGFloat)] = []
        for r in radii {
            var angle = 0.0, distance = 0.0
            var spot = CGPoint.zero
            while true {
                spot = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance * 0.8)
                if !placed.contains(where: { hypot($0.0.x - spot.x, $0.0.y - spot.y) < $0.1 + r + 6 }) { break }
                angle += 0.35
                distance += 1.2
            }
            placed.append((spot, r))
        }
        let minX = placed.map { $0.0.x - $0.1 }.min()!, maxX = placed.map { $0.0.x + $0.1 }.max()!
        let minY = placed.map { $0.0.y - $0.1 }.min()!, maxY = placed.map { $0.0.y + $0.1 }.max()!
        let scale = min((size.width - 40) / (maxX - minX), (size.height - 40) / (maxY - minY), 2.2)
        let offset = CGPoint(x: size.width / 2 - (minX + maxX) / 2 * scale, y: size.height / 2 - (minY + maxY) / 2 * scale)
        return placed.map { Circle2(center: CGPoint(x: $0.0.x * scale + offset.x, y: $0.0.y * scale + offset.y), diameter: $0.1 * 2 * scale) }
    }
}

struct Bubble: View {
    let node: SpaceMap.Node
    let diameter: CGFloat
    @State private var hovering = false

    /// Folders in the map's cyan-lilac, apps in amber, plain files in pink-violet.
    private var tint: (Color, Color) {
        if node.url.pathExtension == "app" { return (Color(hex: 0xFBBF24), Color(hex: 0xF97316)) }
        return node.isFolder ? (Color(hex: 0x22D3EE), Color(hex: 0xA78BFA)) : (Color(hex: 0xF0ABFC), Color(hex: 0x818CF8))
    }

    var body: some View {
        ZStack {
            GlassSlab(shape: Circle(), tintA: tint.0, tintB: tint.1,
                      depth: min(10, max(3, diameter * 0.06)) + (hovering ? 3 : 0),
                      strength: hovering ? 0.75 : 0.5, highlight: diameter > 40)
            // A small sharp glint on the upper left, like light caught on a glass bead.
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: diameter * 0.22, height: diameter * 0.1)
                .rotationEffect(.degrees(-30))
                .blur(radius: diameter * 0.02)
                .offset(x: -diameter * 0.24, y: -diameter * 0.3)
            if diameter > 56 {
                VStack(spacing: 3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path)).resizable()
                        .frame(width: min(44, diameter * 0.28), height: min(44, diameter * 0.28))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    if diameter > 90 {
                        Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                        Text((node.size ?? 0).bytes).font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: diameter * 0.8)
            }
        }
        .frame(width: diameter, height: diameter)
        .offset(y: hovering ? -3 : 0)
        .scaleEffect(hovering ? 1.03 : 1)
        .shadow(color: tint.0.opacity(hovering ? 0.5 : 0.22), radius: hovering ? 20 : 10, y: 6)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
        .help("\(node.name) · \((node.size ?? 0).bytes)\(node.isFolder ? " · içine girmek için tıkla" : "")")
        .contentShape(Circle())
    }
}
