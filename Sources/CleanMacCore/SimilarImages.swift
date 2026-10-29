import Accelerate
import Foundation
import ImageIO
import Vision

/// Finds photos that look alike (bursts, edits, re-saved copies) with Vision's image feature prints.
/// Everything runs on this Mac. Nothing is selected for removal by default; the best shot of each
/// group (highest resolution, then newest) is marked so "smart select" can keep it.
public struct SimilarImages: Sendable {
    public struct Group: Identifiable, Sendable {
        public let id = UUID()
        public var items: [CleanItem]
        /// Index of the copy worth keeping.
        public let best: Int
    }

    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
    let roots: [URL]
    let home: URL
    let threshold: Float
    let limit: Int

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, threshold: Float = 0.28, limit: Int = 3_000) {
        self.init(home: home, roots: ["Pictures", "Desktop", "Downloads", "Documents"].map { home.appending(path: $0) },
                  threshold: threshold, limit: limit)
    }

    init(home: URL, roots: [URL], threshold: Float, limit: Int) {
        self.home = home
        self.roots = roots
        self.threshold = threshold
        self.limit = limit
    }

    @concurrent
    public func find(progress: @Sendable @escaping (String) async -> Void = { _ in }) async -> [Group] {
        let guardian = SafetyGuard(home: home)
        var images: [(url: URL, size: Int64, date: Date)] = []
        for root in roots {
            await progress(root.lastPathComponent)
            images += Self.imageFiles(in: root)
            if images.count >= limit { break }
        }
        images = Array(images.prefix(limit))

        // Feature prints are independent; a few at a time keeps every core busy without flooding memory.
        var prints: [(index: Int, vector: [Float], pixels: Int)] = []
        await withTaskGroup(of: (Int, [Float], Int)?.self) { group in
            var next = 0
            func enqueue() {
                guard next < images.count else { return }
                let index = next, url = images[index].url
                next += 1
                group.addTask { Self.featurePrint(url).map { (index, $0.0, $0.1) } }
            }
            for _ in 0..<min(ProcessInfo.processInfo.activeProcessorCount, 8) { enqueue() }
            var done = 0
            for await result in group {
                done += 1
                if let result { prints.append(result) }
                if done % 25 == 0 { await progress(String(localized: "\(done) / \(images.count) görsel")) }
                if Task.isCancelled { group.cancelAll(); return }
                enqueue()
            }
        }
        prints.sort { $0.index < $1.index }

        // Union-find over every close pair.
        var parent = Array(0..<prints.count)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let limitSquared = threshold * threshold
        for i in prints.indices {
            if Task.isCancelled { return [] }
            for j in (i + 1)..<prints.count where prints[i].vector.count == prints[j].vector.count {
                var distance: Float = 0
                vDSP_distancesq(prints[i].vector, 1, prints[j].vector, 1, &distance, vDSP_Length(prints[i].vector.count))
                if distance < limitSquared { parent[root(j)] = root(i) }
            }
        }

        let homePath = DuplicateFinder.normalized(home)
        return Dictionary(grouping: prints.indices, by: root).values
            .filter { $0.count > 1 }
            .compactMap { members -> Group? in
                let ordered = members.sorted { a, b in
                    (prints[a].pixels, images[prints[a].index].date) > (prints[b].pixels, images[prints[b].index].date)
                }
                let items = ordered.compactMap { m -> CleanItem? in
                    let image = images[prints[m].index]
                    guard guardian.isAllowed(image.url, policy: .userFile) else { return nil }
                    return CleanItem(title: image.url.lastPathComponent,
                                     detail: DuplicateFinder.normalized(image.url).replacingOccurrences(of: homePath, with: "~"),
                                     size: image.size, action: .trash(image.url), isSelected: false, policy: .userFile, date: image.date)
                }
                return items.count > 1 ? Group(items: items, best: 0) : nil
            }
            .sorted { $0.items.count > $1.items.count }
    }

    static func imageFiles(in root: URL) -> [(url: URL, size: Int64, date: Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [(URL, Int64, Date)] = []
        for case let url as URL in enumerator {
            if DuplicateFinder.skippedFolders.contains(url.lastPathComponent) || isProjectFolder(url) {
                enumerator.skipDescendants()
                continue
            }
            guard extensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size >= 30_000 else { continue }
            result.append((url, Int64(size), values.creationDate ?? .distantPast))
        }
        return result
    }

    /// Images inside code projects are app icons, assets and docs screenshots that look alike on purpose.
    static func isProjectFolder(_ url: URL) -> Bool {
        if ["xcassets", "appiconset", "imageset", "xcodeproj"].contains(url.pathExtension) { return true }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        return [".git", "Package.swift", "package.json", "pubspec.yaml", "Cargo.toml"].contains {
            FileManager.default.fileExists(atPath: url.appending(path: $0).path)
        }
    }

    /// A downscaled thumbnail is enough for Vision and keeps large photos fast.
    static func featurePrint(_ url: URL) -> ([Float], Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixels = ((props?[kCGImagePropertyPixelWidth] as? Int) ?? 0) * ((props?[kCGImagePropertyPixelHeight] as? Int) ?? 0)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 360,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first, observation.elementType == .float else { return nil }
        let vector = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return (vector, pixels)
    }
}
