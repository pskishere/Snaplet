import XCTest
import AppKit
import ImageIO
@testable import LightCapture

final class RegressionTests: XCTestCase {
    func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnapletTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }
    func writeImage(_ url: URL, width: Int = 200, height: Int = 100) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
    }
    @MainActor func testPreferencesAndExternalFileChanges() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let suite = "SnapletTests-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let a = root.appendingPathComponent("a.png"), b = root.appendingPathComponent("b.png")
        try writeImage(a); try writeImage(b)
        let store = CaptureStore(directory: root, preferences: preferences)
        store.autoCopy = false; store.captureDelay = 5
        let restarted = CaptureStore(directory: root, preferences: preferences)
        XCTAssertFalse(restarted.autoCopy); XCTAssertEqual(restarted.captureDelay, 5)
        store.selected = store.captures.first { $0.id == a.resolvingSymlinksInPath().path }
        let chosen = try XCTUnwrap(store.selected, "files=\(store.captures.map { $0.url.path }), target=\(a.path)")
        let cached = try XCTUnwrap(chosen.image)
        let thumbnail = try XCTUnwrap(chosen.thumbnail)
        try writeImage(a, width: 500)
        store.reload()
        XCTAssertEqual(store.selected?.id, a.resolvingSymlinksInPath().path)
        XCTAssertFalse(store.selected!.image === cached)
        XCTAssertFalse(store.selected!.thumbnail === thumbnail)
        XCTAssertEqual(store.selected!.image?.representations.first?.pixelsWide, 500)
        try FileManager.default.removeItem(at: a)
        store.reload(); XCTAssertEqual(store.captures.count, 1); XCTAssertEqual(store.selected?.id, b.resolvingSymlinksInPath().path)
    }
    @MainActor func testDirectoryWatcherAddsFiles() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let suite = "SnapletTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!; defer { defaults.removePersistentDomain(forName: suite) }
        let store = CaptureStore(directory: root, preferences: defaults)
        try writeImage(root.appendingPathComponent("new.png"))
        for _ in 0..<30 {
            if store.captures.count == 1 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(store.captures.count, 1)
    }
    @MainActor func testDraftRestorationAndOutputCleanup() async throws {
        _ = NSApplication.shared
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let capture = Capture(url: root.appendingPathComponent("source.png"), date: Date())
        let session = AnnotationWindowSession(window: NSWindow(), capture: capture, draftsDirectory: root)
        session.document.add(session.document.makeMark(at: CGPoint(x: 10, y: 10)))
        XCTAssertTrue(session.document.hasUnsavedChanges)
        try session.saveDraft()
        let restored = AnnotationWindowSession(window: NSWindow(), capture: capture, draftsDirectory: root)
        XCTAssertEqual(restored.document.marks, session.document.marks)
        XCTAssertTrue(restored.document.hasUnsavedChanges)
        restored.document.acceptOutput()
        XCTAssertFalse(restored.document.hasUnsavedChanges)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        try session.saveDraft()
        let erased = AnnotationWindowSession(window: NSWindow(), capture: capture, draftsDirectory: root)
        erased.document.marks.removeAll()
        XCTAssertTrue(erased.windowShouldClose(erased.window))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    @MainActor func testAsynchronousOutputsPreserveDimensions() async throws {
        let root = try workspace(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        try writeImage(source)
        let exported = try await ImageOutput.export(sourceURL: source, destinationURL: root.appendingPathComponent("scaled.jpg"), scale: 0.5, format: "jpg", quality: 0.8)
        XCTAssertEqual(exported.width, 100); XCTAssertEqual(exported.height, 50)
        let renderer = AnnotationRenderer(url: source)!
        let document = AnnotationDocument()
        var mark = document.makeMark(at: CGPoint(x: 20, y: 20)); mark.points[1] = CGPoint(x: 80, y: 60)
        let annotated = try await ImageOutput.annotate(original: renderer.original, marks: [mark], destinationURL: nil)
        XCTAssertEqual(annotated.width, 200); XCTAssertEqual(annotated.height, 100)
        XCTAssertNotNil(NSImage(data: annotated.data))
        XCTAssertTrue(document.undoStates.isEmpty)
    }
}
