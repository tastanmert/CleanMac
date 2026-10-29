import Foundation

public enum Shell {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
    }

    /// Runs `command` in a login zsh so the user's PATH (Homebrew, nvm, ~/.local/bin) is available.
    static func login(_ command: String, timeout: TimeInterval = 25) async -> Result {
        await run("/bin/zsh", ["-lc", command], timeout: timeout)
    }

    /// Single-quotes `text` for a POSIX shell.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Long enough for a password prompt or a big cleanup (brew, simulator runtimes, Spotlight rebuild);
    /// scans keep the short default so one stuck tool never stalls them.
    public static let actionTimeout: TimeInterval = 30 * 60

    /// osascript's "User canceled. (-128)": the administrator password dialog was dismissed.
    public static func wasCancelled(_ result: Result) -> Bool {
        result.status != 0 && result.output.contains("(-128)")
    }

    /// Collects a child's output and settles exactly once: when the process exits or the timeout hits.
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var finished = false
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        /// Returns the output the first time it is called, nil afterwards.
        func finish() -> String? {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return nil }
            finished = true
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Runs a tool and returns its output. A tool that hangs (a busy daemon, a licence prompt) is killed
    /// after `timeout` seconds and reported as status -2, so one stuck command never freezes a scan.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 25) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            // A GUI app starts in "/", which is read-only; tools such as pnpm write temp files to the cwd.
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            let capture = Capture()
            // Drain while the process runs: output larger than the pipe buffer (64 KB) would otherwise block it.
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil } else { capture.append(chunk) }
            }
            // A background child the tool leaves behind can keep the pipe open; the exit is what counts.
            process.terminationHandler = { finished in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    if let output = capture.finish() {
                        continuation.resume(returning: Result(status: finished.terminationStatus, output: output))
                    }
                }
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminate()
                if let output = capture.finish() {
                    continuation.resume(returning: Result(status: -2, output: output))
                }
            }
        }
    }
}
