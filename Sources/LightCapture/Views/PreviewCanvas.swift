import AppKit

final class PreviewCanvas: NSView, NSDraggingSource {
    var onZoom: ((Double) -> Void)?
    private var image: NSImage?
    private var url: URL?
    private var state = PreviewViewport()
    private var dragPoint: CGPoint?
    private var dragOffset = CGPoint.zero
    private var dragging = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func configure(image: NSImage, url: URL, zoom: Double) {
        if self.url != url {
            self.url = url
            self.image = image
            state.offset = .zero
            dragPoint = nil
            dragging = false
        }
        self.image = image
        state.image = image.size
        state.viewport = bounds.size
        if abs(state.zoom - zoom) > 0.00001 {
            state.setZoom(zoom, anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        }
        state.clamp()
        redraw()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L("截图"))
        setAccessibilityValue("\(Int(state.zoom * 100))%")
    }
    override func layout() {
        super.layout()
        state.viewport = bounds.size
        state.clamp()
        redraw()
    }
    private func redraw() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = state.zoom > 4 ? .none : .high
        image.draw(in: state.rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: state.zoom > 1 ? (dragging ? .closedHand : .openHand) : .arrow)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .cursorUpdate], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func cursorUpdate(with event: NSEvent) {
        (state.zoom > 1 ? (dragging ? NSCursor.closedHand : NSCursor.openHand) : NSCursor.arrow).set()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            changeZoom(state.zoom > 1 ? 1 : 2, anchor: point)
            dragPoint = nil
            return
        }
        dragPoint = point
        dragOffset = state.offset
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        if state.zoom > 1 {
            dragging = true
            state.offset = CGPoint(x: dragOffset.x + point.x - start.x, y: dragOffset.y + point.y - start.y)
            state.clamp()
            NSCursor.closedHand.set()
            redraw()
        } else if state.rect.contains(start), hypot(point.x - start.x, point.y - start.y) > 4, let url, let image {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(state.rect, contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
            dragPoint = nil
        }
    }
    override func mouseUp(with event: NSEvent) {
        dragPoint = nil
        dragging = false
        redraw()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            changeZoom(state.zoom * pow(1.01, event.scrollingDeltaY), anchor: convert(event.locationInWindow, from: nil))
        } else if state.zoom > 1 {
            let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            state.offset.x += event.scrollingDeltaX * factor
            state.offset.y += event.scrollingDeltaY * factor
            state.clamp()
            redraw()
        } else { super.scrollWheel(with: event) }
    }
    override func magnify(with event: NSEvent) {
        changeZoom(state.zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }
    private func changeZoom(_ value: CGFloat, anchor: CGPoint) {
        state.setZoom(value, anchor: anchor)
        dragPoint = nil
        dragging = false
        onZoom?(Double(state.zoom))
        redraw()
        setAccessibilityValue("\(Int(state.zoom * 100))%")
    }
    override func keyDown(with event: NSEvent) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch event.keyCode {
        case 24, 69: changeZoom(state.zoom * 1.25, anchor: center)
        case 27, 78: changeZoom(state.zoom / 1.25, anchor: center)
        case 29, 82: changeZoom(1, anchor: center)
        case 123, 124, 125, 126:
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 100 : 30
            switch event.keyCode {
            case 123: state.offset.x += step
            case 124: state.offset.x -= step
            case 125: state.offset.y -= step
            default: state.offset.y += step
            }
            state.clamp(); redraw()
        case 53: changeZoom(1, anchor: center)
        default: super.keyDown(with: event)
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
