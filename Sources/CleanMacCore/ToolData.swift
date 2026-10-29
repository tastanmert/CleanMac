import Foundation

/// Large data owned by developer tools, removed only through each tool's own command.
enum ToolData {
    struct OllamaModel: Equatable {
        let name: String
        let size: Int64
    }

    /// Parses `ollama list`:
    /// NAME          ID              SIZE      MODIFIED
    /// qwen3.5:4b    d8b0f5e9760c    3.3 GB    40 hours ago
    static func parseOllama(_ output: String) -> [OllamaModel] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 4, let value = Double(cols[2]) else { return nil }
            let unit: Double = switch cols[3].uppercased() {
            case "KB": 1e3
            case "MB": 1e6
            case "GB": 1e9
            case "TB": 1e12
            default: 1
            }
            return OllamaModel(name: String(cols[0]), size: Int64(value * unit))
        }
    }

    /// Models read straight from `~/.ollama/models/manifests/<registry>/<namespace>/<model>/<tag>`, for when the
    /// Ollama server is not running and `ollama list` cannot answer. Size is the manifest's layers plus config.
    static func ollamaFromManifests(home: URL) -> [OllamaModel] {
        let root = home.appending(path: ".ollama/models/manifests")
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var models: [OllamaModel] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            // registry / namespace / model / tag: the last four components (the walk may report /private/var for /var)
            let parts = url.pathComponents.suffix(4)
            guard url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "manifests",
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let layers = (json["layers"] as? [[String: Any]] ?? []) + [json["config"] as? [String: Any] ?? [:]]
            let size = layers.reduce(Int64(0)) { $0 + ((($1["size"]) as? NSNumber)?.int64Value ?? 0) }
            let p = Array(parts)
            let name = (p[1] == "library" ? p[2] : "\(p[1])/\(p[2])") + ":" + p[3]
            models.append(OllamaModel(name: name, size: size))
        }
        return models.sorted { $0.size > $1.size }
    }

    struct Runtime: Equatable {
        let identifier: String
        let name: String
        let size: Int64
        let lastUsedAt: Date?
        let deletable: Bool
        let runtimeIdentifier: String
    }

    /// Cryptex runtimes report a near-zero `sizeBytes`; measure their image instead.
    static func size(reported: Int64, path: String?) -> Int64 {
        guard reported < 1_000_000, let path else { return reported }
        return max(reported, Scanner.allocatedSize(of: URL(filePath: path)))
    }

    /// Parses `xcrun simctl runtime list -j`.
    static func parseRuntimes(_ json: Data) -> [Runtime] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: [String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return root.values.compactMap { r in
            guard let id = r["identifier"] as? String else { return nil }
            let runtimeID = r["runtimeIdentifier"] as? String ?? ""
            let version = r["version"] as? String
            let name = version.map { "iOS \($0)" } ?? SimulatorService.readable(runtimeID)
            return Runtime(identifier: id, name: name,
                           size: Self.size(reported: (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0, path: r["path"] as? String),
                           lastUsedAt: (r["lastUsedAt"] as? String).flatMap(iso.date(from:)),
                           deletable: r["deletable"] as? Bool ?? false,
                           runtimeIdentifier: runtimeID)
        }
        .sorted { $0.name < $1.name }
    }
}
