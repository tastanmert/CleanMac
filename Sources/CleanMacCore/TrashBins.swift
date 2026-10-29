import Foundation

/// The Trash folders on this Mac: the user's own and one per mounted disk.
/// Finder's "Empty Trash" empties all of them together.
public enum TrashBins {
    public struct Bin: Identifiable, Sendable, Hashable {
        public var id: URL { url }
        public let name: String
        public let url: URL
        public let size: Int64
        public let count: Int
        public let isExternal: Bool
    }

    public static func list(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            volumes: URL = URL(filePath: "/Volumes")) -> [Bin] {
        var bins: [Bin] = []
        if let bin = bin(name: String(localized: "Çöp"), url: home.appending(path: ".Trash"), external: false) { bins.append(bin) }
        let uid = getuid()
        let mounted = (try? FileManager.default.contentsOfDirectory(at: volumes, includingPropertiesForKeys: nil)) ?? []
        for volume in mounted {
            // The startup disk shows up here as a link back to "/"; its Trash is the user's own.
            if (try? volume.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            if let bin = bin(name: volume.lastPathComponent, url: volume.appending(path: ".Trashes/\(uid)"), external: true) {
                bins.append(bin)
            }
        }
        return bins
    }

    static func bin(name: String, url: URL, external: Bool) -> Bin? {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
        let visible = items.filter { $0 != ".DS_Store" }
        return Bin(name: name, url: url, size: Scanner.allocatedSize(of: url), count: visible.count, isExternal: external)
    }
}
