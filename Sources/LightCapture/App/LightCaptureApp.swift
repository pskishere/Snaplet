import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusPanelController?
    private weak var captureStore: CaptureStore?
    private let shortcuts = GlobalShortcuts()
    func configureMenu(store: CaptureStore) {
        captureStore = store
        guard statusController == nil else { return }
        statusController = StatusPanelController(store: store)
        shortcuts.action = { [weak self, weak store] id in
            guard let store, !store.busy else { return }
            self?.statusController?.dismissForCapture()
            store.capture([1: "region", 2: "window", 3: "full"][id] ?? "region")
        }
        if !shortcuts.register() { store.shortcutError = L("全局快捷键被占用，前台快捷键仍可使用。") }
    }
    func toggleQuickPanel() { statusController?.togglePanel() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        UpdateService.shared.start()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showLibrary()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        captureStore?.confirmClosingAnnotations() == false ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { shortcuts.unregister() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct LightCaptureApp: App {
    @ObservedObject private var language = AppLanguage.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = CaptureStore()
    var body: some Scene {
        Window("Snaplet", id: "main") {
            ContentView().environmentObject(store).background(InitialWindowSize())
                .onAppear { delegate.configureMenu(store: store) }
        }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 850, height: 620)
            .commands {
                CommandGroup(after: .appInfo) {
                    Button(L("检查更新…")) { UpdateService.shared.check() }
                    Button(L("权限与更新")) { store.openSystemSettings() }
                }
                CommandMenu(L("截图")) {
                    Button(L("快速预览")) { store.previewSelected() }.keyboardShortcut(.space, modifiers: [])
                        .disabled(store.selected == nil)
                    Divider()
                    Button(L("快速截图面板")) { delegate.toggleQuickPanel() }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
    }
}

private struct InitialWindowSize: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ nsView: SizingView, context: Context) { }

    final class SizingView: NSView {
        private var configured = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !configured else { return }
            configured = true
            window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.collectionBehavior.remove(.canJoinAllSpaces)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            DispatchQueue.main.async {
                if !window.setFrameUsingName("SnapletMainWindow") {
                    window.setContentSize(NSSize(width: 850, height: 620))
                    window.center()
                }
                window.setFrameAutosaveName("SnapletMainWindow")
            }
        }
    }
}
