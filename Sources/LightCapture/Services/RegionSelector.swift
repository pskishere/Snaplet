import AppKit

@MainActor final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?
    func select(_ completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.finished = { [weak self, weak window] rect in
                guard let window else { return }
                let screenRect = rect.map { window.convertToScreen($0) }
                let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
                let quartzRect = screenRect.map { CGRect(x: $0.minX, y: primaryTop - $0.maxY, width: $0.width, height: $0.height) }
                self?.finish(quartzRect)
            }
            window.contentView = view
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finish(_ rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let action = completion
        completion = nil
        action?(rect)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var finished: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var selection = NSRect.zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        finished?(selection.width >= 4 && selection.height >= 4 ? selection : nil)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finished?(nil) } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.systemOrange.setStroke()
            let path = NSBezierPath(rect: selection)
            path.lineWidth = 2
            path.stroke()
        }
        let label = selection.isEmpty ? L("拖动选择截图区域 · Esc 取消") : "\(Int(selection.width)) × \(Int(selection.height))"
        (label as NSString).draw(at: NSPoint(x: 24, y: bounds.height - 48), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 16, weight: .semibold)])
    }
}
