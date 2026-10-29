import Foundation

/// One-off system maintenance commands. Tasks that need an administrator ask for the password
/// in macOS's own dialog (via `osascript … with administrator privileges`); CleanMac never sees it.
public enum Maintenance {
    public struct Task: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let explanation: String
        public let symbol: String
        public let needsAdmin: Bool
        let command: String
    }

    public static let tasks: [Task] = [
        Task(id: "dns", title: String(localized: "DNS önbelleğini temizle"),
             explanation: String(localized: "Bazı siteler açılmıyor ya da eski adrese gidiyorsa çözer. Zararsız, hemen biter."),
             symbol: "network", needsAdmin: true,
             command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
        Task(id: "ram", title: String(localized: "Belleği boşalt"),
             explanation: String(localized: "Diskte önbelleğe alınmış verileri bellekten atar. Mac ağır bir işten sonra yavaş kaldıysa işe yarayabilir."),
             symbol: "memorychip", needsAdmin: true,
             command: "purge"),
        Task(id: "launchServices", title: String(localized: "\"Birlikte Aç\" menüsünü onar"),
             explanation: String(localized: "Sağ tık > Birlikte Aç menüsündeki kopya ya da eski uygulamaları temizler."),
             symbol: "list.bullet.rectangle", needsAdmin: false,
             command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"),
        Task(id: "spotlight", title: String(localized: "Spotlight dizinini yeniden oluştur"),
             explanation: String(localized: "Spotlight dosya bulamıyorsa ya da yanlış sonuç veriyorsa. Yeniden dizinleme arka planda bir süre sürer."),
             symbol: "magnifyingglass", needsAdmin: true,
             command: "mdutil -E /"),
        Task(id: "quicklook", title: String(localized: "Hızlı Bakış önizlemelerini sıfırla"),
             explanation: String(localized: "Boşluk tuşuyla açılan önizlemeler bozuk ya da eski görünüyorsa."),
             symbol: "eye", needsAdmin: false,
             command: "qlmanage -r && qlmanage -r cache"),
        Task(id: "mail", title: String(localized: "Mail'i hızlandır"),
             explanation: String(localized: "Mail'in zarf veritabanını sıkıştırır; arama ve gelen kutusu hızlanır. Mail kapatılır, açıldığında kısa bir süre dizinler. CleanMac'in Tam Disk Erişimi olmalı."),
             symbol: "envelope.badge.shield.half.filled", needsAdmin: false,
             command: "osascript -e 'tell application \"Mail\" to quit' 2>/dev/null; sleep 2; found=0; for f in ~/Library/Mail/V*/MailData/'Envelope Index'; do [ -f \"$f\" ] || continue; found=1; /usr/bin/sqlite3 \"$f\" vacuum || exit 1; done; [ $found = 1 ] || { echo 'Mail veritabanı okunamadı (Tam Disk Erişimi gerekli ya da Mail hiç kurulmamış)'; exit 1; }"),
        Task(id: "fonts", title: String(localized: "Yazı tipi önbelleğini sıfırla"),
             explanation: String(localized: "Yazı tipleri bozuk ya da üst üste görünüyorsa. Oturumu kapatıp açınca yeniden oluşur."),
             symbol: "textformat", needsAdmin: false,
             command: "atsutil databases -removeUser"),
        Task(id: "snapshots", title: String(localized: "Yerel Time Machine anlık görüntülerini incelt"),
             explanation: String(localized: "Time Machine'in bu Mac'te tuttuğu yerel kopyalar \"Sistem Verileri\"nde yer kaplar. Yedek diskindeki yedeklere dokunmaz."),
             symbol: "clock.arrow.circlepath", needsAdmin: true,
             command: "tmutil thinlocalsnapshots / 999999999999 4"),
    ]

    /// Tasks worth running now: Quick Look always (harmless), snapshot thinning when local snapshots exist.
    public static func recommendations() async -> [Task] {
        var ids = ["quicklook"]
        let snapshots = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output
        if snapshots.contains("com.apple.TimeMachine") { ids.append("snapshots") }
        return tasks.filter { ids.contains($0.id) }
    }

    public struct Outcome: Sendable {
        public let task: Task
        public let ok: Bool
        public let message: String
    }

    public static func run(_ task: Task) async -> Outcome {
        let result = await runCommand(task.command, admin: task.needsAdmin)
        let message = result.status == 0 ? String(localized: "Tamamlandı")
            : Shell.wasCancelled(result) ? String(localized: "İptal edildi")
            : result.status == -2 ? String(localized: "Süre doldu; arka planda bitmiş olabilir, sonucu kontrol et")
            : String(localized: "Olmadı: \(result.output.prefix(160))")
        return Outcome(task: task, ok: result.status == 0, message: message)
    }

    static func runCommand(_ command: String, admin: Bool) async -> Shell.Result {
        guard admin else { return await Shell.run("/bin/zsh", ["-c", command], timeout: Shell.actionTimeout) }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return await Shell.run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"], timeout: Shell.actionTimeout)
    }
}
