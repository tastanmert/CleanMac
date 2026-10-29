import Foundation
import Security

/// Finds support files left behind by apps that are no longer installed.
///
/// Only entries named like a bundle identifier are considered and Apple's are skipped. "Installed" covers each
/// app's embedded helpers and extensions and the app groups it declares. Small per-app files (preferences, saved
/// state, web storage) belong to an installed app only when one identifier extends the other, so another product of
/// the same vendor does not hide them. Data folders (Application Support, containers,
/// app groups, scripts) are kept whenever the vendor has any app installed: helpers and shared group folders rarely
/// carry the main app's name. Never selected by default.
public enum Leftovers {
    public static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]

    // Caches and Logs have their own rules; counting them here too would show the same bytes twice.
    static let leftoverFolders = ["Application Support", "Preferences", "Saved Application State",
                                  "HTTPStorages", "WebKit", "Containers", "Group Containers", "Application Scripts"]
    /// Folders holding an app's data or data shared between a vendor's apps: any installed app of the vendor keeps them.
    static let vendorGuardedFolders: Set<String> = ["Application Support", "Containers", "Group Containers", "Application Scripts"]

    /// Frameworks, SDKs and command-line tools: their files are shared by other apps or have no app at all.
    static let sharedVendors: Set<String> = [
        "org.swift", "org.sparkle-project", "com.bugsnag", "com.firebase", "com.segment", "com.launchdarkly",
        "com.crashlytics", "io.sentry", "com.amplitude", "com.google", "com.microsoft", "com.vercel",
    ]

    /// Bundle identifiers of every installed app (Spotlight plus the usual folders).
    public static func installedBundleIDs() -> Set<String> {
        var urls: [URL] = []
        let mdfind = Process()
        mdfind.executableURL = URL(filePath: "/usr/bin/mdfind")
        mdfind.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        mdfind.standardOutput = pipe
        mdfind.standardError = FileHandle.nullDevice
        if (try? mdfind.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            mdfind.waitUntilExit()
            urls += String(decoding: data, as: UTF8.self).split(separator: "\n").map { URL(filePath: String($0)) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in ["/Applications", "/Applications/Utilities", "/System/Applications", "\(home.path)/Applications"] {
            urls += ((try? FileManager.default.contentsOfDirectory(at: URL(filePath: folder), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        var ids = Set<String>()
        for app in urls {
            guard let id = Bundle(url: app)?.bundleIdentifier?.lowercased() else { continue }
            ids.insert(id)
            // Login-item helpers, extensions and XPC services: Spotlight does not list bundles inside bundles.
            for sub in ["Contents/Library/LoginItems", "Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LaunchServices"] {
                for inner in (try? FileManager.default.contentsOfDirectory(at: app.appending(path: sub), includingPropertiesForKeys: nil)) ?? [] {
                    if let innerID = Bundle(url: inner)?.bundleIdentifier?.lowercased() { ids.insert(innerID) }
                }
            }
            if !app.path.hasPrefix("/System/") { ids.formUnion(sharedGroups(of: app)) }
        }
        return ids
    }

    /// The app groups and keychain groups an app's signature declares ("group.net.whatsapp.family" → "net.whatsapp.family").
    static func sharedGroups(of app: URL) -> [String] {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let entitlements = (info as? [String: Any])?[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        let groups = (entitlements["com.apple.security.application-groups"] as? [String] ?? [])
            + (entitlements["keychain-access-groups"] as? [String] ?? [])
        return groups.compactMap(identifier(from:))
    }

    /// "ABCDE12345.com.vendor.app" or "group.com.vendor.app" → "com.vendor.app"; "x.plist" → "x".
    static func identifier(from name: String) -> String? {
        var id = name.lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies"] where id.hasSuffix(suffix) { id.removeLast(suffix.count) }
        var parts = id.split(separator: ".").map(String.init)
        if parts.first == "group" { parts.removeFirst() }
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isLetter || $0.isNumber }), parts.count > 3 {
            parts.removeFirst()   // team identifier prefix
        }
        let tlds: Set<String> = ["com", "org", "net", "io", "ai", "dev", "app", "co", "me", "de", "us", "tv", "so", "sh", "cc", "info"]
        guard parts.count >= 3, let tld = parts.first, tlds.contains(tld) else { return nil }
        return parts.joined(separator: ".")
    }

    /// "com.vendor.app.widgets" and "com.vendor.app" belong together, either way round; "com.vendor.other" does not.
    static func belongs(_ id: String, to app: String) -> Bool {
        id == app || id.hasPrefix(app + ".") || app.hasPrefix(id + ".")
    }

    static func vendor(of id: String) -> String {
        id.split(separator: ".").prefix(2).joined(separator: ".")
    }

    public static func orphans(home: URL, installed: Set<String>) -> [URL] {
        let vendors = Set(installed.map(vendor(of:)))
        return leftoverFolders.flatMap { folder -> [URL] in
            let root = home.appending(path: "Library/\(folder)")
            return ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).filter { url in
                guard let id = identifier(from: url.lastPathComponent), !id.hasPrefix("com.apple.") else { return false }
                if sharedVendors.contains(vendor(of: id)) || id.hasSuffix("-cli") || id.hasSuffix(".cli") { return false }
                if vendorGuardedFolders.contains(folder), vendors.contains(vendor(of: id)) { return false }
                return !installed.contains { belongs(id, to: $0) }
            }
        }
    }
}
