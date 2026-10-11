import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement
import Combine

@MainActor final class CaptureStore: ObservableObject {
    @Published var captures: [Capture] = []
    @Published var selected: Capture?
    @Published var busy = false
    @Published var message = L("准备好，捕捉每一个瞬间。")
    @Published var error: String?
    @Published var autoCopy = true {
        didSet { preferences.set(autoCopy, forKey: "SnapletAutoCopy") }
    }
    @Published var shortcutError: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var showExport = false
    @Published var showAnnotations = false
    private var annotationSessions: [String: AnnotationWindowSession] = [:]
    private var directoryWatcher: DirectoryWatcher?
    private var refreshTask: Task<Void, Never>?
    private var fileVersions: [String: String] = [:]
    private var activation: AnyCancellable?
    private var settingsWindow: NSWindow?
    private let regionSelector = RegionSelector()
    private let quickLook = QuickLookService()
    @Published var captureDelay = 0 {
        didSet { preferences.set(captureDelay, forKey: "SnapletCaptureDelay") }
    }
    @Published var countdown = 0
    private var pendingCapture: Task<Void, Never>?
    private var restoreWindows: (() -> Void)?
    let directory: URL
    private let preferences: UserDefaults

    init(directory: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.directory = (directory ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Snaplet", isDirectory: true)).resolvingSymlinksInPath()
        autoCopy = preferences.object(forKey: "SnapletAutoCopy") as? Bool ?? true
        let delay = preferences.integer(forKey: "SnapletCaptureDelay")
        captureDelay = [0, 3, 5].contains(delay) ? delay : 0
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.reload() }
        do {
            let previous = self.directory.deletingLastPathComponent().appendingPathComponent("轻截", isDirectory: true)
            if directory == nil && FileManager.default.fileExists(atPath: previous.path), !FileManager.default.fileExists(atPath: self.directory.path) {
                try FileManager.default.moveItem(at: previous, to: self.directory)
            }
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            reload()
            directoryWatcher = DirectoryWatcher(url: self.directory) { [weak self] in
                Task { @MainActor in
                    self?.refreshTask?.cancel()
                    self?.refreshTask = Task { @MainActor [weak self] in
                        do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                        self?.reload()
                    }
                }
            }
        } catch { self.error = L("无法打开截图目录：%@", String(describing: error.localizedDescription)) }
    }

    func reload() {
        guard !busy else { return }
        let previous = selected?.id
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
            var versions: [String: String] = [:]
            let updated = files.filter { $0.pathExtension.lowercased() == "png" }.map { url -> Capture in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
                versions[url.path] = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
                return Capture(url: url, date: values?.creationDate ?? .distantPast)
            }.sorted { $0.date > $1.date }
            for (path, version) in fileVersions where versions[path] != version {
                CaptureImageCache.shared.remove(URL(fileURLWithPath: path))
            }
            guard versions != fileVersions || updated.map(\.id) != captures.map(\.id) else { return }
            fileVersions = versions
            captures = updated
            selected = captures.first { $0.id == previous } ?? captures.first
        } catch {
            message = L("无法打开截图目录：%@", error.localizedDescription)
        }
    }

    func openSystemSettings() {
        if let settingsWindow {
            if settingsWindow.isMiniaturized { settingsWindow.deminiaturize(nil) }
            settingsWindow.makeKeyAndOrderFront(nil)
        }
        else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 440), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Snaplet"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: SystemSettingsView())
            hosting.safeAreaRegions = []
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.center()
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openAnnotationWindow() {
        showAnnotations = false
        guard let selected else { return }
        if let session = annotationSessions[selected.id] {
            if session.window.isMiniaturized { session.window.deminiaturize(nil) }
            session.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 900)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1200, screen.width - 60), height: min(860, screen.height - 80)), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("标注 · Snaplet") + " · " + selected.url.lastPathComponent
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 780, height: 560)
        window.collectionBehavior = [.fullScreenPrimary]
        let session = AnnotationWindowSession(window: window, capture: selected)
        session.onClosed = { [weak self] in self?.annotationSessions.removeValue(forKey: selected.id) }
        let hosting = NSHostingView(rootView: AnnotationEditor(capture: selected, onClose: { [weak window] in window?.performClose(nil) }, document: session.document).environmentObject(self))
        hosting.safeAreaRegions = []
        window.contentView = hosting
        annotationSessions[selected.id] = session
        if !window.setFrameUsingName("SnapletAnnotationWindow") { window.center() }
        window.setFrameAutosaveName("SnapletAnnotationWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func confirmClosingAnnotations() -> Bool {
        for session in annotationSessions.values where !session.confirmDiscardOrKeep() { return false }
        return true
    }

    func delete(_ capture: Capture) {
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return }
        let previousSelection = selected?.id
        do {
            try FileManager.default.trashItem(at: capture.url, resultingItemURL: nil)
            CaptureImageCache.shared.remove(capture.url)
            captures.remove(at: index)
            if previousSelection == capture.id {
                selected = captures.isEmpty ? nil : captures[min(index, captures.count - 1)]
            } else if let previousSelection {
                selected = captures.first { $0.id == previousSelection } ?? captures.first
            }
            message = L("截图已移到废纸篓。")
        } catch {
            message = L("删除失败：%@", String(describing: error.localizedDescription))
        }
    }

    func capture(_ mode: String) {
        guard !busy else { return }
        ScreenPermissionService.shared.refresh()
        guard ScreenPermissionService.shared.granted else {
            openSystemSettings()
            return
        }
        busy = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = directory.appendingPathComponent("截图_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(4)).png")
        let windows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
        let previousKeyWindow = NSApp.keyWindow
        restoreWindows = {
            windows.forEach { $0.orderFront(nil) }
            previousKeyWindow?.makeKeyAndOrderFront(nil)
            if !windows.isEmpty { NSApp.activate(ignoringOtherApps: true) }
        }
        windows.forEach { $0.orderOut(nil) }
        message = mode == "full" ? L("正在截取屏幕…") : L("拖动选择区域或点击窗口，按 Esc 取消。")
        let delay = captureDelay
        pendingCapture = Task {
            do {
                if delay > 0 {
                    for remaining in stride(from: delay, through: 1, by: -1) {
                        self.countdown = remaining
                        self.message = L("%@ 秒后开始截图，可在菜单栏取消。", String(describing: remaining))
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
                self.countdown = 0
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch { return }
            self.pendingCapture = nil
            self.message = mode == "full" ? L("正在截取屏幕…") : L("拖动选择区域或点击窗口，按 Esc 取消。")
            if mode == "region" {
                self.regionSelector.select { region in
                    guard let region else { self.finishCancelledSelection(); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.runCapture(mode, url: url, region: region) }
                }
            } else {
                self.runCapture(mode, url: url, region: nil)
            }
        }
    }

    private func finishCancelledSelection() {
        busy = false
        restoreWindows?()
        restoreWindows = nil
        message = L("截图已取消。")
    }

    private func runCapture(_ mode: String, url: URL, region: CGRect?) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            var args = ["-x", "-t", "png"]
            if let region {
                args += ["-R", "\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))"]
            }
            if mode == "window" { args += ["-i", "-w"] }
            if mode == "full" { args += ["-m"] }
            process.arguments = args + [url.path]
            process.terminationHandler = { completed in
                let status = completed.terminationStatus
                Task { @MainActor in
                    self.busy = false
                    if NSImage(contentsOf: url) != nil {
                        self.restoreWindows = nil
                        let capture = Capture(url: url, date: Date())
                        self.captures.insert(capture, at: 0)
                        self.selected = capture
                        if self.autoCopy { self.copy() }
                        self.message = self.autoCopy ? L("截图已保存，并复制到剪贴板。") : L("截图已保存到「图片 / Snaplet」。")
                    } else {
                        self.restoreWindows?()
                        self.restoreWindows = nil
                        self.message = L("截图已取消或未完成。")
                        if status != 0 && (mode == "full" || !CGPreflightScreenCaptureAccess()) {
                            self.error = L("系统未能完成截图。若已开启Snaplet的屏幕录制权限，请关闭再开启该开关，然后重新打开Snaplet。")
                        }
                    }
                }
            }
            do { try process.run() }
            catch {
                self.busy = false
                self.restoreWindows?()
                self.restoreWindows = nil
                self.error = L("无法启动截图：%@", String(describing: error.localizedDescription))
            }
    }

    func cancelCountdown() {
        guard pendingCapture != nil else { return }
        pendingCapture?.cancel()
        pendingCapture = nil
        countdown = 0
        busy = false
        restoreWindows?()
        restoreWindows = nil
        message = L("已取消延时截图。")
    }

    func copy() {
        guard let image = selected?.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        message = L("已复制，可以直接粘贴。")
    }

    func previewSelected() {
        guard let selected else { return }
        quickLook.show(selected.url)
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                message = L("请在登录项设置中允许 Snaplet。")
            }
        } catch { message = L("登录启动设置失败：%@", String(describing: error.localizedDescription)) }
    }

    func saveAs() {
        guard let capture = selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = capture.url.lastPathComponent
        if panel.runModal() == .OK, let destination = panel.url, destination != capture.url {
            do {
                let data = try Data(contentsOf: capture.url)
                try data.write(to: destination, options: .atomic)
                message = L("已保存到 %@。", String(describing: destination.lastPathComponent))
            } catch { self.error = L("保存失败：%@", String(describing: error.localizedDescription)) }
        }
    }
}

