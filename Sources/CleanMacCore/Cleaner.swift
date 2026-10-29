import Foundation

public struct CleanReport: Sendable {
    public struct Failure: Sendable, Identifiable {
        public let id = UUID()
        public let title: String
        public let reason: String
        /// Where the item sits, when the user can finish the job by hand in Finder.
        public let revealURL: URL?
        public init(title: String, reason: String, revealURL: URL? = nil) {
            self.title = title
            self.reason = reason
            self.revealURL = revealURL
        }
    }

    /// Moved to the Trash: frees space once the Trash is emptied.
    public var trashedBytes: Int64 = 0
    /// Freed right away by tool commands and simulator deletion.
    public var freedBytes: Int64 = 0
    public var cleanedCount = 0
    /// Left untouched because the user stopped the cleanup.
    public var skippedCount = 0
    public var failures: [Failure] = []
    /// One line per item, in order, for the "Günlüğü göster" panel: (succeeded, title, what happened).
    public var entries: [(ok: Bool, title: String, note: String)] = []
}

public struct Cleaner: Sendable {
    public let guardian: SafetyGuard
    let logFolder: URL
    let trash: @Sendable (URL) throws -> Void
    /// Apps open at cleaning time (bundle ids and names): an app opened after the scan keeps its caches.
    let running: Scanner

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, runningApps: Set<String> = [],
                temporaryDirectory: URL = FileManager.default.temporaryDirectory, aiTempRoots: [String]? = nil,
                trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        guardian = SafetyGuard(home: home, temporaryDirectory: temporaryDirectory, aiTempRoots: aiTempRoots)
        logFolder = home.appending(path: "Library/Logs/CleanMac")
        self.trash = trash
        running = Scanner(home: home, runningApps: runningApps)
    }

    @concurrent
    /// `source` names the screen for the Activity history; nil (tests, internal use) records nothing.
    public func clean(_ items: [CleanItem], source: String? = nil,
                      progress: @Sendable @escaping (Double) async -> Void = { _ in }) async -> CleanReport {
        var report = CleanReport()
        var log: [String] = []

        // Root-owned items go to the Trash together, behind a single administrator prompt.
        let adminItems = items.filter { if case .adminTrash = $0.action { true } else { false } }
        if !adminItems.isEmpty {
            switch await adminTrash(adminItems) {
            case .success(let moved):
                for item in adminItems where !moved.contains(item) {
                    report.failures.append(.init(title: item.title, reason: String(localized: "Taşınamadı")))
                }
                for item in moved {
                    report.trashedBytes += item.size
                    report.cleanedCount += 1
                    report.entries.append((true, item.title, item.size.formatted(.byteCount(style: .file))))
                    log.append("OK\t\(item.size)\t\(item.title)\t\(describe(item.action))")
                }
            case .failure(let error):
                for item in adminItems {
                    report.failures.append(.init(title: item.title, reason: String(describing: error)))
                    log.append("HATA\t\(item.title)\t\(describe(item.action))\t\(error)")
                }
            }
        }
        let items = items.filter { if case .adminTrash = $0.action { false } else { true } }

        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                report.skippedCount = items.count - index
                log.append(String(localized: "DURDURULDU\t\(report.skippedCount) öğe temizlenmedi"))
                break
            }
            do {
                let freed = try await perform(item)
                switch item.action {
                case .trash, .trashContents: report.trashedBytes += freed
                default: report.freedBytes += freed
                }
                report.cleanedCount += 1
                report.entries.append((true, item.title, freed > 0 ? Int64(freed).formatted(.byteCount(style: .file)) : String(localized: "tamam")))
                log.append("OK\t\(freed)\t\(item.title)\t\(describe(item.action))")
            } catch {
                let (reason, reveal) = Self.explain(error, for: item)
                report.failures.append(.init(title: item.title, reason: reason, revealURL: reveal))
                report.entries.append((false, item.title, reason))
                log.append("HATA\t\(item.title)\t\(describe(item.action))\t\(error)")
            }
            await progress(Double(index + 1) / Double(items.count))
        }
        writeLog(log)
        if let source {
            ActivityLog.record(.init(date: .now, source: source, bytes: report.trashedBytes + report.freedBytes,
                                     count: report.cleanedCount), home: guardian.home)
        }
        return report
    }

    /// A reason the user can act on. macOS refuses some removals (App Store apps, protected files, files in use):
    /// those come with the item's location so it can be finished by hand in Finder.
    static func explain(_ error: any Error, for item: CleanItem) -> (String, URL?) {
        let url: URL? = { if case .trash(let url) = item.action { url } else { nil } }()
        let ns = error as NSError
        let denied = (ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(ns.code))
        guard denied, let url else { return (String(describing: error), nil) }
        if item.policy == .application, FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt").path) {
            return (String(localized: "App Store uygulaması: macOS kısıtları yüzünden buradan kaldırılamadı. Finder'da gösterip elle Çöp'e taşı."), url)
        }
        return (String(localized: "macOS izin vermedi (dosya kullanımda ya da korumalı olabilir). Finder'da gösterip elle Çöp'e taşı."), url)
    }

    enum CleanError: Error, CustomStringConvertible {
        case commandFailed(String)
        case appOpened
        case usedSinceScan
        var description: String {
            switch self {
            case .appOpened: return String(localized: "Uygulama şimdi açık; kapatınca yeniden tara")
            case .usedSinceScan: return String(localized: "Taramadan sonra kullanıldı, atlandı")
            case .commandFailed(let output):
                // Strip terminal escape codes (colors, cursor moves) that tools like ollama print.
                let plain = output.replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return String(localized: "Komut başarısız: \(plain.prefix(200))")
            }
        }
    }

    /// The scan's verdict can go stale while results sit on screen: re-ask what may have changed since.
    func checkStillIdle(_ item: CleanItem, at url: URL) throws(CleanError) {
        switch item.policy {
        case .junk, .appSupportCache, .containerCache, .darwinCache, .tempFile:
            if Self.ownerNames(of: url, policy: item.policy).contains(where: running.belongsToRunningApp) { throw .appOpened }
        default:
            break
        }
        // Temporary folders judged idle by their newest file: anything written after the scan means it is in use.
        if item.policy == .tempFile || item.policy == .aiTemp, let scanned = item.date,
           let newest = Scanner.newestModification(in: url, stopAfter: scanned.addingTimeInterval(1)),
           newest > scanned.addingTimeInterval(1) {
            throw .usedSinceScan
        }
    }

    /// Folder names that can tie an item to an app: its own name, the app folder above a cache, a container's id.
    static func ownerNames(of url: URL, policy: SafetyGuard.Policy) -> [String] {
        switch policy {
        case .appSupportCache: return [url.deletingLastPathComponent().lastPathComponent]
        case .containerCache:
            // …/Containers/<id>/Data/Library/Caches or …/Group Containers/<TEAM.id>/Library/Caches
            let parts = url.pathComponents
            guard let i = parts.lastIndex(where: { $0 == "Containers" || $0 == "Group Containers" }), i + 1 < parts.count else { return [] }
            let id = parts[i + 1].lowercased()
            let team = id.split(separator: ".").first.map(String.init) ?? ""
            return team.count == 10 ? [id, String(id.dropFirst(team.count + 1))] : [id]
        default: return [url.lastPathComponent]
        }
    }

    func perform(_ item: CleanItem) async throws -> Int64 {
        switch item.action {
        case .trash(let url):
            let safe = try guardian.validate(url, policy: item.policy)   // checked again right before moving
            try checkStillIdle(item, at: safe)
            try trash(safe)
            if item.policy == .privacy {
                for sidecar in Privacy.sidecars(of: safe) { try? trash(guardian.validate(sidecar, policy: .privacy)) }
            }
            return item.size

        case .shell(let command, let measure):
            let before = measure.map(Scanner.allocatedSize(of:))
            let result = await Shell.login(command, timeout: Shell.actionTimeout)
            guard result.status == 0 else { throw CleanError.commandFailed(result.output) }
            guard let measure, let before else { return item.size }
            return max(0, before - Scanner.allocatedSize(of: measure))

        case .deleteSimulator(let udid):
            let result = await Shell.run("/usr/bin/xcrun", ["simctl", "delete", udid], timeout: Shell.actionTimeout)
            guard result.status == 0 else { throw CleanError.commandFailed(result.output) }
            return item.size

        case .trashContents(let folder):
            try checkStillIdle(item, at: folder)
            let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var moved = 0
            var lastError: (any Error)?
            for child in contents {
                do {
                    try trash(try guardian.validate(child, policy: item.policy))
                    moved += 1
                } catch {
                    lastError = error   // a file in use stays; the rest still goes
                }
            }
            if moved == 0, let lastError { throw lastError }
            return contents.isEmpty ? 0 : item.size * Int64(moved) / Int64(contents.count)

        case .adminTrash:
            return 0   // handled in one batch by `adminTrash(_:)`
        }
    }

    /// Moves root-owned items into a dated folder in the user's Trash with one administrator prompt,
    /// then hands that folder to the user so emptying the Trash needs no password.
    func adminTrash(_ items: [CleanItem]) async -> Result<[CleanItem], CleanError> {
        var valid: [(CleanItem, URL)] = []
        for item in items {
            guard case .adminTrash(let url) = item.action, [.systemAdmin, .launchItem].contains(item.policy),
                  let safe = try? guardian.validate(url, policy: item.policy) else { continue }
            valid.append((item, safe))
        }
        guard !valid.isEmpty else { return .failure(.commandFailed(String(localized: "Güvenlik denetiminden geçen öğe yok"))) }
        let destination = guardian.home.appending(path: ".Trash/CleanMac \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)))")
        var script = "/bin/mkdir -p \(Shell.quote(destination.path))"
        for (index, (_, url)) in valid.enumerated() {
            let target = destination.appending(path: "\(index + 1) \(url.lastPathComponent)")
            script += " ; /bin/mv \(Shell.quote(url.path)) \(Shell.quote(target.path))"
        }
        script += " ; /usr/sbin/chown -R \(getuid()) \(Shell.quote(destination.path))"
        let result = await Maintenance.runCommand(script, admin: true)
        if Shell.wasCancelled(result) { return .failure(.commandFailed(String(localized: "Parola penceresi iptal edildi"))) }
        // Each move is independent; whatever is gone from its place made it to the Trash.
        let moved = valid.filter { !FileManager.default.fileExists(atPath: $0.1.path) }.map(\.0)
        return moved.isEmpty ? .failure(.commandFailed(result.output)) : .success(moved)
    }

    func describe(_ action: CleanAction) -> String {
        switch action {
        case .trash(let url): "trash \(url.path)"
        case .shell(let command, _): "shell \(command)"
        case .deleteSimulator(let udid): "simctl delete \(udid)"
        case .trashContents(let url): "trash contents of \(url.path)"
        case .adminTrash(let url): "admin trash \(url.path)"
        }
    }

    func writeLog(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        try? FileManager.default.createDirectory(at: logFolder, withIntermediateDirectories: true)
        let file = logFolder.appending(path: "\(Date.now.formatted(.iso8601.year().month().day())).log")
        let text = "# \(Date.now.formatted(.iso8601))\n" + lines.joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: file)
        }
    }
}
