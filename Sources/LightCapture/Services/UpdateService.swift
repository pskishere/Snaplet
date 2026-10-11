import AppKit
import Sparkle
import Combine

private final class UpdateDiagnostics: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        NSLog("Snaplet updater: feed loaded (%ld items)", appcast.items.count)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("Snaplet updater: %@", error.localizedDescription)
    }
}

@MainActor final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    private let diagnostics = UpdateDiagnostics()
    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []
    @Published private(set) var canCheck = false
    @Published var automaticChecks = false {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticChecks {
                controller.updater.automaticallyChecksForUpdates = automaticChecks
            }
        }
    }
    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: diagnostics, userDriverDelegate: nil)
        observations.append(controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in self?.canCheck = change.newValue ?? false }
        })
        observations.append(controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in self?.automaticChecks = change.newValue ?? false }
        })
    }
    func start() { controller.startUpdater() }
    func check() { if canCheck { controller.checkForUpdates(nil) } }
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    var releases: URL { URL(string: "https://github.com/pskishere/Snaplet/releases")! }
}
