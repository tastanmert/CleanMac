import Foundation

/// Launch agents and daemons that start with the Mac.
/// Only the user's own agents can be switched off here (reversibly, with `launchctl disable`);
/// system-wide ones need an administrator and are shown for information.
public enum StartupItems {
    public struct Item: Identifiable, Sendable, Hashable {
        public var id: String { plist.path }
        public let label: String
        public let program: String
        public let plist: URL
        public let isUserAgent: Bool
        public var isDisabled: Bool
        public let isRunning: Bool

        /// The program it starts no longer exists (its app was removed): the agent can only fail.
        public var isBroken: Bool {
            program.hasPrefix("/") && !FileManager.default.fileExists(atPath: program)
        }

        /// The .app the program lives in, if any (shows its icon and name instead of a bare label).
        public var owningApp: URL? {
            var url = URL(filePath: program)
            while url.path != "/" {
                if url.pathExtension == "app" { return url }
                url.deleteLastPathComponent()
            }
            return nil
        }
    }

    public static func list(home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> [Item] {
        let folders: [(URL, Bool)] = [
            (home.appending(path: "Library/LaunchAgents"), true),
            (URL(filePath: "/Library/LaunchAgents"), false),
            (URL(filePath: "/Library/LaunchDaemons"), false),
        ]
        let uid = getuid()
        let disabledOutput = await Shell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"]).output
        let running = await Shell.run("/bin/launchctl", ["list"]).output

        return folders.flatMap { folder, isUser in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "plist" }
                .compactMap { url -> Item? in
                    guard let dict = NSDictionary(contentsOf: url) as? [String: Any],
                          let label = dict["Label"] as? String else { return nil }
                    let program = (dict["Program"] as? String) ?? ((dict["ProgramArguments"] as? [String])?.first) ?? ""
                    let disabledInPlist = dict["Disabled"] as? Bool ?? false
                    return Item(label: label, program: program, plist: url, isUserAgent: isUser,
                                isDisabled: disabledInPlist || isDisabled(label, in: disabledOutput),
                                isRunning: running.contains("\t\(label)\n") || running.hasSuffix("\t\(label)"))
                }
        }
        .sorted { ($0.isUserAgent ? 0 : 1, $0.label) < ($1.isUserAgent ? 0 : 1, $1.label) }
    }

    /// `launchctl print-disabled` lines look like: "com.example.agent" => disabled
    static func isDisabled(_ label: String, in output: String) -> Bool {
        output.split(separator: "\n").contains { line in
            line.contains("\"\(label)\"") && (line.contains("=> disabled") || line.contains("=> true"))
        }
    }

    /// Stops a user agent and keeps it from starting again. Reversible with `setEnabled(true, …)`.
    public static func setEnabled(_ enabled: Bool, _ item: Item) async -> Bool {
        guard item.isUserAgent else { return false }
        let domain = "gui/\(getuid())"
        if enabled {
            let enable = await Shell.run("/bin/launchctl", ["enable", "\(domain)/\(item.label)"])
            _ = await Shell.run("/bin/launchctl", ["bootstrap", domain, item.plist.path])
            return enable.status == 0
        } else {
            _ = await Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(item.label)"])
            return await Shell.run("/bin/launchctl", ["disable", "\(domain)/\(item.label)"]).status == 0
        }
    }
}
