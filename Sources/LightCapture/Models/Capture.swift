import AppKit

struct Capture: Identifiable {
    let url: URL
    let date: Date
    var id: String { url.resolvingSymlinksInPath().path }
    var image: NSImage? { CaptureImageCache.shared.image(url) }
    var thumbnail: NSImage? { CaptureImageCache.shared.thumbnail(url) }
}

