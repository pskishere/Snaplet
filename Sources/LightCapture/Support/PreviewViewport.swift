import Foundation
import CoreGraphics

/// Coordinates are view points; zoom is relative to the fitted image.
struct PreviewViewport {
    var image = CGSize.zero
    var viewport = CGSize.zero
    var zoom: CGFloat = 1
    var offset = CGPoint.zero
    var fitted: CGSize {
        let factor = min(max(0, viewport.width - 32) / max(1, image.width), max(0, viewport.height - 32) / max(1, image.height))
        return CGSize(width: image.width * factor, height: image.height * factor)
    }
    var rect: CGRect {
        let size = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)
        return CGRect(x: (viewport.width - size.width) / 2 + offset.x, y: (viewport.height - size.height) / 2 + offset.y, width: size.width, height: size.height)
    }
    mutating func clamp() {
        let x = max(0, (fitted.width * zoom - viewport.width) / 2)
        let y = max(0, (fitted.height * zoom - viewport.height) / 2)
        offset.x = min(x, max(-x, offset.x))
        offset.y = min(y, max(-y, offset.y))
        if zoom == 1 { offset = .zero }
    }
    mutating func setZoom(_ value: CGFloat, anchor: CGPoint) {
        let next = min(8, max(1, value))
        let ratio = next / zoom
        let relative = CGPoint(x: anchor.x - viewport.width / 2, y: anchor.y - viewport.height / 2)
        offset = CGPoint(x: relative.x - (relative.x - offset.x) * ratio, y: relative.y - (relative.y - offset.y) * ratio)
        zoom = next
        clamp()
    }
}
