import SwiftUI
import AppKit

/// Native macOS traffic lights hosted in the application's header.
struct WindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ view: ControlsView, context: Context) { view.configureWindow() }

    final class ControlsView: NSView {
        private var buttons: [NSButton] = []
        override init(frame: NSRect) {
            super.init(frame: frame)
            for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
                button.target = self
                button.action = #selector(performWindowAction(_:))
                button.tag = index
                addSubview(button)
                buttons.append(button)
            }
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }
        func configureWindow() {
            guard let window else { return }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
            needsLayout = true
        }
        override func layout() {
            super.layout()
            for (index, button) in buttons.enumerated() {
                button.setFrameOrigin(NSPoint(x: CGFloat(index) * 22, y: (bounds.height - button.frame.height) / 2))
            }
        }
        @objc private func performWindowAction(_ sender: NSButton) {
            switch sender.tag {
            case 0: window?.performClose(nil)
            case 1: window?.miniaturize(nil)
            default:
                if NSEvent.modifierFlags.contains(.option) { window?.performZoom(nil) }
                else { window?.toggleFullScreen(nil) }
            }
        }
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
