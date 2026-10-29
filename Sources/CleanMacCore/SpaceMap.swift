import Foundation

/// One level of the space map: the children of a folder with their real on-disk size.
public enum SpaceMap {
    public struct Node: Identifiable, Sendable, Hashable {
        public var id: URL { url }
        public let url: URL
        /// nil until measured.
        public var size: Int64?
        public let isFolder: Bool
        public var name: String { url.lastPathComponent }
    }

    /// The children of `folder`, unmeasured, right away. Symlinks and other volumes are left out.
    public static func entries(of folder: URL, includeHidden: Bool = true) -> [Node] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                      options: options) else { return [] }
        let folderVolume = SafetyGuard.volume(of: folder)
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { return nil }
            if let v = SafetyGuard.volume(of: url), let fv = folderVolume, v != fv { return nil }
            return Node(url: url, size: nil, isFolder: values?.isDirectory == true && values?.isPackage != true)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Measures `nodes` at most `width` at a time, reporting each one as it finishes.
    public static func measure(_ nodes: [Node], width: Int = 8,
                               onMeasured: @Sendable (Node) async -> Void) async {
        await withTaskGroup(of: Node?.self) { group in
            var pending = nodes[...]
            func addNext() {
                guard var node = pending.popFirst() else { return }
                group.addTask {
                    if Task.isCancelled { return nil }
                    node.size = Scanner.allocatedSize(of: node.url)
                    return node
                }
            }
            for _ in 0..<width { addNext() }
            for await node in group {
                if let node { await onMeasured(node) }
                addNext()
            }
        }
    }

    /// Measured, non-empty children, largest first.
    public static func children(of folder: URL, includeHidden: Bool = true) async -> [Node] {
        let collected = Collected()
        await measure(entries(of: folder, includeHidden: includeHidden)) { await collected.add($0) }
        return await collected.nodes.filter { ($0.size ?? 0) > 0 }.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
    }

    private actor Collected {
        var nodes: [Node] = []
        func add(_ node: Node) { nodes.append(node) }
    }
}
