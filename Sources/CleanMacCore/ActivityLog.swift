import Foundation

/// What CleanMac has done over time (for the Activity screen) and what the user asked it to leave alone.
/// Both live in ~/Library/Application Support/CleanMac as small JSON files.
public enum ActivityLog {
    public struct Entry: Codable, Sendable, Hashable, Identifiable {
        public var id: Date { date }
        public let date: Date
        public let source: String
        public let bytes: Int64
        public let count: Int
    }

    public static func folder(home: URL) -> URL { home.appending(path: "Library/Application Support/CleanMac") }

    public static func entries(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Entry] {
        guard let data = try? Data(contentsOf: folder(home: home).appending(path: "activity.json")) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    public static func record(_ entry: Entry, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        guard entry.count > 0 else { return }
        let all = Array((entries(home: home) + [entry]).suffix(1_000))
        let dir = folder(home: home)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: dir.appending(path: "activity.json"), options: .atomic)
    }
}

public enum IgnoreList {
    static func file(home: URL) -> URL { ActivityLog.folder(home: home).appending(path: "ignored.json") }

    public static func paths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<String> {
        guard let data = try? Data(contentsOf: file(home: home)) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    public static func set(_ paths: Set<String>, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        try? FileManager.default.createDirectory(at: ActivityLog.folder(home: home), withIntermediateDirectories: true)
        try? JSONEncoder().encode(paths).write(to: file(home: home), options: .atomic)
    }

    public static func add(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        set(paths(home: home).union([DuplicateFinder.normalized(url)]), home: home)
    }

    public static func remove(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        set(paths(home: home).subtracting([path]), home: home)
    }
}
