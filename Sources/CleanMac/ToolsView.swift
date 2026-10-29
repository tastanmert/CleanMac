import SwiftUI
import CleanMacCore

/// Every tool as a glass card with search; a card opens its screen directly.
struct ToolsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    /// Pinned tool titles, kept between launches (the Favorites row).
    @AppStorage("favoriteTools") private var favoritesRaw = ""
    /// When each tool was last opened, as "title=timestamp" lines.
    @AppStorage("toolLastUsed") private var lastUsedRaw = ""

    private var favorites: [String] { favoritesRaw.split(separator: "\n").map(String.init) }
    private func toggleFavorite(_ title: String) {
        var list = favorites
        if let i = list.firstIndex(of: title) { list.remove(at: i) } else { list.append(title) }
        favoritesRaw = list.joined(separator: "\n")
    }
    private var lastUsed: [String: Date] {
        Dictionary(lastUsedRaw.split(separator: "\n").compactMap { line -> (String, Date)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let t = Double(parts[1]) else { return nil }
            return (String(parts[0]), Date(timeIntervalSince1970: t))
        }, uniquingKeysWith: { a, _ in a })
    }
    private func markUsed(_ title: String) {
        var map = lastUsed
        map[title] = .now
        lastUsedRaw = map.map { "\($0.key)=\($0.value.timeIntervalSince1970)" }.joined(separator: "\n")
    }

    struct Tool: Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let symbol: String
        let module: Module
        let open: (AppModel) -> Void
    }

    private var tools: [Tool] {
        func scan(_ m: Module) -> (AppModel) -> Void { { $0.select(m) } }
        return [
            Tool(title: String(localized: "Sistem Çöpü"), detail: String(localized: "Önbellekler, günlükler, Xcode çöpü, AI artıkları"), symbol: "wind", module: .junk, open: scan(.junk)),
            Tool(title: String(localized: "AI Artıkları"), detail: String(localized: "AI uygulaması önbellekleri, yerel modeller"), symbol: "brain", module: .ai, open: scan(.ai)),
            Tool(title: String(localized: "Geliştirici ve Sistem"), detail: String(localized: "Simülatörler, paket önbellekleri, sistem günlükleri, yedekler"), symbol: "hammer", module: .developer, open: scan(.developer)),
            Tool(title: String(localized: "Gizlilik"), detail: String(localized: "Tarayıcı izleri, son öğeler"), symbol: "hand.raised", module: .protection, open: scan(.protection)),
            Tool(title: String(localized: "Uygulama izinleri"), detail: String(localized: "Kamera, mikrofon, dosya izinleri"), symbol: "lock.shield", module: .protection,
                 open: { _ in model.panel = .permissions }),
            Tool(title: String(localized: "Wi‑Fi ağları"), detail: String(localized: "Mac'in kendiliğinden bağlandığı ağlar"), symbol: "wifi", module: .protection,
                 open: { _ in model.panel = .wifi }),
            Tool(title: String(localized: "Kaldırıcı"), detail: String(localized: "Uygulamaları artıklarıyla kaldır"), symbol: "xmark.app", module: .applications, open: { $0.open(.applications, tab: 0) }),
            Tool(title: String(localized: "Güncellemeler"), detail: "Sparkle, Homebrew, macOS", symbol: "arrow.down.app", module: .applications, open: { $0.open(.applications, tab: 3) }),
            Tool(title: String(localized: "Artık dosyalar"), detail: String(localized: "Kaldırılmış uygulamalardan kalanlar"), symbol: "folder.badge.minus", module: .applications, open: { $0.open(.applications, tab: 1) }),
            Tool(title: String(localized: "Kurulum dosyaları"), detail: ".dmg, .pkg, .xip", symbol: "shippingbox", module: .applications, open: { $0.open(.applications, tab: 2) }),
            Tool(title: String(localized: "Bakım görevleri"), detail: String(localized: "DNS, Spotlight, Mail, anlık görüntüler"), symbol: "wrench.and.screwdriver", module: .performance, open: { $0.open(.performance, tab: 0) }),
            Tool(title: String(localized: "Başlangıç öğeleri"), detail: String(localized: "Açılışta çalışan servisler"), symbol: "power", module: .performance, open: { $0.open(.performance, tab: 1) }),
            Tool(title: String(localized: "Enerji"), detail: String(localized: "Pil, uyku engelleri, enerji harcayanlar"), symbol: "battery.75percent", module: .performance, open: { $0.open(.performance, tab: 2) }),
            Tool(title: String(localized: "Büyük ve eski dosyalar"), detail: String(localized: "100 MB üstü dosyalar"), symbol: "doc.zipper", module: .clutter, open: { $0.open(.clutter, tab: 0) }),
            Tool(title: String(localized: "Kopyalar"), detail: String(localized: "Birebir aynı dosyalar"), symbol: "doc.on.doc", module: .clutter, open: { $0.open(.clutter, tab: 1) }),
            Tool(title: String(localized: "Benzer görseller"), detail: String(localized: "Birbirine benzeyen fotoğraflar"), symbol: "photo.stack", module: .clutter, open: { $0.open(.clutter, tab: 3) }),
            Tool(title: String(localized: "Eski indirilenler"), detail: String(localized: "90 gündür dokunulmamış indirmeler"), symbol: "arrow.down.circle", module: .clutter, open: { $0.open(.clutter, tab: 2) }),
            Tool(title: String(localized: "Alan Haritası"), detail: String(localized: "Diskte ne ne kadar yer kaplıyor"), symbol: "chart.pie", module: .spaceLens, open: { $0.open(.spaceLens) }),
            Tool(title: String(localized: "Çöp"), detail: String(localized: "Çöp kutuları ve boşaltma"), symbol: "trash", module: .trash, open: { $0.open(.trash) }),
            Tool(title: String(localized: "Etkinlik"), detail: String(localized: "Temizlik geçmişi ve yoksayılanlar"), symbol: "chart.bar", module: .activity, open: { $0.open(.activity) }),
        ]
    }

    var body: some View {
        let visible = search.isEmpty ? tools : tools.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)
        }
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Araçlarım")).font(.system(size: 26, weight: .regular))
                Spacer()
                TextField(String(localized: "Araç ara"), text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            .padding(.horizontal, 32).padding(.top, 52).padding(.bottom, 16)
            ScrollView {
                let pinned = visible.filter { favorites.contains($0.title) }
                let others = visible.filter { !favorites.contains($0.title) }
                VStack(alignment: .leading, spacing: 10) {
                    if !pinned.isEmpty {
                        Text(String(localized: "Favoriler")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        grid(pinned)
                        Text(String(localized: "Diğer araçlar")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary).padding(.top, 8)
                    }
                    grid(others)
                }
                .padding(.horizontal, 32).padding(.bottom, 24)
                .animation(.smooth(duration: 0.3), value: favoritesRaw)
            }
            if visible.isEmpty {
                EmptyStateView(title: String(localized: "Araç bulunamadı"), message: String(localized: "Başka bir kelime dene."), symbol: "magnifyingglass")
            }
        }
    }
}

extension ToolsView {
    private func grid(_ list: [Tool]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            ForEach(list) { tool in
                ToolCard(tool: tool, isFavorite: favorites.contains(tool.title), lastUsed: lastUsed[tool.title],
                         onFavorite: { toggleFavorite(tool.title) }) {
                    markUsed(tool.title)
                    tool.open(model)
                }
            }
        }
    }
}

struct ToolCard: View {
    let tool: ToolsView.Tool
    var isFavorite = false
    var lastUsed: Date?
    var onFavorite: () -> Void = {}
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tool.module.palette.orb))
                    .shadow(color: tool.module.palette.glow.opacity(hovering ? 0.6 : 0.25), radius: hovering ? 10 : 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(tool.detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(2)
                    if let lastUsed {
                        Text(String(localized: "Son kullanım: \(lastUsed.formatted(.relative(presentation: .named)))"))
                            .font(.system(size: 10)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isFavorite ? Theme.glow : Theme.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .opacity(isFavorite || hovering ? 1 : 0)
                .help(isFavorite ? String(localized: "Favorilerden çıkar") : String(localized: "Favorilere ekle"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background {
                GlassSlab(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                          tintA: Color(hex: tool.module.palette.orbA), tintB: Color(hex: tool.module.palette.orbB),
                          depth: hovering ? 7 : 4, strength: hovering ? 0.3 : 0.14)
            }
            .offset(y: hovering ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: hovering)
    }
}
