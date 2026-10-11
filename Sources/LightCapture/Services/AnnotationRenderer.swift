import AppKit
import CoreImage
import ImageIO

final class AnnotationRenderer {
    let original: CGImage
    let image: NSImage
    let size: CGSize
    private static let context = CIContext()
    private let pixelLock = NSLock()
    private var cachedPixelated: NSImage?
    private var pixelated: NSImage? {
        pixelLock.lock(); defer { pixelLock.unlock() }
        if let cachedPixelated { return cachedPixelated }
        let ci = CIImage(cgImage: original)
        guard let filtered = Self.context.createCGImage(ci.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(12, CGFloat(original.width) / 100)]), from: ci.extent) else { return nil }
        let result = NSImage(cgImage: filtered, size: size)
        cachedPixelated = result
        return result
    }
    convenience init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(original: cg)
    }
    init(original: CGImage) {
        self.original = original
        size = CGSize(width: original.width, height: original.height)
        image = NSImage(cgImage: original, size: size)
    }
    func prepareMosaic() { _ = pixelated }
    static func textSize(_ mark: AnnotationMark) -> CGSize {
        let measured = (mark.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: mark.fontSize, weight: .semibold)])
        return CGSize(width: max(12, measured.width), height: max(mark.fontSize * 1.2, measured.height))
    }
    static func bounds(_ mark: AnnotationMark) -> CGRect {
        if mark.tool == .text { return CGRect(origin: mark.points[0], size: textSize(mark)) }
        if mark.tool == .number {
            let diameter = mark.fontSize * 1.4
            return CGRect(x: mark.points[0].x - diameter / 2, y: mark.points[0].y - diameter / 2, width: diameter, height: diameter)
        }
        return mark.rect
    }
    static func path(_ mark: AnnotationMark) -> NSBezierPath {
        let p = NSBezierPath(); p.lineCapStyle = .round; p.lineJoinStyle = .round; p.lineWidth = mark.lineWidth
        switch mark.tool {
        case .rectangle: p.appendRect(mark.rect)
        case .ellipse: p.appendOval(in: mark.rect)
        case .arrow:
            let a = mark.points[0], b = mark.points[1], angle = atan2(b.y - a.y, b.x - a.x)
            let head = max(12, mark.lineWidth * 4)
            p.move(to: a); p.line(to: b)
            p.move(to: CGPoint(x: b.x - head * cos(angle - .pi / 6), y: b.y - head * sin(angle - .pi / 6)))
            p.line(to: b); p.line(to: CGPoint(x: b.x - head * cos(angle + .pi / 6), y: b.y - head * sin(angle + .pi / 6)))
        case .pen, .highlight:
            if let first = mark.points.first { p.move(to: first); for point in mark.points.dropFirst() { p.line(to: point) } }
            if mark.tool == .highlight { p.lineWidth = mark.lineWidth * 4 }
        default: break
        }
        return p
    }
    func draw(_ marks: [AnnotationMark]) {
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        for mark in marks {
            let color = AnnotationDocument.colors[mark.colorIndex]
            color.setStroke(); color.setFill()
            switch mark.tool {
            case .text:
                (mark.text as NSString).draw(at: mark.points[0], withAttributes: [.font: NSFont.systemFont(ofSize: mark.fontSize, weight: .semibold), .foregroundColor: color])
            case .mosaic:
                NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: mark.rect).addClip()
                pixelated?.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
                NSGraphicsContext.restoreGraphicsState()
            case .number:
                let rect = Self.bounds(mark); NSBezierPath(ovalIn: rect).fill()
                let text = String(mark.number) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: mark.fontSize * 0.8, weight: .bold), .foregroundColor: mark.colorIndex == 5 ? NSColor.black : NSColor.white]
                let measured = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2), withAttributes: attributes)
            case .highlight:
                color.withAlphaComponent(0.3).setStroke(); Self.path(mark).stroke()
            default: Self.path(mark).stroke()
            }
        }
    }
    func render(_ marks: [AnnotationMark]) -> CGImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: original.width, pixelsHigh: original.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let ctx = graphics.cgContext
        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(marks)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}
