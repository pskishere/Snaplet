import AppKit
import SwiftUI

enum SnapletBrand {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "SnapletLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snaplet")!
    }()

    static var statusImage: NSImage {
        let source = self.image
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            source.draw(in: NSRect(x: -1, y: -1, width: 26, height: 26), from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Snaplet"
        return image
    }
}

struct SnapletLogo: View {
    let size: CGFloat
    var body: some View {
        Image(nsImage: SnapletBrand.image).resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityLabel("Snaplet Logo")
    }
}
