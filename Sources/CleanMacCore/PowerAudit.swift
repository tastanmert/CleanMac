import Foundation

/// Energy and performance check-up: reads power settings, sleep blockers, battery health,
/// energy-hungry apps and background helpers, then turns them into findings with an optional fix.
/// Nothing changes without the user pressing a button; admin fixes ask for the password in macOS's own dialog.
public enum PowerAudit {
    public enum Severity: Int, Sendable, Codable, Comparable {
        case info, suggestion, warning
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Fix: Sendable, Hashable {
        /// Runs with administrator privileges; `undo` reverses it.
        case admin(command: String, undo: String)
        /// Stops a user launch agent and keeps it from starting again (reversible).
        case disableAgent(label: String, plist: URL)
        /// Ends processes nobody owns any more.
        case kill(pids: [Int32])
        /// A command the user runs in Terminal themselves; shown for copying.
        case copy(command: String)
        case openSettings(URL)
    }

    public struct Finding: Identifiable, Sendable, Hashable {
        public let id: String
        public let title: String
        public let detail: String
        public let severity: Severity
        public let fix: Fix?
    }

    // MARK: - Readings

    public struct Assertion: Sendable, Hashable {
        public let pid: Int32
        public let process: String
        public let type: String
        public let forever: Bool
        public let age: TimeInterval
    }

    public struct Battery: Sendable, Hashable {
        public var onBattery = false
        public var percent = 0
        public var cycles = 0
        public var maxCapacity = 100
    }

    public struct Usage: Sendable, Hashable {
        public let pid: Int32
        public let command: String
        public let power: Double
    }

    public struct Process: Sendable, Hashable {
        public let pid: Int32
        public let ppid: Int32
        public let rssKB: Int
        public let command: String
    }

    public struct Readings: Sendable {
        /// `pmset -g custom`: settings per power source.
        public var battery: [String: String] = [:]
        public var ac: [String: String] = [:]
        public var assertions: [Assertion] = []
        public var power = Battery()
        public var usage: [Usage] = []
        public var darkWakes24h = 0
        public var swapUsedMB = 0
        public var processes: [Process] = []
        public var agents: [StartupItems.Item] = []
        public var reduceTransparency = false
    }

    public static func read(now: Date = .now) async -> Readings {
        async let custom = Shell.run("/usr/bin/pmset", ["-g", "custom"]).output
        async let assertions = Shell.run("/usr/bin/pmset", ["-g", "assertions"]).output
        async let batt = Shell.run("/usr/bin/pmset", ["-g", "batt"]).output
        async let profile = Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType"]).output
        async let top = Shell.run("/usr/bin/top", ["-l", "2", "-s", "1", "-o", "power", "-n", "12", "-stats", "pid,command,power"]).output
        async let wakes = Shell.run("/bin/zsh", ["-c", "/usr/bin/pmset -g log | /usr/bin/grep DarkWake | /usr/bin/tail -2000"]).output
        async let swap = Shell.run("/usr/sbin/sysctl", ["-n", "vm.swapusage"]).output
        async let ps = Shell.run("/bin/ps", ["-Ao", "pid=,ppid=,rss=,command="]).output
        async let transparency = Shell.run("/usr/bin/defaults", ["read", "com.apple.universalaccess", "reduceTransparency"]).output
        async let agents = StartupItems.list()

        var r = Readings()
        (r.battery, r.ac) = parseCustom(await custom)
        r.assertions = parseAssertions(await assertions)
        r.power = parseBattery(batt: await batt, profile: await profile)
        r.usage = parseTop(await top)
        r.darkWakes24h = countDarkWakes(await wakes, since: now.addingTimeInterval(-86_400))
        r.swapUsedMB = parseSwapUsed(await swap)
        r.processes = parseProcesses(await ps)
        r.reduceTransparency = (await transparency).trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        r.agents = await agents
        return r
    }

    // MARK: - Parsers

    static func parseCustom(_ output: String) -> (battery: [String: String], ac: [String: String]) {
        var battery: [String: String] = [:], ac: [String: String] = [:]
        var inBattery: Bool?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("Battery Power") { inBattery = true; continue }
            if line.hasPrefix("AC Power") { inBattery = false; continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let inBattery, parts.count >= 2 else { continue }
            let key = parts.dropLast().joined(separator: " "), value = String(parts.last!)
            if inBattery { battery[key] = value } else { ac[key] = value }
        }
        return (battery, ac)
    }

    /// Lines like `pid 4544(caffeinate): [0x…] 71:45:08 PreventUserIdleSystemSleep named: "…"`,
    /// optionally followed by `Details: caffeinate asserting forever`.
    static func parseAssertions(_ output: String) -> [Assertion] {
        let lines = output.split(separator: "\n").map(String.init)
        var result: [Assertion] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("pid "),
                  let open = trimmed.firstIndex(of: "("), let close = trimmed.firstIndex(of: ")"),
                  let pid = Int32(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<open]) else { continue }
            let process = String(trimmed[trimmed.index(after: open)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
                .split(separator: " ").filter { !$0.hasPrefix("[") && $0 != ":" && !$0.hasPrefix(":") }
            guard rest.count >= 2 else { continue }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            result.append(Assertion(pid: pid, process: process, type: String(rest[1]),
                                    forever: next.contains("asserting forever"), age: duration(String(rest[0]))))
        }
        return result
    }

    static func duration(_ text: String) -> TimeInterval {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    static func parseBattery(batt: String, profile: String) -> Battery {
        var b = Battery()
        b.onBattery = batt.contains("'Battery Power'")
        if let match = batt.firstMatch(of: /(\d+)%;/) { b.percent = Int(match.1) ?? 0 }
        if let match = profile.firstMatch(of: /Cycle Count: (\d+)/) { b.cycles = Int(match.1) ?? 0 }
        if let match = profile.firstMatch(of: /Maximum Capacity: %?(\d+)%?/) { b.maxCapacity = Int(match.1) ?? 100 }
        return b
    }

    /// `top -l 2` prints two samples; the first has no CPU history, so only the last one counts.
    static func parseTop(_ output: String) -> [Usage] {
        guard let range = output.range(of: "PID", options: .backwards) else { return [] }
        return output[range.lowerBound...].split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let power = Double(parts.last!) else { return nil }
            return Usage(pid: pid, command: parts.dropFirst().dropLast().joined(separator: " "), power: power)
        }
    }

    static func countDarkWakes(_ output: String, since: Date) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return output.split(separator: "\n").filter { line in
            guard line.contains("DarkWake"), line.count > 25,
                  let date = formatter.date(from: String(line.prefix(25))) else { return false }
            return date >= since
        }.count
    }

    /// `total = 2048.00M  used = 627.69M  free = 1420.31M  (encrypted)`
    static func parseSwapUsed(_ output: String) -> Int {
        guard let match = output.firstMatch(of: /used = ([\d.]+)([MG])/), let value = Double(match.1) else { return 0 }
        return Int(match.2 == "G" ? value * 1024 : value)
    }

    static func parseProcesses(_ output: String) -> [Process] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]), let rss = Int(parts[2]) else { return nil }
            return Process(pid: pid, ppid: ppid, rssKB: rss, command: String(parts[3]))
        }
    }

    // MARK: - Rules

    /// MCP helper servers started by AI tools (`npm exec …mcp…`, `mcp-…-server`).
    static func isMCPHelper(_ command: String) -> Bool {
        let c = command.lowercased()
        return (c.hasPrefix("npm exec") || c.hasPrefix("node ")) && (c.contains("mcp") || c.contains("modelcontextprotocol") || c.contains("desktop-commander"))
    }

    static let updaterAgents = ["keystone", "googleupdater", "zoom.updater", "canva", "microsoft.update", "autoupdate"]
    static let systemProcesses: Set<String> = ["WindowServer", "kernel_task", "top", "launchd"]

    public static func findings(_ r: Readings) -> [Finding] {
        var out: [Finding] = []

        // Sleep blockers
        for a in r.assertions where a.process == "caffeinate" && a.forever && a.type == "PreventUserIdleDisplaySleep" {
            out.append(Finding(
                id: "caffeinate-display", title: String(localized: "caffeinate ekranın da uyumasını engelliyor"),
                detail: String(localized: "\(hours(a.age)) saattir süresiz çalışıyor (-d). Mac'i uyanık tutmak yeterliyse yalnız -i kullan: sistem çalışır, ekran kapanabilir."),
                severity: .suggestion,
                fix: .copy(command: "pkill -x caffeinate; nohup caffeinate -i >/dev/null 2>&1 &")))
            break
        }
        let blockers = r.assertions.filter {
            $0.process != "caffeinate" && $0.process != "powerd" && $0.process != "WindowServer"
                && $0.type.contains("Sleep") && $0.age > 3_600
        }
        for name in Set(blockers.map(\.process)).sorted() {
            out.append(Finding(id: "blocker-\(name)", title: String(localized: "\(name) Mac'in uyumasını engelliyor"),
                               detail: String(localized: "Bir saatten uzun süredir uyku engeli tutuyor. Kullanmıyorsan uygulamadan çık."),
                               severity: .info, fix: nil))
        }

        // Power settings
        if r.battery["lowpowermode"] == "0" {
            out.append(Finding(id: "lowpower-battery", title: String(localized: "Pilde Düşük Güç Modu kapalı"),
                               detail: String(localized: "Yalnız pildeyken açılır; prizde performans aynı kalır. Pil süresini belirgin uzatır."),
                               severity: .suggestion,
                               fix: .admin(command: "pmset -b lowpowermode 1", undo: "pmset -b lowpowermode 0")))
        }
        if r.battery["powernap"] == "1" {
            out.append(Finding(id: "powernap-battery", title: String(localized: "Pilde Power Nap açık"),
                               detail: String(localized: "Uykudayken pilde arka plan işleri için uyanır."),
                               severity: .suggestion,
                               fix: .admin(command: "pmset -b powernap 0", undo: "pmset -b powernap 1")))
        }
        if r.ac["womp"] == "1" || r.battery["womp"] == "1" {
            let many = r.darkWakes24h >= 100
            out.append(Finding(id: "womp", title: String(localized: "Ağ üzerinden uyandırma açık"),
                               detail: String(localized: "Son 24 saatte \(r.darkWakes24h) kez uykudan kısa uyanma oldu. Başka cihazdan bu Mac'e uzaktan erişmiyorsan kapat."),
                               severity: many ? .warning : .info,
                               fix: .admin(command: "pmset -a womp 0", undo: "pmset -a womp 1")))
        }

        // Battery
        if r.power.maxCapacity < 80 {
            out.append(Finding(id: "battery-health", title: String(localized: "Pil kapasitesi %\(r.power.maxCapacity)"),
                               detail: String(localized: "\(r.power.cycles) şarj döngüsü. %80 altında Apple servis önerir."),
                               severity: .warning, fix: .openSettings(batterySettings)))
        } else if !r.power.onBattery && r.power.percent >= 95 {
            out.append(Finding(id: "charge-limit", title: String(localized: "Çoğunlukla prizdeysen şarj sınırı koy"),
                               detail: String(localized: "Pil sağlığı %\(r.power.maxCapacity), \(r.power.cycles) döngü. Pil ayarlarında şarjı %80'de durdurmak pilin yaşlanmasını yavaşlatır."),
                               severity: .info, fix: .openSettings(batterySettings)))
        }

        // Memory
        if r.swapUsedMB >= 1_024 {
            out.append(Finding(id: "swap", title: String(localized: "Takas alanı \(r.swapUsedMB) MB"),
                               detail: String(localized: "Bellek yetmeyince diske yazılıyor; Mac yavaşlar ve pil daha çok harcanır. Ağır uygulamaları kapat ya da yeniden başlat."),
                               severity: .warning, fix: nil))
        }

        // Energy-hungry apps (last top sample)
        let hungry = r.usage.filter { $0.power >= 20 && !systemProcesses.contains($0.command) }
        if !hungry.isEmpty {
            let names = hungry.prefix(4).map { "\($0.command) (\(Int($0.power)))" }.joined(separator: ", ")
            out.append(Finding(id: "hungry", title: String(localized: "Çok enerji harcayan uygulamalar"),
                               detail: String(localized: "\(names). Kullanmadığın uygulamaların penceresini kapatmak ya da çıkmak pil süresini uzatır."),
                               severity: hungry.count >= 3 ? .warning : .suggestion, fix: nil))
        }

        // AI tool helpers
        let mcp = r.processes.filter { isMCPHelper($0.command) }
        let orphans = mcp.filter { $0.ppid == 1 }
        if !orphans.isEmpty {
            let mb = orphans.reduce(0) { $0 + $1.rssKB } / 1024
            out.append(Finding(id: "mcp-orphans", title: String(localized: "\(orphans.count) sahipsiz MCP süreci"),
                               detail: String(localized: "Kapanmış yapay zekâ oturumlarından kalmış, \(mb) MB bellek tutuyor."),
                               severity: .warning, fix: .kill(pids: orphans.map(\.pid))))
        }
        // Sessions that started helpers: parents that are not themselves helpers (npm exec → node is one helper).
        let helperPIDs = Set(mcp.map(\.pid))
        let owners = Set(mcp.filter { $0.ppid != 1 && !helperPIDs.contains($0.ppid) }.map(\.ppid))
        let mcpMB = mcp.reduce(0) { $0 + $1.rssKB } / 1024
        if mcpMB >= 1_024 {
            out.append(Finding(id: "mcp-sessions", title: String(localized: "Yapay zekâ yardımcıları \(mcpMB) MB kullanıyor"),
                               detail: String(localized: "\(mcp.count) MCP süreci, \(owners.count) ayrı oturum tarafından başlatılmış. Her açık oturum kendi kopyasını çalıştırır; kullanmadığın oturumları kapat ya da arşivle."),
                               severity: .suggestion, fix: nil))
        }

        // Background updaters
        for agent in r.agents where agent.isUserAgent && !agent.isDisabled
            && updaterAgents.contains(where: { agent.label.lowercased().contains($0) }) {
            out.append(Finding(id: "agent-\(agent.label)", title: String(localized: "Arka plan güncelleyicisi: \(agent.label)"),
                               detail: String(localized: "Düzenli olarak uyanır. Uygulama zaten kendi açılışında güncelleme yapıyorsa kapatılabilir."),
                               severity: .info, fix: .disableAgent(label: agent.label, plist: agent.plist)))
        }

        if !r.reduceTransparency {
            out.append(Finding(id: "transparency", title: String(localized: "Saydamlık efektleri açık"),
                               detail: String(localized: "Erişilebilirlik > Ekran > Saydamlığı azalt, WindowServer'ın grafik yükünü biraz azaltır. Görünüm tercihine bağlı."),
                               severity: .info,
                               fix: .openSettings(URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")!)))
        }

        return out.sorted { ($0.severity, $1.id) > ($1.severity, $0.id) }
    }

    static let batterySettings = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!

    static func hours(_ seconds: TimeInterval) -> Int { Int(seconds / 3_600) }

    /// 100 minus a penalty per finding.
    public static func score(_ findings: [Finding]) -> Int {
        let penalty = findings.reduce(0) { total, f in
            total + (f.severity == .warning ? 15 : f.severity == .suggestion ? 7 : 2)
        }
        return max(0, 100 - penalty)
    }

    // MARK: - Fixes

    public static func apply(_ fix: Fix) async -> Bool {
        switch fix {
        case .admin(let command, _):
            return await Maintenance.runCommand(command, admin: true).status == 0
        case .disableAgent(let label, let plist):
            let item = StartupItems.Item(label: label, program: "", plist: plist, isUserAgent: true, isDisabled: false, isRunning: true)
            return await StartupItems.setEnabled(false, item)
        case .kill(let pids):
            return pids.allSatisfy { Darwin.kill($0, SIGTERM) == 0 }
        case .copy, .openSettings:
            return true
        }
    }

    /// Reverses `apply` where that is possible.
    public static func undo(_ fix: Fix) async -> Bool {
        switch fix {
        case .admin(_, let undo):
            return await Maintenance.runCommand(undo, admin: true).status == 0
        case .disableAgent(let label, let plist):
            let item = StartupItems.Item(label: label, program: "", plist: plist, isUserAgent: true, isDisabled: true, isRunning: false)
            return await StartupItems.setEnabled(true, item)
        case .kill, .copy, .openSettings:
            return false
        }
    }

    // MARK: - History

    public struct Snapshot: Codable, Sendable, Hashable {
        public let date: Date
        public let score: Int
        public let swapUsedMB: Int
        public let darkWakes24h: Int
        public let findingIDs: [String]

        public init(date: Date, score: Int, swapUsedMB: Int, darkWakes24h: Int, findingIDs: [String]) {
            (self.date, self.score, self.swapUsedMB, self.darkWakes24h, self.findingIDs) = (date, score, swapUsedMB, darkWakes24h, findingIDs)
        }
    }

    public static let historyFolder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CleanMac/power")

    public static func save(_ snapshot: Snapshot, in folder: URL = historyFolder) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = snapshot.date.formatted(.iso8601.year().month().day()) + ".json"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(snapshot).write(to: folder.appending(path: name))
    }

    /// Newest first.
    public static func history(in folder: URL = historyFolder, limit: Int = 10) -> [Snapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Snapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
            .prefix(limit).map { $0 }
    }

    // MARK: - Weekly reminder

    static let reminderLabel = "com.cleanmac.power-reminder"
    static var reminderPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(reminderLabel).plist")
    }

    public static var isReminderOn: Bool { FileManager.default.fileExists(atPath: reminderPlist.path) }

    /// Every Sunday at 20:00, a notification if the last check-up is older than six days. It only notifies; it never fixes.
    static func reminderScript(folder: URL) -> String {
        """
        f=$(/bin/ls -t "\(folder.path)"/*.json 2>/dev/null | /usr/bin/head -1); \
        if [ -z "$f" ] || [ $(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$f") )) -gt 518400 ]; then \
        /usr/bin/osascript -e 'display notification "Enerji ve performans taraması bir haftadır yapılmadı." with title "CleanMac"'; fi
        """
    }

    public static func setReminder(_ on: Bool) async -> Bool {
        let domain = "gui/\(getuid())"
        if on {
            let plist: [String: Any] = [
                "Label": reminderLabel,
                "ProgramArguments": ["/bin/zsh", "-c", reminderScript(folder: historyFolder)],
                "StartCalendarInterval": ["Weekday": 0, "Hour": 20, "Minute": 0],
            ]
            try? FileManager.default.createDirectory(at: reminderPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (plist as NSDictionary).write(to: reminderPlist, atomically: true) else { return false }
            return await Shell.run("/bin/launchctl", ["bootstrap", domain, reminderPlist.path]).status == 0
        } else {
            _ = await Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(reminderLabel)"])
            return (try? FileManager.default.removeItem(at: reminderPlist)) != nil
        }
    }

    /// Appends a line to the action log so every change can be traced and undone by hand.
    public static func log(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CleanMac/power-actions.log")
        let entry = "\(Date.now.formatted(.iso8601)) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(entry.utf8).write(to: url)
        }
    }
}
