import Foundation
import Security

/// Signs of unwanted software, judged by code signatures and where things run from.
/// There is no malware database here: a finding means "Gatekeeper would not vouch for this", not "this is a virus".
///
/// - Apps in the Applications folders whose signature is missing or broken, or that came from the internet
///   (quarantined) with only an ad-hoc signature.
/// - Launch agents and daemons whose program has a broken signature, or runs unsigned from a hidden folder,
///   /tmp, /Users/Shared or Application Support: the pattern adware such as Adload and Pirrit uses.
public enum Threats {
    public enum Signature: Sendable, Equatable {
        case trusted, other, adhoc, unsigned, invalid
    }

    public struct Finding: Sendable, Equatable {
        public let url: URL
        public let title: String
        public let reason: String
        /// /Library/LaunchAgents or /Library/LaunchDaemons: moving it needs an administrator.
        public let needsAdmin: Bool
        public let isApp: Bool
    }

    /// Who signed `url` (an app bundle or a program). Resources are not re-hashed so big apps stay quick.
    public static func signature(of url: URL) -> Signature {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .unsigned }
        let flags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
        switch SecStaticCodeCheckValidity(code, flags, nil) {
        case errSecSuccess: break
        case errSecCSUnsigned: return .unsigned
        // Only a real mismatch counts as tampering; an unfamiliar layout or a passing Security error does not.
        case errSecCSSignatureFailed, errSecCSSignatureInvalid, errSecCSBadResource, errSecCSBadMainExecutable: return .invalid
        default: return .other
        }
        var info: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dict = info as? [String: Any],
           let codeFlags = dict[kSecCodeInfoFlags as String] as? UInt32,
           codeFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 {
            return .adhoc
        }
        var requirement: SecRequirement?
        if SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
           SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess {
            return .trusted
        }
        return .other
    }

    /// Downloaded from the internet and not yet cleared by the user (`com.apple.quarantine`).
    static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// Places adware hides its programs in; ordinary apps run from their bundle or a package manager.
    /// System daemons of VPN and security tools legitimately live in /Library/Application Support, so that
    /// folder only counts for the user's own agents (`system` false).
    static func isHiddenLocation(_ path: String, home: String, system: Bool = false) -> Bool {
        let parts = path.split(separator: "/")
        if parts.dropLast().contains(where: { $0.hasPrefix(".") && !toolFolders.contains(String($0)) }) { return true }
        let roots = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/Users/Shared/"]
            + (system ? [] : ["/Library/Application Support/", "\(home)/Library/Application Support/"])
        return roots.contains { path.hasPrefix($0) }
    }

    /// Dot folders developer tools install their programs in (pipx, uv, cargo, bun, version managers).
    static let toolFolders: Set<String> = [".local", ".cargo", ".rustup", ".bun", ".deno", ".nvm", ".volta", ".pyenv",
                                           ".rbenv", ".asdf", ".npm-global", ".orbstack", ".docker", ".claude", ".codex"]

    /// Interpreters a launch item may start; then the script it runs is what counts.
    static let interpreters: Set<String> = ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/python3",
                                            "/usr/bin/osascript", "/usr/bin/perl", "/usr/bin/ruby", "/bin/launchctl"]

    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                            appFolders: [URL]? = nil, launchFolders: [(URL, Bool)]? = nil) -> [Finding] {
        let h = home.path
        var findings: [Finding] = []
        let fm = FileManager.default

        for folder in appFolders ?? [URL(filePath: "/Applications"), home.appending(path: "Applications")] {
            for app in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where app.pathExtension == "app" {
                let id = Bundle(url: app)?.bundleIdentifier ?? ""
                if id.hasPrefix("com.apple.") { continue }
                let reason: String? = switch signature(of: app) {
                case .unsigned: String(localized: "İmzasız uygulama: geliştiricisi doğrulanamıyor")
                case .invalid: String(localized: "İmzası bozuk: uygulama imzalandıktan sonra değiştirilmiş")
                case .adhoc where isQuarantined(app): String(localized: "İnternetten indirilmiş, geliştirici imzası yok")
                default: nil
                }
                if let reason {
                    findings.append(Finding(url: app, title: app.deletingPathExtension().lastPathComponent,
                                            reason: reason, needsAdmin: false, isApp: true))
                }
            }
        }

        let launch = launchFolders ?? [(home.appending(path: "Library/LaunchAgents"), false),
                                       (URL(filePath: "/Library/LaunchAgents"), true),
                                       (URL(filePath: "/Library/LaunchDaemons"), true)]
        for (folder, admin) in launch {
            for plist in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where plist.pathExtension == "plist" {
                guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { continue }
                let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                let args = (dict["ProgramArguments"] as? [String]) ?? []
                guard var program = (dict["Program"] as? String) ?? args.first, program.hasPrefix("/") else { continue }
                // `/bin/sh /path/to/script`: judge the script, not the shell.
                if interpreters.contains(program),
                   let script = args.dropFirst().first(where: { $0.hasPrefix("/") && fm.fileExists(atPath: $0) }) {
                    program = script
                } else if interpreters.contains(program) {
                    continue
                }
                guard fm.fileExists(atPath: program) else { continue }   // a missing program is the "broken" rule's job
                let hidden = isHiddenLocation(program, home: h, system: admin)
                let reason: String? = switch signature(of: URL(filePath: program)) {
                case .invalid: String(localized: "Başlattığı programın imzası bozuk")
                case .unsigned where hidden, .adhoc where hidden: String(localized: "İmzasız bir programı gizli ya da ortak bir klasörden başlatıyor")
                default: nil
                }
                if let reason {
                    findings.append(Finding(url: plist, title: label,
                                            reason: "\(reason) · \(program.replacingOccurrences(of: h, with: "~"))"
                                                + (admin ? String(localized: " · Sistem servisi: kaldırınca bir sonraki açılışta başlamaz; geri koymak parola ister") : ""),
                                            needsAdmin: admin, isApp: false))
                }
            }
        }
        return findings
    }
}
