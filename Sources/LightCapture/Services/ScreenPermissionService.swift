import AppKit
import CoreGraphics
import Combine

@MainActor final class ScreenPermissionService: ObservableObject {
    static let shared = ScreenPermissionService()
    @Published private(set) var granted = false
    private var restartObserver: NSObjectProtocol?
    private var activation: AnyCancellable?
    private init() {
        refresh()
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        let value = CGPreflightScreenCaptureAccess()
        if value != granted { granted = value }
    }
    func request() {
        guard !granted else { return }
        _ = CGRequestScreenCaptureAccess()
        refresh()
        if !granted { openSettings() }
    }
    func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func restart() {
        if let restartObserver { NotificationCenter.default.removeObserver(restartObserver) }
        restartObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$1\"", "snaplet-restart", Bundle.main.bundleURL.path]
            try? process.run()
        }
        NSApp.terminate(nil)
        // terminate returns only when quitting was cancelled.
        if let restartObserver { NotificationCenter.default.removeObserver(restartObserver); self.restartObserver = nil }
    }
}
