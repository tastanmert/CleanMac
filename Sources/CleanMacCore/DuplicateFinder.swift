import CryptoKit
import Foundation

/// Finds byte-identical files: group by size, then by a hash of the first 64 KB, then by a full SHA-256.
public struct DuplicateFinder: Sendable {
    public struct Group: Identifiable, Sendable {
        public let id = UUID()
        public let size: Int64
        public var items: [CleanItem]
        public var wasted: Int64 { size * Int64(max(0, items.count - 1)) }
    }

    public let home: URL
    let roots: [URL]
    /// Duplicates under these folders are pre-selected; elsewhere (Desktop, Documents, projects) the user decides.
    let autoSelectRoots: [URL]
    let minBytes: Int64
    static let skippedFolders: Set<String> = ["node_modules", ".git", ".build", "build", "DerivedData", "Pods", "venv", ".venv",
                                              "__pycache__", ".next", "dist", ".turbo", ".gradle", "target"]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, minBytes: Int64 = 1_000_000) {
        self.home = home
        roots = ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"].map { home.appending(path: $0) }
        // Only Downloads: Desktop and Documents may hold projects whose files are duplicated on purpose.
        autoSelectRoots = [home.appending(path: "Downloads")]
        self.minBytes = minBytes
    }

    init(home: URL, roots: [URL], autoSelectRoots: [URL], minBytes: Int64) {
        self.home = home
        self.roots = roots
        self.autoSelectRoots = autoSelectRoots
        self.minBytes = minBytes
    }

    @concurrent
    public func find(progress: @Sendable @escaping (String) async -> Void = { _ in }) async -> [Group] {
        var bySize: [Int64: [(URL, Date)]] = [:]
        for root in roots {
            await progress(root.lastPathComponent)
            for (url, size, created) in files(in: root) where size >= minBytes {
                bySize[size, default: []].append((url, created))
            }
        }

        var groups: [Group] = []
        let guardian = SafetyGuard(home: home)
        for (size, candidates) in bySize where candidates.count > 1 {
            if Task.isCancelled { break }
            let byHead = Dictionary(grouping: candidates) { Self.hash($0.0, limit: 65_536) ?? UUID().uuidString }
            for heads in byHead.values where heads.count > 1 {
                let byFull = Dictionary(grouping: heads) { Self.hash($0.0, limit: nil) ?? UUID().uuidString }
                for same in byFull.values where same.count > 1 {
                    // Keep the oldest copy; offer the rest.
                    let homePath = Self.normalized(home)
                    let autoPaths = autoSelectRoots.map { Self.normalized($0) + "/" }
                    // Same date (copied together): keep the one outside Downloads, the likelier original.
                    let inAuto = { (url: URL) in autoPaths.contains { Self.normalized(url).hasPrefix($0) } }
                    let ordered = same.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : !inAuto($0.0) && inAuto($1.0) }
                    let items = ordered.enumerated().compactMap { index, entry -> CleanItem? in
                        let (url, _) = entry
                        guard guardian.isAllowed(url, policy: .userFile) else { return nil }
                        let path = Self.normalized(url)
                        let auto = index > 0 && autoPaths.contains { path.hasPrefix($0) }
                        return CleanItem(title: url.lastPathComponent,
                                         detail: path.replacingOccurrences(of: homePath, with: "~"),
                                         size: size, action: .trash(url), isSelected: auto, policy: .userFile)
                    }
                    if items.count > 1 { groups.append(Group(size: size, items: items)) }
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    func files(in root: URL) -> [(URL, Int64, Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [(URL, Int64, Date)] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                let name = url.lastPathComponent
                // Build output, dependencies and asset catalogs hold intentional copies.
                if Self.skippedFolders.contains(name) || name.hasSuffix(".xcassets") { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            result.append((url, Int64(values.fileSize ?? 0), values.creationDate ?? .distantPast))
        }
        return result
    }

    /// Enumerators may report /private/var where the caller passed /var; compare resolved paths.
    static func normalized(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0 {
            let chunk = handle.readData(ofLength: min(1 << 20, remaining))
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
