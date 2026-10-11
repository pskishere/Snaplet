import AppKit
import SwiftUI
import Combine

@MainActor final class StatusPanelController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = QuickPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var mainWindow: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var countdownObservation: AnyCancellable?

    init(store: CaptureStore) {
        super.init()
        mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "main" } ?? NSApp.windows.first { $0.title == "Snaplet" && !($0 is NSPanel) }
        let menuIcon = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snaplet")
        menuIcon?.isTemplate = true
        item.button?.image = menuIcon
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.toolTip = L("Snaplet · 快速截图")
        countdownObservation = store.$countdown.sink { [weak self] remaining in
            guard let self else { return }
            self.item.length = remaining > 0 ? NSStatusItem.variableLength : NSStatusItem.squareLength
            self.item.button?.title = remaining > 0 ? " \(remaining)" : ""
            self.item.button?.toolTip = remaining > 0 ? L("%@ 秒后截图 · 点击可取消", String(describing: remaining)) : L("Snaplet · 快速截图")
            if remaining == 0 && store.busy { self.closePanel() }
        }
        panel.title = L("Snaplet 快速截图")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let content = CaptureMenu(openLibraryAction: { [weak self] in self?.showLibrary() }, closePanelAction: { [weak self] in self?.closePanel() }).environmentObject(store)
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible {
                self.closePanel()
                return nil
            }
            if event.type != .keyDown && event.window !== self.panel && event.window !== self.item.button?.window {
                self.closePanel()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    @objc func togglePanel() {
        if panel.isVisible { closePanel(); return }
        guard let button = item.button, let statusWindow = button.window else { return }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = statusWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.contentView?.fittingSize ?? NSSize(width: 282, height: 220)
        panel.setContentSize(size)
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 6))
        panel.makeKeyAndOrderFront(nil)
    }

    func dismissForCapture() { closePanel() }

    private func closePanel() { panel.orderOut(nil) }

    func showLibrary() {
        closePanel()
        mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "main" } ?? mainWindow
        if mainWindow?.isMiniaturized == true { mainWindow?.deminiaturize(nil) }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}

private final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
