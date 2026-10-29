import Foundation

public struct CleanRule: Identifiable, Sendable {
    public enum Strategy: Sendable {
        /// Each of these paths that exists becomes one item.
        case paths([String])
        /// Each direct child of a folder becomes one item.
        case children(of: String, skip: Set<String> = [], skipPrefixes: [String] = [], onlyPrefixes: [String] = [],
                      skipRunningApps: Bool = false, policy: SafetyGuard.Policy = .junk)
        /// Files anywhere below a folder that were last modified more than `olderThanDays` ago.
        case oldFiles(in: String, olderThanDays: Int)
        /// A tool's own cleanup command; skipped when the tool is not installed.
        case tool(name: String, command: String, measure: String)
        /// Simulators that are unavailable or have not been booted for `unusedDays`.
        case simulators(unusedDays: Int)
        /// Local AI models managed by Ollama, removed with `ollama rm`.
        case ollamaModels
        /// iOS simulator runtimes, removed with `xcrun simctl runtime delete`.
        case simulatorRuntimes
        /// Known cache folders of apps in ~/Library/Application Support (Electron/Chromium apps).
        case appSupportCaches
        /// Preference files in ~/Library/Preferences that no longer parse.
        case brokenPreferences
        /// Each folder `depth` levels below `root` (e.g. publisher/model) becomes one item.
        case nested(root: String, depth: Int)
        /// Support files of apps that are no longer installed (bundle-identifier names only).
        case orphanedSupportFiles
        /// Installer images and packages; pre-selected only inside `selectedIn`.
        case installers(in: [String], selectedIn: [String])
        /// Big files under these folders. Never selected by default.
        case largeFiles(in: [String], minBytes: Int64)
        /// The Caches and Logs folders inside sandboxed apps' containers, emptied but kept.
        case containerCaches
        /// Items in this user's temporary folder untouched for `olderThanDays`.
        case tempFiles(olderThanDays: Int)
        /// Root-owned children of a system folder; removed with an administrator prompt.
        case adminChildren(of: String, skipPrefixes: [String] = [])
        /// Root-owned files below system log folders untouched for `olderThanDays`.
        case adminOldFiles(in: [String], olderThanDays: Int)
        /// Folders an app rebuilds by itself, keyed by the app's name; skipped while that app is open.
        case appDataCaches([String: [String]])
        /// iOS and iPadOS device backups made by Finder, named after the device.
        case iosBackups
        /// The user's launch agents whose program no longer exists.
        case brokenLaunchAgents
        /// Browser histories, cookies, last sessions and recent-items lists.
        case privacyTraces
        /// Unsigned or tampered apps and launch items (see `Threats`).
        case threats
        /// Children of the per-user cache folder in /var/folders (clang, Metal, helper apps).
        case darwinCaches(skipPrefixes: [String] = [], onlyPrefixes: [String] = [])
        /// AI tools' scratch folders in /tmp (`claude-<uid>/<project>/<session>`) untouched for `olderThanDays`.
        case aiTempFolders(olderThanDays: Int)
        /// Old versions of a self-updating tool; the one `activeLink` points into stays.
        case staleVersions(root: String, activeLink: String)
        /// Audio Units, VST/VST3 plug-ins and audio drivers, from the user's and the system Library.
        case audioPlugins
        /// Byte-identical copies under these folders; the oldest copy of each file is kept and not listed.
        case duplicates(in: [String], minBytes: Int64)
    }

    public let id: String
    public let category: Category
    public let title: String
    public let explanation: String
    public let symbol: String
    public let risk: Risk
    public let strategy: Strategy

    /// `~` in a strategy path stands for the home folder.
    public static func expand(_ path: String, home: URL) -> URL {
        path.hasPrefix("~/") ? home.appending(path: String(path.dropFirst(2))) : URL(filePath: path)
    }
}

extension CleanRule {
    /// The full catalog. Anything not listed here is never touched.
    public static let catalog: [CleanRule] = [
        CleanRule(
            id: "derivedData", category: .xcode, title: "Xcode DerivedData",
            explanation: String(localized: "Derleme ara dosyaları. Xcode bir sonraki derlemede yeniden üretir."),
            symbol: "hammer", risk: .safe,
            strategy: .children(of: "~/Library/Developer/Xcode/DerivedData")),
        CleanRule(
            id: "deviceSupport", category: .simulators, title: String(localized: "iOS Cihaz Sembolleri"),
            explanation: String(localized: "Eski iOS sürümleri için hata ayıklama sembolleri. Cihaz bağlanınca yeniden indirilir."),
            symbol: "iphone", risk: .safe,
            strategy: .children(of: "~/Library/Developer/Xcode/iOS DeviceSupport")),
        CleanRule(
            id: "archives", category: .simulators, title: String(localized: "Xcode Arşivleri"),
            explanation: String(localized: "Yayınlanmış sürümlerin arşivleri. İçindeki dSYM'ler crash raporlarını çözmek için gerekebilir."),
            symbol: "archivebox", risk: .review,
            strategy: .children(of: "~/Library/Developer/Xcode/Archives")),
        CleanRule(
            id: "simulators", category: .simulators, title: String(localized: "Simülatörler"),
            explanation: String(localized: "Kullanılamaz durumdaki simülatörler güvenle silinir. Uzun süredir açılmayanlar yalnız önerilir; silinen simülatörün içindeki uygulamalar ve verileri gider."),
            symbol: "ipad.and.iphone", risk: .review,
            strategy: .simulators(unusedDays: 30)),
        CleanRule(
            id: "npm", category: .devCaches, title: String(localized: "npm önbelleği"),
            explanation: String(localized: "npm'in indirme önbelleği. `npm cache clean --force` ile temizlenir."),
            symbol: "shippingbox", risk: .safe,
            strategy: .tool(name: "npm", command: "npm cache clean --force", measure: "~/.npm/_cacache")),
        CleanRule(
            id: "uv", category: .devCaches, title: String(localized: "uv önbelleği"),
            explanation: String(localized: "Python paket önbelleği. `uv cache clean` ile temizlenir."),
            symbol: "shippingbox", risk: .safe,
            strategy: .tool(name: "uv", command: "uv cache clean", measure: "~/.cache/uv")),
        CleanRule(
            id: "pnpm", category: .devCaches, title: String(localized: "pnpm deposu"),
            explanation: String(localized: "Hiçbir projenin kullanmadığı paketler `pnpm store prune` ile atılır."),
            symbol: "shippingbox", risk: .safe,
            strategy: .tool(name: "pnpm", command: "pnpm store prune", measure: "~/Library/pnpm/store")),
        CleanRule(
            id: "brew", category: .devCaches, title: String(localized: "Homebrew önbelleği"),
            explanation: String(localized: "Eski sürümler ve indirmeler `brew cleanup --prune=all` ile silinir."),
            symbol: "mug", risk: .safe,
            strategy: .tool(name: "brew", command: "brew cleanup --prune=all", measure: "~/Library/Caches/Homebrew")),
        CleanRule(
            id: "runtimes", category: .simulators, title: String(localized: "iOS simülatör sürümleri"),
            explanation: String(localized: "Her iOS sürümü 8 GB civarı yer kaplar. Artık test etmediğin sürümleri sil; o sürümü kullanan simülatörler de çalışmaz olur. Gerekirse Xcode > Settings > Components'ten yeniden indirilir."),
            symbol: "square.stack.3d.down.right", risk: .review,
            strategy: .simulatorRuntimes),
        CleanRule(
            id: "ollama", category: .localModels, title: String(localized: "Ollama modelleri"),
            explanation: String(localized: "Yerel yapay zekâ modelleri. Kullanmadıklarını `ollama rm` ile sil; gerekirse `ollama pull` ile yeniden indirilir."),
            symbol: "cpu", risk: .review,
            strategy: .ollamaModels),
        CleanRule(
            id: "swiftpm", category: .devCaches, title: String(localized: "SwiftPM önbelleği"),
            explanation: String(localized: "Swift paket indirmeleri. Gerektiğinde yeniden indirilir."),
            symbol: "swift", risk: .safe,
            strategy: .children(of: "~/Library/Caches/org.swift.swiftpm")),
        CleanRule(
            id: "browsers", category: .devCaches, title: String(localized: "Test tarayıcıları"),
            explanation: String(localized: "Playwright ve Puppeteer'ın indirdiği tarayıcılar. Silinirse ilk testte yeniden indirilir (`npx playwright install`)."),
            symbol: "globe", risk: .review,
            strategy: .paths(["~/Library/Caches/ms-playwright", "~/Library/Caches/ms-playwright-mcp", "~/.cache/puppeteer"])),
        CleanRule(
            id: "aiAppCaches", category: .aiClutter, title: String(localized: "AI ve editör önbellekleri"),
            explanation: String(localized: "Claude, Cursor, VS Code, Codex, Antigravity gibi uygulamaların önbellek, günlük ve indirilmiş eklenti paketleri. Uygulama açılınca yeniden oluşur. Açık uygulamalarınki atlanır."),
            symbol: "brain.head.profile", risk: .safe,
            strategy: .appSupportCaches),
        CleanRule(
            id: "claudeTemp", category: .aiClutter, title: String(localized: "Claude Code geçici dosyaları"),
            explanation: String(localized: "Claude Code'un /tmp altında bıraktığı oturum çıktıları ve çalışma klasörleri. 1 günden eski olanlar listelenir; kullanımdaki oturumların klasörleri atlanır."),
            symbol: "terminal", risk: .safe,
            strategy: .aiTempFolders(olderThanDays: 1)),
        CleanRule(
            id: "claudeVersions", category: .aiClutter, title: String(localized: "Claude Code eski sürümleri"),
            explanation: String(localized: "Kendini güncelleyen Claude Code'un geride bıraktığı eski sürümler. Kullanımdaki sürüme dokunulmaz."),
            symbol: "clock.arrow.circlepath", risk: .safe,
            strategy: .staleVersions(root: "~/.local/share/claude/versions", activeLink: "~/.local/bin/claude")),
        CleanRule(
            id: "claudeVM", category: .devCaches, title: String(localized: "Claude sanal makine paketleri"),
            explanation: String(localized: "Claude masaüstü uygulamasının Cowork için indirdiği sanal makine imajları (genelde birkaç GB). Silinirse gerektiğinde yeniden indirilir; Claude'u kapatıp sil."),
            symbol: "shippingbox", risk: .review,
            strategy: .children(of: "~/Library/Application Support/Claude/vm_bundles", policy: .knownData)),
        CleanRule(
            id: "localModels", category: .localModels, title: String(localized: "Yerel AI modelleri"),
            explanation: String(localized: "LM Studio ve Hugging Face ile indirilen modeller. Kullanmadıklarını sil; gerekirse yeniden indirilir."),
            symbol: "cpu", risk: .review,
            strategy: .nested(root: "~/.lmstudio/models", depth: 2)),
        CleanRule(
            id: "hfCache", category: .devCaches, title: String(localized: "Hugging Face önbelleği"),
            explanation: String(localized: "Python kütüphanelerinin indirdiği modeller ve veri setleri. Gerektiğinde yeniden indirilir."),
            symbol: "face.smiling", risk: .review,
            strategy: .nested(root: "~/.cache/huggingface/hub", depth: 1)),
        CleanRule(
            id: "darwinCaches", category: .appCaches, title: String(localized: "Sistem önbellekleri (kullanıcı)"),
            explanation: String(localized: "clang, yardımcı uygulamalar ve ikon önbellekleri gibi /var/folders altındaki kullanıcı önbellekleri. İlgili program yeniden üretir."),
            symbol: "internaldrive", risk: .safe,
            strategy: .darwinCaches(skipPrefixes: ["com.apple."])),
        CleanRule(
            id: "darwinAppleCaches", category: .appCaches, title: String(localized: "Apple grafik önbellekleri"),
            explanation: String(localized: "Metal gölgelendirici ve simülatör çizim önbellekleri. Sonraki kullanımda yeniden derlenir; ilk açılış biraz yavaş olabilir, o yüzden seçili gelmez."),
            symbol: "cube", risk: .review,
            strategy: .darwinCaches(onlyPrefixes: ["com.apple.metal", "com.apple.CoreSimulator"])),
        CleanRule(
            id: "appleCaches", category: .appCaches, title: String(localized: "macOS önbellekleri"),
            explanation: String(localized: "Apple servislerinin önbellekleri. Çoğu kendiliğinden yeniden oluşur ama ilgili servis bir süre yavaş çalışabilir; o yüzden seçili gelmez."),
            symbol: "apple.logo", risk: .review,
            strategy: .children(of: "~/Library/Caches", skip: ["com.apple.HomeKit", "com.apple.Safari.SafeBrowsing", "com.apple.dt.Xcode"],
                                skipPrefixes: [], onlyPrefixes: ["com.apple."], skipRunningApps: true)),
        CleanRule(
            id: "brokenPrefs", category: .broken, title: String(localized: "Bozuk tercih dosyaları"),
            explanation: String(localized: "Açılamayan, bozulmuş ayar dosyaları. Uygulama bir sonraki açılışta yenisini oluşturur."),
            symbol: "wrench.adjustable", risk: .review,
            strategy: .brokenPreferences),
        CleanRule(
            id: "orphans", category: .appLeftovers, title: String(localized: "Kaldırılmış uygulama artıkları"),
            explanation: String(localized: "Artık kurulu olmayan uygulamaların ayar ve destek dosyaları. Aynı geliştiricinin kurulu bir uygulaması varsa dokunulmaz; yine de gözden geçir."),
            symbol: "folder.badge.minus", risk: .review,
            strategy: .orphanedSupportFiles),
        CleanRule(
            id: "brokenAgents", category: .broken, title: String(localized: "Bozuk başlangıç öğeleri"),
            explanation: String(localized: "Kaldırılmış bir uygulamayı her açılışta başlatmaya çalışan servis kayıtları. Başlatacakları program artık yok."),
            symbol: "bolt.slash", risk: .safe,
            strategy: .brokenLaunchAgents),
        CleanRule(
            id: "audioPlugins", category: .appLeftovers, title: String(localized: "Ses eklentileri"),
            explanation: String(localized: "Audio Unit, VST, VST3 eklentileri ve ses sürücüleri. Kullanmadığın DAW ya da eklenti paketlerinden kalanlar yer kaplar; kullandıklarını silersen projelerin açılmaz, o yüzden seçili gelmez. Sistem klasöründekiler yönetici parolası ister."),
            symbol: "waveform", risk: .review,
            strategy: .audioPlugins),
        CleanRule(
            id: "installers", category: .appLeftovers, title: String(localized: "Kurulum dosyaları"),
            explanation: String(localized: "Uygulamayı kurduktan sonra gereği kalmayan .dmg, .pkg ve .xip dosyaları. İndirilenler'dekiler seçili gelir."),
            symbol: "shippingbox.and.arrow.backward", risk: .safe,
            strategy: .installers(in: ["~/Downloads", "~/Desktop", "~/Documents"], selectedIn: ["~/Downloads"])),
        CleanRule(
            id: "appCaches", category: .appCaches, title: String(localized: "Uygulama önbellekleri"),
            explanation: String(localized: "Uygulamaların geçici dosyaları; ihtiyaç olunca yeniden oluşur. Açık uygulamalar ve Apple sistem önbellekleri atlanır."),
            symbol: "app.badge", risk: .safe,
            strategy: .children(
                of: "~/Library/Caches",
                skip: ["Homebrew", "org.swift.swiftpm", "ms-playwright", "ms-playwright-mcp",
                       "CloudKit", "FamilyCircle", "GeoServices", "PassKit", "CleanMac", "Temizle", "dev.merttastan.cleanmac", "dev.merttastan.temizle"],
                skipPrefixes: ["com.apple."],
                skipRunningApps: true)),
        CleanRule(
            id: "containerCaches", category: .appCaches, title: String(localized: "Sandbox uygulama önbellekleri"),
            explanation: String(localized: "App Store ve sandbox uygulamalarının kendi kutularındaki önbellek ve günlükler. Klasör yerinde kalır, içi boşaltılır; açık uygulamalarınki atlanır."),
            symbol: "shippingbox.circle", risk: .safe,
            strategy: .containerCaches),
        CleanRule(
            id: "tempFiles", category: .system, title: String(localized: "Geçici dosyalar"),
            explanation: String(localized: "Uygulamaların geçici klasörde unuttuğu, 3 günden uzun süredir dokunulmamış dosyalar."),
            symbol: "clock.arrow.circlepath", risk: .safe,
            strategy: .tempFiles(olderThanDays: 3)),
        CleanRule(
            id: "systemCaches", category: .system, title: String(localized: "Sistem önbellekleri"),
            explanation: String(localized: "/Library/Caches altındaki üçüncü parti önbellekler. Yönetici parolası ister; Apple'ınkilere dokunulmaz."),
            symbol: "lock.shield", risk: .review,
            strategy: .adminChildren(of: "/Library/Caches", skipPrefixes: ["com.apple."])),
        CleanRule(
            id: "systemLogs", category: .system, title: String(localized: "Sistem günlükleri"),
            explanation: String(localized: "/Library/Logs ve /var/log altında bir haftadır yazılmamış günlükler. Yönetici parolası ister."),
            symbol: "lock.doc", risk: .review,
            strategy: .adminOldFiles(in: ["/Library/Logs", "/private/var/log"], olderThanDays: 7)),
        CleanRule(
            id: "deletedUsers", category: .system, title: String(localized: "Silinmiş kullanıcılar"),
            explanation: String(localized: "Silinen kullanıcı hesaplarından kalan disk görüntüleri ve klasörler. İçinde o kişinin dosyaları olabilir; yönetici parolası ister."),
            symbol: "person.crop.circle.badge.xmark", risk: .review,
            strategy: .adminChildren(of: "/Users/Deleted Users")),
        CleanRule(
            id: "iosBackups", category: .system, title: String(localized: "iPhone ve iPad yedekleri"),
            explanation: String(localized: "Finder'ın aldığı cihaz yedekleri. iCloud yedeğin varsa ya da cihazı artık kullanmıyorsan eski yedekleri silebilirsin."),
            symbol: "iphone.gen3", risk: .review,
            strategy: .iosBackups),
        CleanRule(
            id: "iosDeviceLogs", category: .system, title: String(localized: "iOS cihaz günlükleri"),
            explanation: String(localized: "Bağlanan cihazlardan alınmış çökme ve tanılama günlükleri."),
            symbol: "iphone.gen3.radiowaves.left.and.right", risk: .safe,
            strategy: .children(of: "~/Library/Logs/CrashReporter/MobileDevice", policy: .knownData)),
        CleanRule(
            id: "mailDownloads", category: .mail, title: String(localized: "Mail indirilenleri"),
            explanation: String(localized: "Mail'de açtığın eklerin kopyaları. Ekler e-postada durmaya devam eder."),
            symbol: "envelope.badge", risk: .review,
            strategy: .children(of: "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", policy: .knownData)),
        CleanRule(
            id: "xcodeCaches", category: .xcode, title: String(localized: "Xcode önbellekleri"),
            explanation: String(localized: "Xcode'un ve simülatörlerin önbellekleri, iOS cihaz günlükleri. Gerekince yeniden oluşur."),
            symbol: "hammer.circle", risk: .safe,
            strategy: .paths(["~/Library/Caches/com.apple.dt.Xcode"])),
        CleanRule(
            id: "simulatorCaches", category: .simulators, title: String(localized: "Simülatör önbellekleri"),
            explanation: String(localized: "CoreSimulator'ın dyld ve görüntü önbellekleri. Simülatör açılınca yeniden oluşur."),
            symbol: "ipad.and.iphone", risk: .safe,
            strategy: .children(of: "~/Library/Developer/CoreSimulator/Caches", policy: .knownData)),
        CleanRule(
            id: "appDataCaches", category: .appCaches, title: String(localized: "Medya önbellekleri"),
            explanation: String(localized: "Spotify'ın akış önbelleği ve Adobe uygulamalarının medya önbelleği. Uygulama açıkken atlanır."),
            symbol: "play.square.stack", risk: .safe,
            strategy: .appDataCaches([
                "Spotify": ["~/Library/Application Support/Spotify/PersistentCache/Storage"],
                "Adobe": ["~/Library/Application Support/Adobe/Common/Media Cache Files",
                          "~/Library/Application Support/Adobe/Common/Media Cache"],
            ])),
        CleanRule(
            id: "threats", category: .threats, title: String(localized: "Şüpheli öğeler"),
            explanation: String(localized: "İmzası olmayan ya da bozulmuş uygulamalar ve imzasız bir programı gizli bir klasörden başlatan arka plan servisleri. Bir virüs veritabanı değil, Gatekeeper'ın güvenmeyeceği şeylerin listesi: kendi derlediğin bir araç da burada görünebilir. Hiçbiri seçili gelmez; sistem klasöründekiler yönetici parolası ister."),
            symbol: "exclamationmark.shield", risk: .review,
            strategy: .threats),
        CleanRule(
            id: "privacy", category: .privacy, title: String(localized: "Tarayıcı izleri ve son öğeler"),
            explanation: String(localized: "Tarama geçmişi, çerezler, son oturum sekmeleri ve Finder'ın son öğeler listeleri. Çerezler silinince sitelerden çıkış yapılır. Kayıtlı parolalar, yer imleri ve otomatik doldurma verilerine dokunulmaz; açık tarayıcılarınki atlanır."),
            symbol: "hand.raised", risk: .review,
            strategy: .privacyTraces),
        CleanRule(
            id: "downloadRecords", category: .privacy, title: String(localized: "İndirme kayıtları"),
            explanation: String(localized: "macOS'un indirdiğin her dosya için tuttuğu kayıt (nereden, ne zaman). Dosyaların kendisine dokunulmaz."),
            symbol: "arrow.down.doc", risk: .review,
            strategy: .tool(name: "sqlite3",
                            command: "sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 'DELETE FROM LSQuarantineEvent; VACUUM;'",
                            measure: "~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")),
        CleanRule(
            id: "logs", category: .logs, title: String(localized: "Eski günlükler"),
            explanation: String(localized: "2 günden eski uygulama günlük dosyaları."),
            symbol: "doc.text", risk: .safe,
            strategy: .oldFiles(in: "~/Library/Logs", olderThanDays: 2)),
        CleanRule(
            id: "oldDownloads", category: .largeFiles, title: String(localized: "Eski indirilenler"),
            explanation: String(localized: "İndirilenler'de 90 günden uzun süredir dokunulmamış dosyalar. Çoğu bir kez kullanılıp unutulmuştur; yine de tek tek bak."),
            symbol: "arrow.down.circle", risk: .review,
            strategy: .oldFiles(in: "~/Downloads", olderThanDays: 90)),
        CleanRule(
            id: "duplicateDownloads", category: .largeFiles, title: String(localized: "Kopya indirilenler"),
            explanation: String(localized: "İndirilenler'de aynı dosyanın birden fazla kopyası. En eski kopya listelenmez ve yerinde kalır."),
            symbol: "doc.on.doc", risk: .review,
            strategy: .duplicates(in: ["~/Downloads"], minBytes: 100_000)),
        CleanRule(
            id: "largeFiles", category: .largeFiles, title: String(localized: "Büyük dosyalar"),
            explanation: String(localized: "İndirilenler, Masaüstü, Belgeler, Filmler, Müzik ve Resimler'deki 100 MB üstü dosyalar. Hiçbiri otomatik seçilmez; tek tek bak."),
            symbol: "doc.zipper", risk: .review,
            strategy: .largeFiles(in: ["~/Downloads", "~/Desktop", "~/Documents", "~/Movies", "~/Music", "~/Pictures"],
                                  minBytes: 100_000_000)),
    ]
}
