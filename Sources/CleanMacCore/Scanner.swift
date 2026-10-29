import Foundation

public struct Scanner: Sendable {
    /// Receives a path now and then while a scan walks the disk, for the live "scanning…" line.
    @TaskLocal public static var pathReporter: (@Sendable (String) -> Void)?

    public let home: URL
    public let guardian: SafetyGuard
    /// Bundle identifiers and names of apps that are open right now; their caches are left alone.
    public let runningApps: Set<String>
    let now: Date
    /// Injected in tests; nil asks Spotlight and the Applications folders.
    var installedBundleIDs: Set<String>?
    /// Injected in tests; nil checks /Applications, ~/Applications and the system launch folders.
    var threatFolders: (apps: [URL], launch: [(URL, Bool)])?

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, runningApps: Set<String> = [], now: Date = .now,
                temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                darwinCacheDirectory: URL = SafetyGuard.systemDarwinCacheDirectory, aiTempRoots: [String]? = nil) {
        self.home = home
        self.guardian = SafetyGuard(home: home, temporaryDirectory: temporaryDirectory,
                                    darwinCacheDirectory: darwinCacheDirectory, aiTempRoots: aiTempRoots)
        self.runningApps = Set(runningApps.map { $0.lowercased() })
        self.now = now
    }

    /// Scans every rule in parallel and reports each one as it finishes.
    public func scan(_ rules: [CleanRule] = CleanRule.catalog,
                     onResult: @Sendable @escaping (CategoryResult) async -> Void) async {
        await withTaskGroup(of: CategoryResult.self) { group in
            for rule in rules {
                group.addTask { await self.scan(rule) }
            }
            for await result in group {
                await onResult(result)
            }
        }
    }

    @concurrent
    public func scan(_ rule: CleanRule) async -> CategoryResult {
        let selected = rule.risk == .safe
        var items: [CleanItem] = []

        switch rule.strategy {
        case .paths(let paths):
            for path in paths {
                let url = CleanRule.expand(path, home: home)
                guard exists(url), guardian.isAllowed(url) else { continue }
                items.append(item(url, selected: selected))
            }

        case .children(let folder, let skip, let skipPrefixes, let onlyPrefixes, let skipRunningApps, let policy):
            for url in children(of: CleanRule.expand(folder, home: home)) {
                let name = url.lastPathComponent
                if skip.contains(name) || skipPrefixes.contains(where: name.hasPrefix) { continue }
                if !onlyPrefixes.isEmpty, !onlyPrefixes.contains(where: name.hasPrefix) { continue }
                guard guardian.isAllowed(url, policy: policy) else { continue }
                // An open app's cache is listed but left unticked: its owner may be using it right now.
                items.append(runningNote(item(url, selected: selected, policy: policy), open: skipRunningApps && belongsToRunningApp(name)))
            }

        case .containerCaches:
            let library = home.appending(path: "Library")
            let folders = children(of: library.appending(path: "Containers")).flatMap { container in
                ["Data/Library/Caches", "Data/Library/Logs"].map { (container.lastPathComponent, container.appending(path: $0)) }
            } + children(of: library.appending(path: "Group Containers")).map {
                ($0.lastPathComponent, $0.appending(path: "Library/Caches"))
            }
            for (id, folder) in folders {
                let lower = id.lowercased()
                if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") || lower.contains("cleanmac") { continue }
                // Group container ids look like TEAMID.com.vendor.app; match the running app by its tail.
                let team = id.split(separator: ".").first.map(String.init) ?? ""
                let bundleID = team.count == 10 && team == team.uppercased() ? String(lower.dropFirst(team.count + 1)) : lower
                if belongsToRunningApp(bundleID) || belongsToRunningApp(lower) { continue }
                let contents = children(of: folder)
                guard !contents.isEmpty, contents.allSatisfy({ guardian.isAllowed($0, policy: .containerCache) }) else { continue }
                let size = Self.allocatedSize(of: folder)
                items.append(CleanItem(title: "\(id) · \(folder.lastPathComponent == "Logs" ? "günlükler" : "önbellek")",
                                       detail: relative(folder), size: size, action: .trashContents(folder),
                                       isSelected: selected, policy: .containerCache))
            }

        case .tempFiles(let days):
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            for url in children(of: URL(filePath: guardian.temporaryRoot)) {
                let name = url.lastPathComponent
                if belongsToRunningApp(name) { continue }
                // A folder's own date only moves when direct children come and go: judge by the newest file inside.
                guard let modified = Self.newestModification(in: url, stopAfter: cutoff),
                      modified < cutoff, guardian.isAllowed(url, policy: .tempFile) else { continue }
                items.append(CleanItem(title: name, detail: relative(url), size: Self.allocatedSize(of: url),
                                       action: .trash(url), isSelected: selected, policy: .tempFile, date: modified))
            }

        case .audioPlugins:
            let label = ["Components": "Audio Unit", "VST": "VST", "VST3": "VST3", "HAL": String(localized: "Ses sürücüsü")]
            for kind in SafetyGuard.audioPluginKinds {
                for url in children(of: home.appending(path: "Library/Audio/Plug-Ins/\(kind)")) where guardian.isAllowed(url) {
                    items.append(CleanItem(title: url.deletingPathExtension().lastPathComponent, detail: "\(label[kind] ?? kind) · ~/Library",
                                           size: Self.allocatedSize(of: url), action: .trash(url), isSelected: false))
                }
                for url in children(of: URL(filePath: "/Library/Audio/Plug-Ins/\(kind)"))
                where guardian.isAllowed(url, policy: .systemAdmin) {
                    items.append(CleanItem(title: url.deletingPathExtension().lastPathComponent, detail: String(localized: "\(label[kind] ?? kind) · /Library (parola ister)"),
                                           size: Self.allocatedSize(of: url), action: .adminTrash(url), isSelected: false, policy: .systemAdmin))
                }
            }

        case .darwinCaches(let skipPrefixes, let onlyPrefixes):
            let root = URL(filePath: guardian.darwinCacheRoot)
            for url in children(of: root) {
                let name = url.lastPathComponent
                if skipPrefixes.contains(where: name.hasPrefix) { continue }
                if !onlyPrefixes.isEmpty, !onlyPrefixes.contains(where: name.hasPrefix) { continue }
                guard guardian.isAllowed(url, policy: .darwinCache) else { continue }
                let plain = item(url, selected: selected, policy: .darwinCache)
                let shown = CleanItem(title: name, detail: "/var/folders/…/C/\(name)", size: plain.size, action: plain.action,
                                      isSelected: plain.isSelected, policy: .darwinCache)
                items.append(runningNote(shown, open: belongsToRunningApp(name)))
            }

        case .aiTempFolders(let days):
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            for root in guardian.aiTempRoots.prefix(1) {   // later entries are alternate spellings of the same folder
                for project in children(of: URL(filePath: root)) {
                    for session in children(of: project) {
                        // A live session keeps writing deep inside its folder: judge by the newest file, not the folder.
                        guard let modified = Self.newestModification(in: session, stopAfter: cutoff),
                              modified < cutoff, guardian.isAllowed(session, policy: .aiTemp) else { continue }
                        let project = project.lastPathComponent.replacingOccurrences(of: "-Users-\(NSUserName())-", with: "~/")
                            .replacingOccurrences(of: "-", with: "/")
                        let shown = project.count > 48 ? "…" + project.suffix(47) : project
                        items.append(CleanItem(title: String(localized: "Claude Code oturumu · \(session.lastPathComponent.prefix(8))"),
                                               detail: "\(shown) · \(modified.formatted(date: .abbreviated, time: .omitted))",
                                               size: Self.allocatedSize(of: session), action: .trash(session),
                                               isSelected: selected, policy: .aiTemp, date: modified))
                    }
                }
            }

        case .staleVersions(let root, let activeLink):
            let versions = CleanRule.expand(root, home: home)
            let link = CleanRule.expand(activeLink, home: home)
            // Without a resolvable link nothing says which version is in use, so nothing is offered.
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil else { break }
            let active = link.resolvingSymlinksInPath().path
            for url in children(of: versions) {
                if active.hasPrefix(url.resolvingSymlinksInPath().path) { continue }   // the version in use
                guard guardian.isAllowed(url, policy: .knownData) else { continue }
                items.append(item(url, selected: selected, policy: .knownData))
            }

        case .adminChildren(let folder, let skipPrefixes):
            for url in children(of: URL(filePath: folder)) where !skipPrefixes.contains(where: url.lastPathComponent.hasPrefix) {
                guard guardian.isAllowed(url, policy: .systemAdmin) else { continue }
                items.append(CleanItem(title: url.lastPathComponent, detail: url.path, size: Self.allocatedSize(of: url),
                                       action: .adminTrash(url), isSelected: false, policy: .systemAdmin))
            }

        case .adminOldFiles(let folders, let days):
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            for folder in folders {
                for (url, size, modified) in files(below: URL(filePath: folder)) where modified < cutoff {
                    guard guardian.isAllowed(url, policy: .systemAdmin) else { continue }
                    items.append(CleanItem(title: url.lastPathComponent, detail: url.path, size: size,
                                           action: .adminTrash(url), isSelected: false, policy: .systemAdmin, date: modified))
                }
            }

        case .appDataCaches(let apps):
            for (app, paths) in apps where !belongsToRunningApp(app) {
                for path in paths {
                    let url = CleanRule.expand(path, home: home)
                    guard exists(url), guardian.isAllowed(url, policy: .knownData) else { continue }
                    items.append(CleanItem(title: "\(app) · \(url.lastPathComponent)", detail: relative(url),
                                           size: Self.allocatedSize(of: url), action: .trash(url),
                                           isSelected: selected, policy: .knownData))
                }
            }

        case .brokenLaunchAgents:
            for url in children(of: home.appending(path: "Library/LaunchAgents")) where url.pathExtension == "plist" {
                guard let dict = NSDictionary(contentsOf: url),
                      let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first,
                      program.hasPrefix("/"), !exists(URL(filePath: program)),
                      guardian.isAllowed(url, policy: .appLeftover) else { continue }
                items.append(CleanItem(title: (dict["Label"] as? String) ?? url.lastPathComponent,
                                       detail: String(localized: "Program yok: \(program.replacingOccurrences(of: home.path, with: "~"))"),
                                       size: max(Self.allocatedSize(of: url), 1), action: .trash(url),
                                       isSelected: selected, policy: .appLeftover))
            }

        case .duplicates(let folders, let minBytes):
            let roots = folders.map { CleanRule.expand($0, home: home) }
            let groups = await DuplicateFinder(home: home, roots: roots, autoSelectRoots: [], minBytes: minBytes).find()
            for group in groups {
                let kept = group.items.first?.title ?? ""
                items += group.items.dropFirst().map {
                    CleanItem(title: $0.title, detail: String(localized: "\(kept) dosyasının kopyası · \($0.detail ?? "")"), size: $0.size,
                              action: $0.action, isSelected: false, policy: .userFile, date: $0.date)
                }
            }

        case .privacyTraces:
            for trace in Privacy.traces(home: home) {
                if !trace.app.isEmpty, belongsToRunningApp(trace.app) { continue }
                guard guardian.isAllowed(trace.url, policy: .privacy) else { continue }
                let size = ([trace.url] + Privacy.sidecars(of: trace.url)).reduce(Int64(0)) { $0 + Self.allocatedSize(of: $1) }
                let modified = try? trace.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                items.append(CleanItem(title: trace.title, detail: relative(trace.url), size: max(size, 1),
                                       action: .trash(trace.url), isSelected: false, policy: .privacy, date: modified))
            }

        case .threats:
            for finding in Threats.scan(home: home, appFolders: threatFolders?.apps, launchFolders: threatFolders?.launch) {
                let policy: SafetyGuard.Policy = finding.isApp ? .application : finding.needsAdmin ? .launchItem : .appLeftover
                guard guardian.isAllowed(finding.url, policy: policy) else { continue }
                let modified = try? finding.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                items.append(CleanItem(title: finding.title, detail: finding.reason, size: max(Self.allocatedSize(of: finding.url), 1),
                                       action: finding.needsAdmin ? .adminTrash(finding.url) : .trash(finding.url),
                                       isSelected: false, policy: policy, date: modified,
                                       appIsOpen: finding.isApp && belongsToRunningApp(Bundle(url: finding.url)?.bundleIdentifier ?? finding.title)))
            }

        case .iosBackups:
            let root = home.appending(path: "Library/Application Support/MobileSync/Backup")
            for url in children(of: root) where !url.lastPathComponent.hasPrefix(".") {
                guard guardian.isAllowed(url, policy: .knownData) else { continue }
                let info = NSDictionary(contentsOf: url.appending(path: "Info.plist"))
                let name = info?["Device Name"] as? String ?? url.lastPathComponent
                let version = (info?["Product Version"] as? String).map { "iOS \($0) · " } ?? ""
                let date = info?["Last Backup Date"] as? Date
                items.append(CleanItem(title: name, detail: version + relative(url), size: Self.allocatedSize(of: url),
                                       action: .trash(url), isSelected: false, policy: .knownData, date: date))
            }

        case .appSupportCaches:
            let support = home.appending(path: "Library/Application Support")
            for app in children(of: support) where !app.lastPathComponent.hasPrefix("com.apple.") {
                let open = belongsToRunningApp(app.lastPathComponent)
                for url in children(of: app) where SafetyGuard.appSupportCacheNames.contains(url.lastPathComponent) {
                    guard guardian.isAllowed(url, policy: .appSupportCache) else { continue }
                    items.append(runningNote(CleanItem(title: "\(app.lastPathComponent) · \(url.lastPathComponent)", detail: relative(url),
                                                       size: Self.allocatedSize(of: url), action: .trash(url),
                                                       isSelected: selected, policy: .appSupportCache), open: open))
                }
            }

        case .brokenPreferences:
            let prefs = home.appending(path: "Library/Preferences")
            for url in children(of: prefs) where url.pathExtension == "plist" && !url.lastPathComponent.hasPrefix("com.apple.") {
                guard Self.isBrokenPlist(url), guardian.isAllowed(url, policy: .appLeftover) else { continue }
                items.append(CleanItem(title: url.lastPathComponent, detail: relative(url), size: Self.allocatedSize(of: url),
                                       action: .trash(url), isSelected: false, policy: .appLeftover))
            }

        case .nested(let root, let depth):
            var level = [CleanRule.expand(root, home: home)]
            for _ in 0..<depth { level = level.flatMap { children(of: $0) } }
            for url in level where !url.lastPathComponent.hasPrefix(".") {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true, guardian.isAllowed(url) else { continue }
                items.append(item(url, selected: selected))
            }

        case .orphanedSupportFiles:
            let installed = installedBundleIDs ?? Leftovers.installedBundleIDs()
            // A vendor whose app is open right now may be using these files: listed, never ticked in bulk.
            let openVendors = Set(runningApps.filter { $0.contains(".") }.map(Leftovers.vendor(of:)))
            for url in Leftovers.orphans(home: home, installed: installed) {
                guard guardian.isAllowed(url, policy: .appLeftover) else { continue }
                let open = Leftovers.identifier(from: url.lastPathComponent).map { openVendors.contains(Leftovers.vendor(of: $0)) } ?? false
                items.append(CleanItem(title: url.lastPathComponent, detail: relative(url), size: Self.allocatedSize(of: url),
                                       action: .trash(url), isSelected: false, policy: .appLeftover, appIsOpen: open))
            }

        case .installers(let folders, let selectedIn):
            let auto = selectedIn.map { DuplicateFinder.normalized(CleanRule.expand($0, home: home)) + "/" }
            var found: [String: (URL, Int64, Date)] = [:]
            for folder in folders {
                let root = CleanRule.expand(folder, home: home)
                for (url, size, modified) in files(below: root)
                where Leftovers.installerExtensions.contains(url.pathExtension.lowercased()) {
                    found[DuplicateFinder.normalized(url)] = (url, size, modified)
                }
                // The walk skips build folders (dist, build…) for speed; Spotlight still sees installers there.
                for url in await Self.spotlightInstallers(in: root) where found[DuplicateFinder.normalized(url)] == nil {
                    let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    found[DuplicateFinder.normalized(url)] = (url, Int64(values?.totalFileAllocatedSize ?? 0), values?.contentModificationDate ?? .distantPast)
                }
            }
            for (path, (url, size, modified)) in found {
                guard guardian.isAllowed(url, policy: .userFile) else { continue }
                items.append(CleanItem(title: url.lastPathComponent, detail: relative(url), size: size, action: .trash(url),
                                       isSelected: auto.contains { path.hasPrefix($0) },
                                       policy: .userFile, date: modified))
            }

        case .oldFiles(let folder, let days):
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            for (url, size, modified) in files(below: CleanRule.expand(folder, home: home)) where modified < cutoff {
                guard guardian.isAllowed(url) else { continue }
                items.append(CleanItem(title: url.lastPathComponent, detail: relative(url), size: size,
                                       action: .trash(url), isSelected: selected, date: modified, origin: Self.downloadOrigin(of: url)))
            }

        case .largeFiles(let folders, let minBytes):
            for folder in folders {
                for (url, size, modified) in files(below: CleanRule.expand(folder, home: home)) where size >= minBytes {
                    // Picked one by one by the user, so the user-file policy applies (Desktop, Documents too).
                    guard guardian.isAllowed(url, policy: .userFile) else { continue }
                    items.append(CleanItem(title: url.lastPathComponent, detail: relative(url), size: size,
                                           action: .trash(url), isSelected: false, policy: .userFile, date: modified,
                                           origin: Self.downloadOrigin(of: url)))
                }
            }

        case .tool(let name, let command, let measure):
            let url = CleanRule.expand(measure, home: home)
            let size = Self.allocatedSize(of: url)
            guard size > 0, await Shell.login("command -v \(name)").status == 0 else { break }
            items.append(CleanItem(title: rule.title, detail: command, size: size,
                                   action: .shell(command: command, measure: url), isSelected: selected))

        case .ollamaModels:
            let result = await Shell.login("ollama list", timeout: 10)
            // With the server stopped `ollama list` fails; the manifests on disk still say what is installed.
            let models = result.status == 0 ? ToolData.parseOllama(result.output) : ToolData.ollamaFromManifests(home: home)
            items = models.map { model in
                CleanItem(title: model.name, detail: "ollama rm \(model.name)", size: model.size,
                          action: .shell(command: "ollama rm \(Shell.quote(model.name))", measure: nil), isSelected: false)
            }

        case .simulatorRuntimes:
            guard await SimulatorService.hasDeveloperTools() else { break }
            let list = await Shell.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
            guard list.status == 0 else { break }
            let sims = await SimulatorService.list()
            for runtime in ToolData.parseRuntimes(Data(list.output.utf8)) where runtime.deletable {
                let users = sims.filter { $0.runtimeIdentifier == runtime.runtimeIdentifier }.count
                let used = runtime.lastUsedAt.map { String(localized: "son kullanım \($0.formatted(date: .abbreviated, time: .omitted))") } ?? String(localized: "hiç kullanılmamış")
                let usage = users > 0 ? String(localized: "silinirse bu sürümdeki \(users) simülatör açılmaz") : String(localized: "hiçbir simülatör kullanmıyor")
                items.append(CleanItem(title: runtime.name, detail: "\(used) · \(usage)",
                                       size: runtime.size,
                                       action: .shell(command: "xcrun simctl runtime delete \(Shell.quote(runtime.identifier))", measure: nil),
                                       isSelected: false))
            }

        case .simulators(let days):
            let devices = home.appending(path: "Library/Developer/CoreSimulator/Devices")
            // Newer simctl builds omit lastBootedAt.
            let sims = await SimulatorService.list().map { sim in
                var sim = sim
                if sim.lastBootedAt == nil {
                    sim.lastBootedAt = Self.lastUse(ofSimulatorAt: devices.appending(path: sim.udid))
                }
                return sim
            }
            let now = now
            items = await withTaskGroup(of: CleanItem.self) { group in
                for (sim, isSafe) in SimulatorService.candidates(sims, unusedDays: days, now: now) {
                    group.addTask {
                        let detail = sim.isMissingRuntime
                            ? String(localized: "\(sim.runtime) yüklü değil · sürümü yeniden indirirsen tekrar çalışır")
                            : isSafe
                            ? String(localized: "\(sim.runtime) · kullanılamaz durumda")
                            : "\(sim.runtime) · \(sim.lastBootedAt.map { "son kullanım \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "hiç açılmamış")"
                        return CleanItem(title: sim.name, detail: detail,
                                         size: Self.allocatedSize(of: devices.appending(path: sim.udid)),
                                         action: .deleteSimulator(udid: sim.udid), isSelected: isSafe)
                    }
                }
                return await group.reduce(into: []) { $0.append($1) }
            }
        }

        items.sort { $0.size > $1.size }
        let ignored = IgnoreList.paths(home: home)
        return CategoryResult(rule: rule, items: items.filter { $0.size > 0 && !ignored.contains($0.url.map(DuplicateFinder.normalized) ?? "") })
    }

    // MARK: - Helpers

    /// Installer images and packages Spotlight has indexed under `folder` (empty when Spotlight is off).
    static func spotlightInstallers(in folder: URL) async -> [URL] {
        let query = Leftovers.installerExtensions.map { "kMDItemFSName == '*.\($0)'c" }.joined(separator: " || ")
        let result = await Shell.run("/usr/bin/mdfind", ["-onlyin", folder.path, query])
        guard result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map { URL(filePath: String($0)) }
    }

    /// A non-empty plist that PropertyListSerialization cannot read.
    static func isBrokenPlist(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
    }

    func belongsToRunningApp(_ folderName: String) -> Bool {
        let name = folderName.lowercased()
        return runningApps.contains { $0 == name || $0.hasPrefix(name + " ") || $0.hasPrefix(name + ".") }
    }

    /// The site a downloaded file came from: the referring page if the browser recorded one, else the file's own
    /// address. Mail and messaging apps record their own names, which are kept as they are.
    static func downloadOrigin(of url: URL) -> String? {
        guard let sources = NSMetadataItem(url: url)?.value(forAttribute: "kMDItemWhereFroms") as? [String], !sources.isEmpty else { return nil }
        let candidates = sources.count > 1 ? [sources[1], sources[0]] : sources
        for source in candidates {
            if let host = URL(string: source)?.host(), !host.isEmpty {
                return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            }
        }
        return sources.first.map { String($0.prefix(40)) }
    }

    /// The most recent modification date of a folder or anything below it (bounded walk).
    static func newestModification(in folder: URL, stopAfter cutoff: Date? = nil, limit: Int = 300_000) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = (try? folder.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? nil
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return newest }
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen > limit { return .now }   // too big to judge: treat as in use
            if let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate, date > (newest ?? .distantPast) {
                newest = date
                if let cutoff, date >= cutoff { return date }   // already known to be in use: no need to walk on
            }
        }
        return newest
    }

    /// Marks an item whose app is open: shown, but never ticked for the user.
    func runningNote(_ item: CleanItem, open: Bool) -> CleanItem {
        guard open else { return item }
        return CleanItem(title: item.title, detail: String(localized: "\(item.detail ?? "") · uygulama açık, kapatınca temizle"),
                         size: item.size, action: item.action, isSelected: false, policy: item.policy, date: item.date,
                         origin: item.origin, appIsOpen: true)
    }

    func item(_ url: URL, selected: Bool, policy: SafetyGuard.Policy = .junk) -> CleanItem {
        CleanItem(title: url.lastPathComponent, detail: relative(url), size: Self.allocatedSize(of: url),
                  action: .trash(url), isSelected: selected, policy: policy)
    }

    func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.path, with: "~")
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Finder's own bookkeeping files (.DS_Store, .localized) are never listed as findings.
    func children(of folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ![".DS_Store", ".localized"].contains($0.lastPathComponent) }
    }

    /// Regular files below `folder`, without crossing into other volumes.
    func files(below folder: URL) -> [(URL, Int64, Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .volumeIdentifierKey]
        guard let rootVolume = try? folder.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject,
              let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys + [.isDirectoryKey],
                                                              options: [.skipsPackageDescendants])
        else { return [] }
        var result: [(URL, Int64, Date)] = []
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen % 400 == 0 {
                if Task.isCancelled { break }
                Self.pathReporter?(url.path)
            }
            // Dependency and build folders hold thousands of files that are never a user's large file or installer.
            if DuplicateFinder.skippedFolders.contains(url.lastPathComponent),
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if let volume = values.volumeIdentifier as? NSObject, !volume.isEqual(rootVolume) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            result.append((url, Int64(values.totalFileAllocatedSize ?? 0), values.contentModificationDate ?? .distantPast))
        }
        return result
    }

    /// When the simulator last wrote its preferences: a good "last used" signal when simctl gives none.
    static func lastUse(ofSimulatorAt folder: URL) -> Date? {
        try? folder.appending(path: "data/Library/Preferences")
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Real on-disk size of a file or folder (hidden files included, other volumes excluded).
    public static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .volumeIdentifierKey]
        guard let rootValues = try? url.resourceValues(forKeys: keys) else { return 0 }
        if rootValues.isRegularFile == true { return Int64(rootValues.totalFileAllocatedSize ?? 0) }
        guard let rootVolume = rootValues.volumeIdentifier as? NSObject,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        else { return 0 }
        var total: Int64 = 0
        var seen = 0
        let reporter = pathReporter
        for case let child as URL in enumerator {
            seen += 1
            if seen % 400 == 0 {
                if Task.isCancelled { break }
                reporter?(child.path)
            }
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if let volume = values.volumeIdentifier as? NSObject, !volume.isEqual(rootVolume) {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true { total += Int64(values.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
