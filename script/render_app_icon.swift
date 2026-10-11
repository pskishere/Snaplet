import AppKit

guard CommandLine.arguments.count == 3,
      let logo = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: render_app_icon.swift logo.png output.png")
}
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let plate = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width: 0, height: -8)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
plate.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 0.85, alpha: 0.7).setStroke()
plate.lineWidth = 2
plate.stroke()
logo.draw(in: NSRect(x: 143, y: 143, width: 738, height: 738), from: .zero, operation: .sourceOver, fraction: 1)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Failed to render icon") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
