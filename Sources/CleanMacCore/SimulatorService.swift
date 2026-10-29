import Foundation

public struct Simulator: Sendable, Decodable, Equatable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
    public let dataPath: String?
    public var lastBootedAt: Date?
    public var availabilityError: String?
    public var runtime: String = ""
    public var runtimeIdentifier: String = ""

    enum CodingKeys: String, CodingKey { case udid, name, state, isAvailable, dataPath, lastBootedAt, availabilityError }

    /// Unavailable only because its iOS version is not installed: comes back when the runtime is re-downloaded.
    public var isMissingRuntime: Bool {
        !isAvailable && (availabilityError ?? "").localizedCaseInsensitiveContains("runtime")
    }
}

enum SimulatorService {
    /// Parses `xcrun simctl list devices -j`.
    static func parse(_ json: Data) throws -> [Simulator] {
        struct List: Decodable { let devices: [String: [Simulator]] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(List.self, from: json)
        return list.devices.flatMap { runtime, sims in
            sims.map { var s = $0; s.runtime = Self.readable(runtime); s.runtimeIdentifier = runtime; return s }
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-4" → "iOS 26.4"
    static func readable(_ runtime: String) -> String {
        let last = runtime.split(separator: ".").last.map(String.init) ?? runtime
        let parts = last.split(separator: "-")
        guard let os = parts.first else { return last }
        return parts.count > 1 ? "\(os) \(parts.dropFirst().joined(separator: "."))" : String(os)
    }

    /// On a Mac without Xcode or its command line tools, calling xcrun pops an install dialog; never do that.
    static func hasDeveloperTools() async -> Bool {
        await Shell.run("/usr/bin/xcode-select", ["-p"]).status == 0
            && FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }

    static func list() async -> [Simulator] {
        guard await hasDeveloperTools() else { return [] }
        let result = await Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"])
        guard result.status == 0 else { return [] }
        return (try? parse(Data(result.output.utf8))) ?? []
    }

    /// Truly broken simulators are safe to delete. Ones missing only their iOS runtime, and shut-down
    /// ones unused for `unusedDays`, are offered for review but never pre-selected.
    static func candidates(_ sims: [Simulator], unusedDays: Int, now: Date = .now) -> [(Simulator, isSafe: Bool)] {
        let cutoff = now.addingTimeInterval(-Double(unusedDays) * 86_400)
        return sims.compactMap { sim in
            if sim.state == "Booted" { return nil }
            if sim.isMissingRuntime { return (sim, false) }
            if !sim.isAvailable { return (sim, true) }
            if (sim.lastBootedAt ?? .distantPast) < cutoff { return (sim, false) }
            return nil
        }
    }
}
