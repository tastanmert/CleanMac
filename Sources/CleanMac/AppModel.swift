import AppKit
import Observation
import Synchronization
import CleanMacCore

@Observable
final class AppModel {
    enum Phase {
        case idle
        case scanning
        case results
        case reviewing
        case cleaning
        case done(CleanReport)
    }

    /// The module shown in the sidebar.
    var module: Module = .smart
    /// Tool modules whose content was opened from their landing page.
    var openedTools: Set<Module> = []

    /// The one cleaning session; it belongs to `sessionModule`.
    var sessionModule: Module = .smart
    var phase: Phase = .idle
    var results: [CategoryResult] = []
    var reviewCategory: CleanMacCore.Category?
    var progress: Double = 0
    var showConfirm = false
    var disk = DiskSpace.current()
    let livePath = LivePath()

    let spaceMap = SpaceMapModel()
    let uninstaller = UninstallerModel()
    let duplicates = DuplicatesModel()
    let similarImages = SimilarImagesModel()
    let updater = UpdaterModel()
    let selfUpdate = SelfUpdateModel()
    let largeFiles = RuleItemsModel(ruleID: "largeFiles")
    let oldDownloads = RuleItemsModel(ruleID: "oldDownloads")
    let orphans = RuleItemsModel(ruleID: "orphans")
    let installers = RuleItemsModel(ruleID: "installers")
    let startup = StartupModel()
    let maintenance = MaintenanceModel()
    let power = PowerModel()
    let trash = TrashModel()

    private var task: Task<Void, Never>?
    private var scanRules: [CleanRule] = []

    // MARK: Derived state

    var isBusy: Bool {
        switch phase {
        case .scanning, .cleaning: true
        default: false
        }
    }

    /// The phase to show for `module`: the session's when it is this module's, otherwise idle.
    var phaseForCurrentModule: Phase { sessionModule == module ? phase : .idle }

    /// Sidebar shrinks to icons while the current module is working, as a focus cue.
    var isFocused: Bool {
        guard sessionModule == module else { return false }
        switch phase {
        case .scanning, .cleaning: return true
        // A smart scan keeps the narrow sidebar through its results and review, like a focused task.
        case .results, .reviewing: return module == .smart
        default: return false
        }
    }

    /// A tab a tool card asked for; the module's tab bar picks it up once when it appears.
    var requestedTab: Int?
    func takeRequestedTab() -> Int? {
        defer { requestedTab = nil }
        return requestedTab
    }

    /// Opens a tool module straight at one of its tabs.
    func open(_ module: Module, tab: Int? = nil) {
        requestedTab = tab
        openedTools.insert(module)
        self.module = module
    }

    /// The manager opened from a smart scan card ("İncele"), shown over the results.
    var smartManager: Module?

    var foundSize: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { results.reduce(0) { $0 + $1.selectedSize } }
    var selectedItems: [CleanItem] { results.flatMap { $0.items.filter(\.isSelected) } }
    var selectedCount: Int { results.reduce(0) { $0 + $1.items.filter(\.isSelected).count } }

    /// Non-empty categories in display order, with their rules.
    var resultCategories: [(category: CleanMacCore.Category, results: [CategoryResult])] {
        CleanMacCore.Category.allCases.compactMap { category in
            let rs = results.filter { $0.rule.category == category && !$0.items.isEmpty }
            return rs.isEmpty ? nil : (category, rs)
        }
    }

    func size(of category: CleanMacCore.Category) -> Int64 {
        results.filter { $0.rule.category == category }.reduce(0) { $0 + $1.totalSize }
    }

    func selectedSize(of category: CleanMacCore.Category) -> Int64 {
        results.filter { $0.rule.category == category }.reduce(0) { $0 + $1.selectedSize }
    }

    var pendingRules: [String] {
        let done = Set(results.map(\.rule.id))
        return scanRules.filter { !done.contains($0.id) }.map(\.title)
    }

    // MARK: Navigation

    func select(_ module: Module) {
        guard module != self.module else { return }
        self.module = module
    }

    /// The landing page's main button.
    func start() {
        if module.categories != nil {
            scan()
        } else {
            openedTools.insert(module)
        }
    }

    // MARK: Scan

    /// ⌘R and the menu bar: findings still on screen are not thrown away without asking.
    func requestScan() {
        switch phase {
        case .results, .reviewing: showResetConfirm = true
        default: scan()
        }
    }

    func scan() {
        if case .scanning = phase, sessionModule != module, module.categories != nil {
            showSwitchScanConfirm = true
            return
        }
        guard !isBusy, let categories = module.categories else { return }
        scanGeneration += 1
        let generation = scanGeneration
        sessionModule = module
        smartManager = nil
        reviewGroupScope = nil
        results = []
        progress = 0
        reviewCategory = nil
        recommendedTasks = []
        selectedTasks = []
        unusedApps = []
        smartUpdates = []
        trashBins = []
        startupCount = 0
        phase = .scanning
        // A smart scan stays on quick, safe ground: its clutter card is only copies in Downloads.
        let rules = CleanRule.catalog.filter {
            categories.contains($0.category) && !(module == .smart && Self.smartSkippedRules.contains($0.id))
        }
        scanRules = rules
        let scanner = Scanner(runningApps: Cleaner.runningApps())
        let livePath = livePath
        let groups = scanGroups

        // Utility priority: the disk walkers must never compete with the frames being drawn.
        task = Task(priority: .utility) {
            // Groups run one after another so the card grid can show each one working in turn.
            for group in groups {
                activeGroup = group
                livePath.set("")   // the previous group's last path would otherwise linger
                let started = ContinuousClock.now
                let groupCategories = self.categories(of: group)
                let groupRules = rules.filter { groupCategories.contains($0.category) }
                await Scanner.$pathReporter.withValue({ livePath.set($0) }) {
                    await scanner.scan(groupRules) { result in
                        await self.receive(result, total: rules.count, generation: generation)
                    }
                }
                // A stopped scan's rules can still be finishing: none of it may reach a newer session.
                guard generation == scanGeneration, !Task.isCancelled else { return }
                if sessionModule == .smart { await scanExtras(for: group, generation: generation) }
                // The Trash bins are shown with the cleanup; emptying them stays on the Trash screen.
                if group == .junk {
                    let bins = await Task.detached { TrashBins.list() }.value
                    guard generation == scanGeneration else { return }
                    trashBins = bins
                }
                guard generation == scanGeneration else { return }
                // Keep each card on stage long enough to read, even when the disk is quick. The big
                // junk sweep gets the longest stage, like a check-up that visibly works through its list.
                let stage = groups.count > 1 ? (group == .junk ? 2800 : 2000) : 2500
                try? await Task.sleep(until: started + .milliseconds(stage))
                if Task.isCancelled { return }
            }
            activeGroup = nil
            if sessionModule == .smart { UserDefaults.standard.set(Date.now, forKey: "lastSmartScan") }
            results.sort { lhs, rhs in
                (rules.firstIndex { $0.id == lhs.rule.id } ?? 0) < (rules.firstIndex { $0.id == rhs.rule.id } ?? 0)
            }
            phase = .results
            Sounds.shared.play(.scanDone)
        }
    }

    /// Rules a smart scan leaves to their own module (big files and audio plug-ins need a closer look).
    static let smartSkippedRules: Set<String> = ["largeFiles", "oldDownloads", "audioPlugins"]

    /// Smart scan works through every module, like a check-up; other modules are a single group.
    var scanGroups: [Module] { sessionModule == .smart ? [.junk, .protection, .performance, .applications, .clutter] : [sessionModule] }

    /// The cleaning categories a group covers in this session. In a smart scan "Temizlik" takes in
    /// AI and developer junk too, and Applications and Clutter get their own rule categories.
    func categories(of group: Module) -> [CleanMacCore.Category] {
        guard sessionModule == .smart else { return group.categories ?? [] }
        switch group {
        // Smart scan cleanup: system junk and mail attachments (AI clutter stays in its own tool).
        case .junk: return [.xcode, .appCaches, .logs, .broken, .mail]
        case .applications: return [.appLeftovers]
        case .clutter: return [.largeFiles]
        case .protection: return [.threats, .privacy]
        default: return []
        }
    }

    /// Smart scan findings that are not files: maintenance tasks worth running, apps nobody opens.
    var recommendedTasks: [Maintenance.Task] = []
    var selectedTasks: Set<String> = []
    var unusedApps: [Uninstaller.App] = []
    /// App updates found during a smart scan (the Applications card counts them).
    var smartUpdates: [Updater.Update] = []
    /// The Trash bins found with a cleanup scan; shown as a card that opens the Trash screen.
    var trashBins: [TrashBins.Bin] = []
    var trashSize: Int64 { trashBins.reduce(0) { $0 + $1.size } }
    /// Login and background items that are on (the smart scan's performance card counts them).
    var startupCount = 0

    private func scanExtras(for group: Module, generation: Int) async {
        switch group {
        case .performance:
            livePath.set(String(localized: "Bakım görevleri ve yerel anlık görüntüler denetleniyor"))
            let tasks = await Maintenance.recommendations()
            guard generation == scanGeneration else { return }
            recommendedTasks = tasks
            selectedTasks = Set(recommendedTasks.filter { !$0.needsAdmin }.map(\.id))
            let startup = await StartupItems.list().filter { !$0.isDisabled }.count
            guard generation == scanGeneration else { return }
            startupCount = startup
        case .applications:
            livePath.set(String(localized: "Uygulamalar ve güncellemeler denetleniyor"))
            // Running apps are in use whatever Spotlight says (menu bar tools, background helpers).
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            async let installed = Uninstaller().installedApps()
            async let updates = Updater.check()
            let unused = await installed.filter { $0.isUnused(runningBundleIDs: running) }
            let found = await updates
            guard generation == scanGeneration else { return }
            unusedApps = unused
            smartUpdates = found
        default:
            break
        }
    }

    var selectedTaskList: [Maintenance.Task] { recommendedTasks.filter { selectedTasks.contains($0.id) } }
    var hasWork: Bool { selectedSize > 0 || !selectedTasks.isEmpty }

    /// Big number and caption for a smart scan card.
    func cardSummary(_ group: Module) -> (value: String, caption: String) {
        let size = size(in: group)
        let count = results(in: group).reduce(0) { $0 + $1.items.count }
        switch group {
        case .junk:
            let selected = selectedSize(in: group)
            let trash = trashSize > 0 ? String(localized: " · Çöp'te \(trashSize.bytes)") : ""
            guard size > 0 else { return (String(localized: "Çöp yok"), String(localized: "her şey temiz") + trash) }
            return (String(localized: "\(size.bytes) çöp"), (selected < size ? String(localized: "\(selected.bytes) güvenle seçili") : "temizlenecek") + trash)
        case .protection:
            let threats = results.filter { $0.rule.category == .threats }.reduce(0) { $0 + $1.items.count }
            if threats > 0 { return (String(localized: "\(threats) şüpheli öğe"), count > threats ? String(localized: "ve \(count - threats) iz · gözden geçir") : String(localized: "gözden geçirilecek")) }
            return count > 0 ? (String(localized: "\(count) iz"), String(localized: "tehdit yok · izler gözden geçirilecek")) : (String(localized: "Tehdit yok"), String(localized: "gizlilik temiz"))
        case .performance:
            let n = recommendedTasks.count
            let startup = startupCount > 0 ? String(localized: "\(startupCount) başlangıç öğesi") : nil
            if n > 0 { return (String(localized: "\(n) görev"), ([String(localized: "çalıştırılacak")] + [startup].compactMap { $0 }).joined(separator: " · ")) }
            return startup.map { ($0, String(localized: "açılışta çalışıyor · gözden geçir")) } ?? (String(localized: "Her şey yolunda"), String(localized: "önerilen bakım yok"))
        case .applications:
            var notes: [String] = []
            if !smartUpdates.isEmpty { notes.append(String(localized: "\(smartUpdates.count) güncelleme")) }
            if !unusedApps.isEmpty { notes.append(String(localized: "\(unusedApps.count) kullanılmayan uygulama")) }
            if size > 0 {
                return (String(localized: "\(size.bytes) artık"), ([String(localized: "kaldırılacak")] + notes).joined(separator: " · "))
            }
            if !smartUpdates.isEmpty {
                return (String(localized: "\(smartUpdates.count) güncelleme"), notes.dropFirst().first ?? String(localized: "yüklenebilir"))
            }
            return unusedApps.isEmpty ? (String(localized: "Derli toplu"), String(localized: "artık dosya yok")) : (String(localized: "\(unusedApps.count) uygulama"), String(localized: "uzun süredir açılmamış"))
        case .clutter:
            return count > 0 ? (String(localized: "\(count) dosya"), String(localized: "\(size.bytes) · gözden geçirilecek")) : (String(localized: "Dağınıklık yok"), String(localized: "büyük ya da kopya dosya yok"))
        default:
            return size > 0 ? (size.bytes, String(localized: "temizlenebilir")) : (String(localized: "Temiz"), String(localized: "bir şey bulunmadı"))
        }
    }

    /// Whether a smart card has anything its checkbox could select.
    func isSelectable(_ group: Module) -> Bool {
        group == .performance ? !recommendedTasks.isEmpty : group != .clutter && hasBulkChoice(results(in: group))
    }

    /// A checkbox only where it can do something: some item it would tick, or a hand-picked one to untick.
    /// Review-only findings (privacy traces, leftovers) are picked one by one in their list instead.
    func hasBulkChoice(_ results: [CategoryResult]) -> Bool {
        results.contains { $0.items.contains { $0.isRecommended || $0.isSelected } }
    }

    /// The group being scanned right now (smart scan card grid).
    var activeGroup: Module?
    var showStopConfirm = false
    /// The glass dialog on screen, if any (see GlassDialog.swift).
    var dialog: GlassDialogModel?
    /// The Full Disk Access card (first launch, or from the "scan may be incomplete" banner).
    var showFDA = false
    /// A larger glass panel over the window (app permissions, Wi-Fi networks).
    enum Panel: Equatable {
        case permissions, wifi, log(String, [LogLine]), update
    }
    struct LogLine: Equatable, Identifiable {
        let id = UUID()
        let ok: Bool
        let title: String
        let note: String
    }
    var panel: Panel?
    /// A scan is running and another module's scan was asked for: ask before dropping the first.
    var showSwitchScanConfirm = false
    /// Start Over on a results page throws the findings away: ask first.
    var showResetConfirm = false
    /// Bumped by every new or stopped scan, so late results of an older one are dropped.
    private var scanGeneration = 0

    func results(in group: Module) -> [CategoryResult] {
        let categories = categories(of: group)
        return results.filter { categories.contains($0.rule.category) }
    }

    func checkState(of category: CleanMacCore.Category) -> CheckState {
        let items = results.filter { $0.rule.category == category }.flatMap(\.items)
        let selected = items.filter(\.isSelected).count
        return selected == 0 ? .off : selected == items.count ? .on : .mixed
    }

    func setSelected(_ on: Bool, category: CleanMacCore.Category) {
        select(on, where: { $0.category == category })
    }

    /// Turning on selects only items of safe rules whose app is closed; "review" items stay a manual choice in the rule's list.
    private func select(_ on: Bool, where matches: (CleanRule) -> Bool) {
        for r in results.indices where matches(results[r].rule) { results[r].select(on) }
    }

    func size(in group: Module) -> Int64 { results(in: group).reduce(0) { $0 + $1.totalSize } }
    func selectedSize(in group: Module) -> Int64 { results(in: group).reduce(0) { $0 + $1.selectedSize } }

    func isScanned(_ group: Module) -> Bool {
        guard let order = scanGroups.firstIndex(of: group) else { return false }
        if case .scanning = phase, let active = activeGroup, let current = scanGroups.firstIndex(of: active) {
            return order < current
        }
        return true
    }

    func checkState(of group: Module) -> CheckState {
        if group == .performance {
            return selectedTasks.isEmpty ? .off : selectedTasks.count == recommendedTasks.count ? .on : .mixed
        }
        let items = results(in: group).flatMap(\.items)
        let selected = items.filter(\.isSelected).count
        return selected == 0 ? .off : selected == items.count ? .on : .mixed
    }

    /// Turning a group on selects only the items its rules mark safe; "review" items stay a manual choice.
    func setSelected(_ on: Bool, group: Module) {
        if group == .performance {
            selectedTasks = on ? Set(recommendedTasks.map(\.id)) : []
            return
        }
        let categories = categories(of: group)
        select(on, where: { categories.contains($0.category) })
    }

    func stop() {
        // The scan may have finished while the confirmation was up: keep its results then.
        guard case .scanning = phase else { showStopConfirm = false; return }
        scanGeneration += 1
        task?.cancel()
        task = nil
        activeGroup = nil
        showStopConfirm = false
        phase = .idle
        results = []
    }

    private func receive(_ result: CategoryResult, total: Int, generation: Int) {
        guard case .scanning = phase, generation == scanGeneration else { return }
        results.append(result)
        progress = Double(results.count) / Double(total)
    }

    // MARK: Review & selection

    func review(_ category: CleanMacCore.Category? = nil, group: Module? = nil) {
        reviewGroupScope = group
        reviewCategory = category ?? reviewCategories.first?.category
        phase = .reviewing
    }

    /// The smart card the review was opened from; the manager then lists only that card's categories.
    var reviewGroupScope: Module?

    var reviewCategories: [(category: CleanMacCore.Category, results: [CategoryResult])] {
        guard let group = reviewGroupScope else { return resultCategories }
        let allowed = categories(of: group)
        return resultCategories.filter { allowed.contains($0.category) }
    }

    var reviewTitle: String {
        switch reviewGroupScope {
        case .junk?: String(localized: "Temizlik Yöneticisi")
        case .protection?: String(localized: "Koruma Yöneticisi")
        default: String(localized: "İnceleme")
        }
    }

    func backToSummary() { phase = .results }

    /// A smart scan card's "İncele": file groups open the review manager, performance opens its module.
    func reviewGroup(_ group: Module) {
        // Cleanup and protection items are reviewed in the three-column manager; the other groups open
        // their own module's manager over the results, and Back returns here.
        if group == .junk || group == .protection {
            // Nothing found: there is no list to open (an empty manager would only say "Yönetici" over a blank page).
            if let category = categories(of: group).first(where: { size(of: $0) > 0 }) { review(category, group: group) }
        } else {
            // Open at the tab the card is about: leftovers when some were found.
            requestedTab = switch group {
            case .applications: size(in: .applications) > 0 ? 1 : !smartUpdates.isEmpty ? 3 : nil
            case .performance: recommendedTasks.isEmpty && startupCount > 0 ? 1 : nil
            default: nil
            }
            smartManager = group
        }
    }

    func setSelected(_ selected: Bool, item: CleanItem, in ruleID: String) {
        guard let r = results.firstIndex(where: { $0.rule.id == ruleID }),
              let i = results[r].items.firstIndex(where: { $0.id == item.id }) else { return }
        results[r].items[i].isSelected = selected
    }

    /// Already added to the ignore list by the row; just drop it from these results.
    func ignore(_ item: CleanItem, in ruleID: String) {
        guard let r = results.firstIndex(where: { $0.rule.id == ruleID }) else { return }
        results[r].items.removeAll { $0.id == item.id }
    }

    /// Ticks what is safe to remove right now: every item of a "safe" rule, minus caches of apps that are open.
    func applySmartSelection(in ruleID: String) {
        guard let r = results.firstIndex(where: { $0.rule.id == ruleID }) else { return }
        results[r].select(true)
    }

    func setAllSelected(_ selected: Bool, in ruleID: String) {
        guard let r = results.firstIndex(where: { $0.rule.id == ruleID }) else { return }
        // "Select all" is a manual choice, but an open app's cache still waits until the app is closed.
        for i in results[r].items.indices { results[r].items[i].isSelected = selected && !results[r].items[i].appIsOpen }
    }

    // MARK: Clean

    func clean() {
        let items = selectedItems
        let tasks = selectedTaskList
        guard !items.isEmpty || !tasks.isEmpty, !isBusy else { return }
        showConfirm = false
        progress = 0
        phase = .cleaning
        task = Task {
            var report = await Cleaner.live().clean(items, source: sessionModule.title) { value in
                await MainActor.run { self.progress = value }
            }
            for task in tasks {
                if Task.isCancelled { report.skippedCount += 1; report.entries.append((false, task.title, String(localized: "durduruldu, çalıştırılmadı"))); continue }
                let outcome = await Maintenance.run(task)
                if outcome.ok {
                    report.cleanedCount += 1
                    report.entries.append((true, task.title, String(localized: "çalıştırıldı")))
                } else {
                    report.failures.append(.init(title: task.title, reason: outcome.message))
                    report.entries.append((false, task.title, outcome.message))
                }
            }
            selectedTasks = []
            disk = DiskSpace.current()
            results = []   // sizes are stale now; the next scan refills them
            phase = .done(report)
            Sounds.shared.play(report.failures.isEmpty ? .cleanDone : .failed)
        }
    }

    /// Stops a running cleanup between items; what was already moved stays moved.
    func stopCleaning() {
        showStopConfirm = false
        task?.cancel()
    }

    func reset() {
        smartManager = nil
        phase = .idle
        results = []
        disk = DiskSpace.current()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// "Güncellemeleri Denetle…": the update panel opens at once and shows what the check finds.
    func checkForUpdates() {
        panel = .update
        Task { await selfUpdate.check() }
    }

    func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
    }
}

extension Cleaner {
    /// Bundle ids and names of the apps open right now (CleanMac itself aside).
    static func runningApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.flatMap { [$0.bundleIdentifier, $0.localizedName].compactMap(\.self) }
            .filter { $0 != Bundle.main.bundleIdentifier })
    }

    /// A cleaner that re-checks, item by item, whether an app was opened since the scan.
    static func live() -> Cleaner { Cleaner(runningApps: runningApps()) }
}

/// The path a scan is looking at right now; written from scan threads, read by a timeline view.
nonisolated final class LivePath: Sendable {
    private let value = Mutex("")
    func set(_ path: String) { value.withLock { $0 = path } }
    var current: String { value.withLock { $0 } }
}

struct DiskSpace {
    var total: Int64
    var available: Int64
    var name = "Macintosh HD"
    /// Space macOS frees by itself when it needs room (iCloud copies, caches, local snapshots).
    var purgeable: Int64 = 0
    var used: Int64 { total - available }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskSpace {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey])
        // The startup disk's own name ("Macintosh HD" by default, but users rename it).
        let name = (try? URL(filePath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? "Macintosh HD"
        return DiskSpace(total: Int64(values?.volumeTotalCapacity ?? 0),
                         available: values?.volumeAvailableCapacityForImportantUsage ?? 0,
                         name: name,
                         purgeable: max(0, (values?.volumeAvailableCapacityForImportantUsage ?? 0) - Int64(values?.volumeAvailableCapacity ?? 0)))
    }
}
