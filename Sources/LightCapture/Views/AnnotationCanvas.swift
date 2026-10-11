import SwiftUI
import AppKit
import Combine

struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    let renderer: AnnotationRenderer
    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(document: document, renderer: renderer) }
    func updateNSView(_ view: AnnotationCanvasView, context: Context) { view.needsDisplay = true; view.window?.invalidateCursorRects(for: view) }
}
@MainActor final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    let document: AnnotationDocument
    let renderer: AnnotationRenderer
    private var observation: AnyCancellable?
    private var draft: AnnotationMark?
    private var before: [AnnotationMark] = []
    private var start = CGPoint.zero
    private var movingID: UUID?
    private var handle: Int?
    private var editor: NSTextField?
    private var editingMark: AnnotationMark?
    private var committing = false
    private var dragging = false
    private var guideX: CGFloat?
    private var guideY: CGFloat?
    private var cursorTracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var factor: CGFloat { min(bounds.width / renderer.size.width, bounds.height / renderer.size.height) }
    var imageRect: CGRect {
        let size = CGSize(width: renderer.size.width * factor, height: renderer.size.height * factor)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    init(document: AnnotationDocument, renderer: AnnotationRenderer) {
        self.document = document; self.renderer = renderer
        super.init(frame: .zero)
        document.commitText = { [weak self] in self?.finishText() }
        observation = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        if let field = editor, let mark = editingMark {
            field.font = NSFont.systemFont(ofSize: max(1, mark.fontSize * factor), weight: .semibold)
            resizeTextEditor()
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(tracking); cursorTracking = tracking
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }
    override func flagsChanged(with event: NSEvent) { updateCursor(event) }
    private func updateCursor(_ event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from:nil)
        if let editor, editor.frame.contains(viewPoint) { NSCursor.iBeam.set(); return }
        if dragging {
            if handle != nil { resizeCursor().set() } else { NSCursor.closedHand.set() }
            return
        }
        guard imageRect.contains(viewPoint), factor > 0 else { NSCursor.arrow.set(); return }
        let point = imagePoint(event)
        if let selected = document.selected, let index = handles(selected).firstIndex(where: { hypot($0.x-point.x,$0.y-point.y) < 8/factor }) {
            resizeCursor(index:index,mark:selected).set(); return
        }
        if !event.modifierFlags.contains(.option), document.marks.reversed().contains(where:{hit($0,at:point)}) {
            NSCursor.openHand.set(); return
        }
        switch document.tool {
        case .select: NSCursor.arrow.set()
        case .text: NSCursor.iBeam.set()
        case .number: NSCursor.pointingHand.set()
        default: NSCursor.crosshair.set()
        }
    }
    private func resizeCursor(index: Int? = nil, mark: AnnotationMark? = nil) -> NSCursor {
        if (mark ?? document.selected)?.tool == .arrow { return .crosshair }
        return ((index ?? handle ?? 0) % 2 == 0) ? Self.resizeDiagonalDown : Self.resizeDiagonalUp
    }
    private static let resizeDiagonalDown = diagonalCursor(up:false)
    private static let resizeDiagonalUp = diagonalCursor(up:true)
    private static func diagonalCursor(up: Bool) -> NSCursor {
        let image = NSImage(size:NSSize(width:24,height:24),flipped:false) { _ in
            let path = NSBezierPath()
            let a = NSPoint(x:5,y:up ? 5 : 19), b = NSPoint(x:19,y:up ? 19 : 5)
            path.move(to:a); path.line(to:b)
            path.move(to:NSPoint(x:a.x,y:a.y+(up ? 6 : -6))); path.line(to:a); path.line(to:NSPoint(x:a.x+6,y:a.y))
            path.move(to:NSPoint(x:b.x-6,y:b.y)); path.line(to:b); path.line(to:NSPoint(x:b.x,y:b.y+(up ? -6 : 6)))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth=4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth=1.5; path.stroke()
            return true
        }
        return NSCursor(image:image,hotSpot:NSPoint(x:12,y:12))
    }
    func imagePoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(renderer.size.width, max(0, (point.x - imageRect.minX) / factor)), y: min(renderer.size.height, max(0, (point.y - imageRect.minY) / factor)))
    }
    override func draw(_ dirtyRect: NSRect) {
        guard factor > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform(); t.translateX(by: imageRect.minX, yBy: imageRect.minY); t.concat()
        let scale = NSAffineTransform(); scale.scale(by: factor); scale.concat()
        NSBezierPath(rect: CGRect(origin: .zero, size: renderer.size)).addClip()
        var visible = document.marks.filter { $0.id != editingMark?.id }
        if let draft { visible.append(draft) }
        renderer.draw(visible)
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        let guides = NSBezierPath(); guides.lineWidth = 1 / factor
        if let guideX { guides.move(to:CGPoint(x:guideX,y:0)); guides.line(to:CGPoint(x:guideX,y:renderer.size.height)) }
        if let guideY { guides.move(to:CGPoint(x:0,y:guideY)); guides.line(to:CGPoint(x:renderer.size.width,y:guideY)) }
        guides.stroke()
        if editor == nil, let mark = document.selected {
            let rect = AnnotationRenderer.bounds(mark).insetBy(dx: -3 / factor, dy: -3 / factor)
            NSColor.controlAccentColor.setStroke()
            let outline = mark.tool == .text ? NSBezierPath(roundedRect:rect,xRadius:3/factor,yRadius:3/factor) : NSBezierPath(rect:rect)
            outline.lineWidth = 1 / factor
            if mark.tool != .text { outline.setLineDash([4 / factor, 3 / factor], count: 2, phase: 0) }
            outline.stroke()
            for point in handles(mark) {
                let r = CGRect(x: point.x - 3 / factor, y: point.y - 3 / factor, width: 6 / factor, height: 6 / factor)
                NSColor.windowBackgroundColor.setFill(); NSBezierPath(ovalIn: r).fill()
                NSColor.controlAccentColor.setStroke(); let p = NSBezierPath(ovalIn: r); p.lineWidth = 1 / factor; p.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func handles(_ mark: AnnotationMark) -> [CGPoint] {
        if mark.tool == .text || mark.tool == .number { return [] }
        if mark.tool == .arrow { return Array(mark.points.prefix(2)) }
        let r = AnnotationRenderer.bounds(mark)
        return [CGPoint(x:r.minX,y:r.minY), CGPoint(x:r.maxX,y:r.minY), CGPoint(x:r.maxX,y:r.maxY), CGPoint(x:r.minX,y:r.maxY)]
    }
    private func hit(_ mark: AnnotationMark, at point: CGPoint) -> Bool {
        let tolerance = max(6 / factor, mark.lineWidth / 2)
        switch mark.tool {
        case .arrow, .pen, .highlight:
            let limit = mark.tool == .highlight ? max(tolerance, mark.lineWidth * 2) : tolerance
            return zip(mark.points, mark.points.dropFirst()).contains { a, b in
                let dx = b.x-a.x, dy=b.y-a.y, length = dx*dx+dy*dy
                let t = length == 0 ? 0 : min(1, max(0, ((point.x-a.x)*dx+(point.y-a.y)*dy)/length))
                return hypot(point.x-a.x-t*dx, point.y-a.y-t*dy) <= limit
            }
        default: return AnnotationRenderer.bounds(mark).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
    override func mouseDown(with event: NSEvent) {
        finishText(); window?.makeFirstResponder(self)
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { document.select(nil); return }
        start = imagePoint(event); before = document.marks; movingID = nil; handle = nil; dragging = false
        if let selected = document.selected, let index = handles(selected).firstIndex(where: { hypot($0.x-start.x,$0.y-start.y) < 8 / factor }) {
            movingID = selected.id; handle = index; return
        }
        if let mark = document.marks.reversed().first(where: { hit($0, at:start) }), !event.modifierFlags.contains(.option) {
            document.select(mark.id)
            if event.clickCount == 2 && mark.tool == .text { beginText(mark) }
            else { movingID = mark.id }
            return
        }
        document.select(nil)
        if document.tool == .select { return }
        let mark = document.makeMark(at: start)
        if document.tool == .text { beginText(mark); return }
        if document.tool == .number { document.add(mark); return }
        draft = mark
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(event)
        if let id = movingID, let source = before.first(where: {$0.id == id}), let index = document.marks.firstIndex(where: {$0.id == id}) {
            guard hypot(point.x-start.x,point.y-start.y)*factor >= 3 || dragging else { return }
            dragging = true
            if handle != nil { resizeCursor().set() } else { NSCursor.closedHand.set() }
            var mark = source
            if let handle {
                if source.tool == .arrow { mark.points[handle] = point }
                else {
                    let corners = handles(source); let opposite = corners[(handle+2)%4]
                    let target = CGRect(x:min(point.x,opposite.x),y:min(point.y,opposite.y),width:max(1,abs(point.x-opposite.x)),height:max(1,abs(point.y-opposite.y)))
                    let old = source.rect
                    mark.points = source.points.map { CGPoint(x:target.minX+($0.x-old.minX)/max(old.width,1)*target.width,y:target.minY+($0.y-old.minY)/max(old.height,1)*target.height) }
                }
            } else {
                let r = AnnotationRenderer.bounds(source)
                var dx = point.x-start.x, dy = point.y-start.y
                if event.modifierFlags.contains(.shift) {
                    if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
                }
                guideX = nil; guideY = nil
                if source.tool == .text && !event.modifierFlags.contains(.option) {
                    if abs(r.midX+dx-renderer.size.width/2)*factor < 5 {
                        dx = renderer.size.width/2-r.midX; guideX = renderer.size.width/2
                    }
                    if abs(r.midY+dy-renderer.size.height/2)*factor < 5 {
                        dy = renderer.size.height/2-r.midY; guideY = renderer.size.height/2
                    }
                }
                dx = min(max(dx,-r.minX),max(0,renderer.size.width-r.maxX))
                dy = min(max(dy,-r.minY),max(0,renderer.size.height-r.maxY))
                mark.points = source.points.map { CGPoint(x:$0.x+dx,y:$0.y+dy) }
            }
            document.marks[index] = mark
        } else if var mark = draft {
            if mark.tool == .pen || mark.tool == .highlight { mark.points.append(point) }
            else {
                var end = point
                if event.modifierFlags.contains(.shift) && (mark.tool == .rectangle || mark.tool == .ellipse) {
                    let length = min(abs(point.x-start.x),abs(point.y-start.y))
                    end = CGPoint(x:start.x+(point.x>=start.x ? length : -length),y:start.y+(point.y>=start.y ? length : -length))
                }
                mark.points[1] = end
            }
            draft = mark
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if movingID != nil { document.record(before) }
        else if let mark = draft {
            if mark.tool == .pen || mark.tool == .highlight {
                if mark.points.count > 2 { document.add(mark) }
            } else if (mark.tool == .arrow && hypot(mark.points[0].x-mark.points[1].x,mark.points[0].y-mark.points[1].y)>3/factor) || (mark.rect.width>3/factor && mark.rect.height>3/factor) { document.add(mark) }
        }
        movingID = nil; handle = nil; draft = nil; dragging = false; guideX = nil; guideY = nil
        window?.invalidateCursorRects(for:self); updateCursor(event); needsDisplay = true
    }
    private func beginText(_ mark: AnnotationMark) {
        editingMark = mark
        let field = NSTextField(string: mark.text)
        let point = mark.points[0]
        let x = imageRect.minX+point.x*factor, y = imageRect.minY+point.y*factor
        field.frame = CGRect(x:x-4,y:y-3,width:100,height:mark.fontSize*factor*1.4+6)
        field.font = NSFont.systemFont(ofSize: max(1,mark.fontSize*factor),weight:.semibold)
        field.textColor = AnnotationDocument.colors[mark.colorIndex]
        field.isBordered = false; field.isBezeled = false; field.focusRingType = .none
        field.drawsBackground = true; field.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9)
        field.wantsLayer = true; field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1; field.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        field.cell?.isScrollable = false; field.cell?.wraps = false
        field.placeholderString = L("输入文字"); field.delegate = self
        addSubview(field); editor = field; resizeTextEditor(); window?.makeFirstResponder(field)
        window?.invalidateCursorRects(for:self)
        needsDisplay = true
    }
    func finishText(cancel: Bool = false) {
        guard !committing, let field = editor, var mark = editingMark else { return }
        committing = true; mark.text = field.stringValue
        editor = nil; editingMark = nil; field.delegate = nil; field.removeFromSuperview()
        if !cancel {
            if let index = document.marks.firstIndex(where: {$0.id == mark.id}) {
                let previous = document.marks
                if mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { document.marks.remove(at:index); document.selectedID = nil }
                else { document.marks[index] = mark; document.select(mark.id) }
                document.record(previous)
            } else if !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { document.add(mark) }
        }
        committing = false; window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for:self); needsDisplay = true
    }
    private func resizeTextEditor() {
        guard let field = editor, let mark = editingMark, let font = field.font else { return }
        let content = field.stringValue.isEmpty ? L("输入文字") : field.stringValue
        let measured = (content as NSString).size(withAttributes:[.font:font])
        let x = imageRect.minX+mark.points[0].x*factor-4
        let y = imageRect.minY+mark.points[0].y*factor-3
        field.frame = CGRect(x:x,y:y,width:max(24,min(max(96,measured.width+12),imageRect.maxX-x)),height:max(font.pointSize*1.3+6,measured.height+6))
    }
    func controlTextDidChange(_ obj: Notification) { resizeTextEditor() }
    func controlTextDidEndEditing(_ obj: Notification) { finishText() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(cancel:true); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finishText(); return true }
        return false
    }
    override func keyDown(with event: NSEvent) {
        if let source = document.selected, [123,124,125,126].contains(event.keyCode), let index = document.marks.firstIndex(where:{$0.id == source.id}) {
            let previous = document.marks
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let rect = AnnotationRenderer.bounds(source)
            let dx = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
            let dy = event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0
            let safeX = min(max(dx,-rect.minX),max(0,renderer.size.width-rect.maxX))
            let safeY = min(max(dy,-rect.minY),max(0,renderer.size.height-rect.maxY))
            document.marks[index].points = source.points.map { CGPoint(x:$0.x+safeX,y:$0.y+safeY) }
            document.record(previous); return
        }
        if event.keyCode == 51 || event.keyCode == 117 { document.deleteSelected(); return }
        if event.keyCode == 53 {
            if draft != nil || movingID != nil { document.marks = before; draft = nil; movingID = nil }
            dragging = false; guideX = nil; guideY = nil
            document.select(nil); window?.invalidateCursorRects(for:self); needsDisplay = true; return
        }
        super.keyDown(with:event)
    }
}
