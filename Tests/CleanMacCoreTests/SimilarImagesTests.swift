import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CleanMacCore

struct SimilarImagesTests {
    /// A scene of coloured shapes; `variant` changes the scene completely, `scale` and `quality` only re-render it.
    func writeImage(_ url: URL, variant: Int, size: Int, quality: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let s = CGFloat(size)
        if variant == 0 {
            ctx.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: s * 0.55, y: s * 0.55, width: s * 0.3, height: s * 0.3))
            ctx.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.3))
        } else {
            for i in 0..<12 {
                ctx.setFillColor(CGColor(red: Double(i % 2), green: 0.1 * Double(i), blue: 0.3, alpha: 1))
                ctx.fill(CGRect(x: CGFloat(i) * s / 12, y: 0, width: s / 12, height: s))
            }
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(s / 30)
            ctx.strokeEllipse(in: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.5))
        }
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func `groups re-saved copies, keeps different photos apart, selects nothing`() async throws {
        let home = try TempDir()
        let pictures = home.url.appending(path: "Pictures")
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        try writeImage(pictures.appending(path: "beach.jpg"), variant: 0, size: 1600, quality: 0.95)
        try writeImage(pictures.appending(path: "beach small.jpg"), variant: 0, size: 1200, quality: 0.85)
        try writeImage(pictures.appending(path: "stripes.jpg"), variant: 1, size: 1600, quality: 0.95)

        // A code project's assets are left alone.
        try writeImage(pictures.appending(path: "App/Assets.xcassets/icon.jpg"), variant: 0, size: 1600, quality: 0.9)
        try FileManager.default.createDirectory(at: pictures.appending(path: "App/.git"), withIntermediateDirectories: true)
        try writeImage(pictures.appending(path: "App/docs/shot.jpg"), variant: 0, size: 1600, quality: 0.9)
        let finder = SimilarImages(home: home.url, roots: [pictures], threshold: 0.28, limit: 100)
        let groups = await finder.find()
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.items.map(\.title) == ["beach.jpg", "beach small.jpg"])   // highest resolution first
        #expect(group.items.allSatisfy { !$0.isSelected })
    }
}
