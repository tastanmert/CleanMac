import SwiftUI
import CleanMacCore

enum Theme {
    // App-wide accent: warm gold to ember. Module worlds below only tint backgrounds and orbs.
    static let glow = Color(hex: 0xFFC24B)
    static let glowDeep = Color(hex: 0xFF6A3D)
    static let safe = Color(hex: 0x5EE6C0)          // mint: rebuilt automatically
    static let review = Color(hex: 0xB9A6FF)        // soft violet: look before removing
    static let text = Color(hex: 0xF6F4FB)
    static let secondary = Color(hex: 0xC9C4DA)     // tinted, never plain gray
    static let tertiary = Color(hex: 0x9790AE)
    static let hairline = Color.white.opacity(0.08)
    static let row = Color.white.opacity(0.05)
    static let sidebar = Color.black.opacity(0.14)   // glass over the module's colour, not a separate panel
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// A sidebar module: its own colour world, landing copy and content.
enum Module: String, CaseIterable, Identifiable {
    case smart, junk, developer, ai, protection, applications, performance, clutter, spaceLens, trash, tools, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: String(localized: "Akıllı Tarama")
        case .junk: String(localized: "Sistem Çöpü")
        case .developer: String(localized: "Geliştirici ve Sistem")
        case .ai: String(localized: "AI Artıkları")
        case .protection: String(localized: "Koruma")
        case .applications: String(localized: "Uygulamalar")
        case .performance: String(localized: "Performans")
        case .clutter: String(localized: "Dağınıklık")
        case .spaceLens: String(localized: "Alan Haritası")
        case .trash: String(localized: "Çöp")
        case .tools: String(localized: "Araçlarım")
        case .activity: String(localized: "Etkinlik")
        }
    }

    var subtitle: String {
        switch self {
        case .smart: String(localized: "Mac'ini baştan sona tara: çöp, uygulamalar, dağınıklık ve bakım. Seçmediğin hiçbir şey silinmez.")
        case .junk: String(localized: "Uygulamaların ve macOS'un biriktirdiği geçici dosyaları temizle.")
        case .developer: String(localized: "Simülatörler, paket önbellekleri, sistem günlükleri ve cihaz yedekleri. Hızlı taramaya girmez; tek tek bak.")
        case .ai: String(localized: "AI uygulamalarının önbelleklerini ve kullanmadığın yerel modelleri gözden geçir.")
        case .protection: String(localized: "Şüpheli uygulama ve servisleri, tarayıcı izlerini, son öğeler listelerini ve verdiğin izinleri gözden geçir.")
        case .applications: String(localized: "Uygulamaları geride hiçbir şey bırakmadan kaldır.")
        case .performance: String(localized: "Mac'ini bakım görevleriyle tazele, açılışta çalışanları yönet.")
        case .clutter: String(localized: "Büyük, unutulmuş ve kopya dosyaları bul.")
        case .spaceLens: String(localized: "Diskinde neyin ne kadar yer kapladığını gör, gizli klasörler dahil.")
        case .trash: String(localized: "Çöp'te bekleyen alanı geri kazan.")
        case .tools: String(localized: "CleanMac'in bütün araçları tek yerde. Ara, istediğine doğrudan git.")
        case .activity: String(localized: "Ne zaman ne kadar yer açtığını ve yoksaydığın öğeleri gör.")
        }
    }

    var bullets: [(symbol: String, text: String)] {
        switch self {
        case .smart: [("wind", String(localized: "Sistem çöpü ve Mail ekleri")), ("hand.raised", String(localized: "Tehditler, tarayıcı izleri, uygulama artıkları")), ("bolt", String(localized: "Bakım önerileri ve kopya indirilenler"))]
        case .junk: [("square.stack.3d.up", String(localized: "Önbellekler, günlükler, Xcode çöpü")), ("brain", String(localized: "AI araçlarının artıkları ve yerel modeller")), ("envelope", String(localized: "Mail ekleri"))]
        case .developer: [("ipad.and.iphone", String(localized: "Simülatörler, iOS sürümleri, arşivler")), ("shippingbox", "npm, uv, pnpm, Homebrew, Hugging Face"), ("gearshape.2", String(localized: "Sistem günlükleri, silinmiş kullanıcılar, yedekler"))]
        case .ai: [("brain.head.profile", String(localized: "Claude, Cursor, VS Code önbellekleri")), ("cpu", String(localized: "Ollama modelleri")), ("face.smiling", String(localized: "LM Studio ve Hugging Face"))]
        case .protection: [("exclamationmark.shield", String(localized: "İmzasız uygulamalar ve şüpheli servisler")), ("safari", "Safari, Chrome, Firefox, Brave, Edge, Arc"), ("clock.arrow.circlepath", String(localized: "Son öğeler ve indirme kayıtları")), ("hand.raised", String(localized: "Kamera, mikrofon ve dosya izinleri"))]
        case .applications: [("xmark.app", String(localized: "Uygulama kaldırıcı")), ("arrow.down.app", String(localized: "Güncellemeler")), ("folder.badge.minus", String(localized: "Artık ve kurulum dosyaları"))]
        case .performance: [("wrench.and.screwdriver", String(localized: "Bakım görevleri")), ("power", String(localized: "Başlangıç öğeleri")), ("gearshape.2", String(localized: "Arka plan servisleri"))]
        case .clutter: [("doc.zipper", String(localized: "Büyük ve eski dosyalar")), ("doc.on.doc", String(localized: "Kopya dosyalar ve indirilenler")), ("photo.stack", String(localized: "Benzer görseller"))]
        case .spaceLens: [("chart.pie", String(localized: "Görsel alan haritası")), ("eye.slash", String(localized: "Gizli klasörler")), ("folder", String(localized: "Büyük klasörler"))]
        case .trash: [("trash", String(localized: "Çöp'teki öğeler")), ("arrow.uturn.backward", String(localized: "Boşaltmadan önce geri alınabilir")), ("externaldrive", String(localized: "Disk alanı geri gelir"))]
        case .tools: [("square.grid.3x3", String(localized: "20 araç")), ("magnifyingglass", String(localized: "Ara ve aç")), ("arrow.right.circle", String(localized: "Doğrudan ilgili ekrana"))]
        case .activity: [("chart.bar", String(localized: "Son 30 günde açılan alan")), ("list.bullet", String(localized: "Temizlik geçmişi")), ("eye.slash", String(localized: "Yoksayılan öğeler"))]
        }
    }

    /// Sidebar and orb symbol.
    var symbol: String {
        switch self {
        case .smart: "desktopcomputer"
        case .junk: "wind"
        case .developer: "hammer.fill"
        case .ai: "brain.fill"
        case .protection: "hand.raised.fill"
        case .applications: "square.grid.2x2.fill"
        case .performance: "bolt.fill"
        case .clutter: "folder.fill"
        case .spaceLens: "chart.pie.fill"
        case .trash: "trash.fill"
        case .tools: "square.grid.3x3.fill"
        case .activity: "chart.bar.fill"
        }
    }

    /// Cleaning categories this module scans; nil for tool modules.
    var categories: [CleanMacCore.Category]? {
        switch self {
        case .smart: [.xcode, .appCaches, .logs, .broken, .mail, .appLeftovers, .largeFiles, .threats, .privacy]
        // Everyday cleanup: system junk, AI clutter, mail attachments. Developer and system-level items have their own tool.
        case .junk: [.xcode, .appCaches, .logs, .broken, .aiClutter, .localModels, .mail]
        case .developer: [.simulators, .devCaches, .system]
        case .ai: [.aiClutter, .localModels]
        case .protection: [.threats, .privacy]
        default: nil
        }
    }

    var actionTitle: String {
        switch self {
        case .applications, .performance, .spaceLens: String(localized: "Başlat")
        case .trash, .activity, .tools: String(localized: "Aç")
        default: String(localized: "Tara")
        }
    }

    var palette: Palette {
        switch self {
        case .smart: Palette(top: 0x0E0B2A, bottom: 0x1E1150, orbA: 0x7C3AED, orbB: 0x06B6D4)
        case .junk: Palette(top: 0x041E1C, bottom: 0x0A3A33, orbA: 0x2DD4BF, orbB: 0xA3E635)
        case .developer: Palette(top: 0x06131F, bottom: 0x0B2740, orbA: 0x38BDF8, orbB: 0x34D399)
        case .ai: Palette(top: 0x1C0A2B, bottom: 0x3A0E38, orbA: 0xF472B6, orbB: 0xA78BFA)
        case .protection: Palette(top: 0x0A1A12, bottom: 0x123526, orbA: 0x4ADE80, orbB: 0x22D3EE)
        case .applications: Palette(top: 0x1C1205, bottom: 0x3A2208, orbA: 0xFBBF24, orbB: 0xF97316)
        case .performance: Palette(top: 0x24060E, bottom: 0x4A0E1C, orbA: 0xFB7185, orbB: 0xF59E0B)
        case .clutter: Palette(top: 0x071A2E, bottom: 0x10305A, orbA: 0x60A5FA, orbB: 0x818CF8)
        case .spaceLens: Palette(top: 0x0F141C, bottom: 0x1F2A3A, orbA: 0x22D3EE, orbB: 0xC4B5FD)
        case .trash: Palette(top: 0x141416, bottom: 0x2A2A30, orbA: 0xA1A1AA, orbB: 0xFDA4AF)
        case .tools: Palette(top: 0x0F1A24, bottom: 0x1B3040, orbA: 0x5EEAD4, orbB: 0x93C5FD)
        case .activity: Palette(top: 0x10142A, bottom: 0x1C2350, orbA: 0x818CF8, orbB: 0xF0ABFC)
        }
    }
}

struct Palette: Hashable {
    let top: UInt32, bottom: UInt32, orbA: UInt32, orbB: UInt32

    var background: LinearGradient {
        LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var orb: LinearGradient {
        LinearGradient(colors: [Color(hex: orbA), Color(hex: orbB)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var glow: Color { Color(hex: orbA) }
}

extension CleanMacCore.Category {
    /// Subcategory names (the manager's middle column).
    var title: String {
        switch self {
        case .xcode: String(localized: "Xcode çöpü")
        case .appCaches: String(localized: "Kullanıcı önbellekleri")
        case .logs: String(localized: "Kullanıcı günlükleri")
        case .broken: String(localized: "Bozuk öğeler")
        case .aiClutter: String(localized: "AI çöp dosyaları")
        case .localModels: String(localized: "Yerel modeller")
        case .mail: String(localized: "Mail ekleri")
        case .simulators: String(localized: "Xcode ve simülatörler")
        case .devCaches: String(localized: "Paket ve model önbellekleri")
        case .system: String(localized: "Sistem ve cihaz dosyaları")
        case .appLeftovers: String(localized: "Uygulama artıkları")
        case .largeFiles: String(localized: "Büyük dosyalar")
        case .threats: String(localized: "Şüpheli öğeler")
        case .privacy: String(localized: "Gizlilik")
        }
    }

    var symbol: String {
        switch self {
        case .xcode: "hammer.fill"
        case .appCaches: "square.stack.3d.up.fill"
        case .logs: "doc.text.fill"
        case .broken: "wrench.adjustable.fill"
        case .aiClutter: "brain"
        case .localModels: "cpu.fill"
        case .mail: "envelope.fill"
        case .simulators: "ipad.and.iphone"
        case .devCaches: "shippingbox.fill"
        case .system: "gearshape.2.fill"
        case .appLeftovers: "folder.badge.minus"
        case .largeFiles: "doc.zipper"
        case .threats: "exclamationmark.shield.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    /// Tint of the category's tile in the manager.
    var tint: Color {
        switch self {
        case .xcode, .simulators: Color(hex: 0x38BDF8)
        case .appCaches, .broken: Color(hex: 0x2DD4BF)
        case .logs: Color(hex: 0xA3E635)
        case .aiClutter, .localModels: Color(hex: 0xF472B6)
        case .mail: Color(hex: 0x60A5FA)
        case .devCaches: Color(hex: 0x34D399)
        case .system: Color(hex: 0xA1A1AA)
        case .appLeftovers: Color(hex: 0xFBBF24)
        case .largeFiles: Color(hex: 0x818CF8)
        case .threats: Color(hex: 0xFB7185)
        case .privacy: Color(hex: 0x4ADE80)
        }
    }

    var blurb: String {
        switch self {
        case .xcode: String(localized: "Xcode'un derleme ara dosyaları ve önbellekleri. Projeler yavaşladıysa ya da yer lazımsa temizlenebilir; Xcode yeniden oluşturur.")
        case .appCaches: String(localized: "Uygulamaların hızlı açılmak için biriktirdiği önbellekler. Zamanla şişer; silinince uygulama yeniden oluşturur.")
        case .logs: String(localized: "Uygulamaların tuttuğu iki günden eski günlükler. Bir sorunu incelemiyorsan işe yaramaz.")
        case .broken: String(localized: "Açılamayan tercih dosyaları ve programı artık olmayan başlangıç öğeleri.")
        case .aiClutter: String(localized: "Claude, Codex, Gemini, Cursor gibi AI araçlarının önbellekleri, günlükleri ve geçici dosyaları.")
        case .localModels: String(localized: "Ollama ve LM Studio ile indirilmiş modeller. Kullanmadıklarını kaldır.")
        case .mail: String(localized: "Mail'de açılan eklerin indirilmiş kopyaları; asılları mesajlarda durur.")
        case .simulators: String(localized: "Cihaz sembolleri, arşivler, simülatörler ve iOS sürümleri.")
        case .devCaches: String(localized: "npm, uv, pnpm, Homebrew, SwiftPM, test tarayıcıları ve Hugging Face önbellekleri.")
        case .system: String(localized: "Geçici dosyalar, sistem önbellek ve günlükleri, silinmiş kullanıcılar, cihaz yedekleri.")
        case .appLeftovers: String(localized: "Kaldırılmış uygulamaların artıkları, ses eklentileri ve kurulum dosyaları.")
        case .largeFiles: String(localized: "100 MB üstü dosyalar ve indirilenler.")
        case .threats: String(localized: "İmzasız ya da imzası bozuk uygulamalar ve gizli klasörden çalışan arka plan servisleri. Virüs veritabanı değil; Gatekeeper'ın güvenmeyeceği şeyler.")
        case .privacy: String(localized: "Tarayıcı geçmişi, çerezler, son öğeler.")
        }
    }

    /// The manager's left column groups subcategories into sections (Sistem Çöpü › Xcode çöpü…).
    var section: String {
        switch self {
        case .xcode, .appCaches, .logs, .broken: String(localized: "Sistem Çöpü")
        case .aiClutter, .localModels: String(localized: "AI Dağınıklığı")
        case .mail: String(localized: "Mail Ekleri")
        case .simulators, .devCaches: String(localized: "Geliştirici")
        case .system: String(localized: "Sistem ve Cihaz")
        case .appLeftovers: String(localized: "Uygulamalar")
        case .largeFiles: String(localized: "Dağınıklık")
        case .threats: String(localized: "Tehditler")
        case .privacy: String(localized: "Gizlilik")
        }
    }
}

extension Int64 {
    var bytes: String { formatted(.byteCount(style: .file)) }
}

/// Content fades and settles slightly; no blur, which is costly on a full page.
struct BlurFade: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content.opacity(active ? 0 : 1).scaleEffect(active ? 0.985 : 1)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition { .modifier(active: BlurFade(active: true), identity: BlurFade(active: false)) }
}
