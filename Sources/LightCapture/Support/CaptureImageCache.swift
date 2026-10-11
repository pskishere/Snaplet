import AppKit
import ImageIO

/// Screenshot files are immutable; entries are removed when a capture is deleted.
final class CaptureImageCache {
    static let shared = CaptureImageCache()
    private let originals = NSCache<NSURL, NSImage>()
    private let thumbnails = NSCache<NSURL, NSImage>()
    private init() {
        originals.countLimit = 4
        originals.totalCostLimit = 128 * 1024 * 1024
        thumbnails.countLimit = 300
        thumbnails.totalCostLimit = 16 * 1024 * 1024
    }
    func image(_ url: URL) -> NSImage? {
        if let cached = originals.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        let rep = image.representations.first
        let cost = max(1, rep?.pixelsWide ?? Int(image.size.width)) * max(1, rep?.pixelsHigh ?? Int(image.size.height)) * 4
        originals.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }
    func thumbnail(_ url: URL) -> NSImage? {
        if let cached = thumbnails.object(forKey: url as NSURL) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        return image
    }
    func remove(_ url: URL) {
        originals.removeObject(forKey: url as NSURL)
        thumbnails.removeObject(forKey: url as NSURL)
    }
}
