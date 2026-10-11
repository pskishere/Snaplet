import AppKit
import CryptoKit

@MainActor final class AnnotationWindowSession: NSObject, NSWindowDelegate {
    let document = AnnotationDocument()
    let window: NSWindow
    private let draftURL: URL
    var onClosed: (() -> Void)?

    init(window: NSWindow, capture: Capture, draftsDirectory: URL? = nil) {
        self.window = window
        let digest = SHA256.hash(data: Data(capture.id.utf8)).map { String(format: "%02x", $0) }.joined()
        draftURL = (draftsDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snaplet/AnnotationDrafts")).appendingPathComponent("\(digest).json")
        super.init()
        if let data = try? Data(contentsOf: draftURL), let marks = try? JSONDecoder().decode([AnnotationMark].self, from: data) {
            document.marks = marks
        }
        document.onOutput = { [weak self] in self?.removeDraft() }
        window.delegate = self
    }
    func confirmDiscardOrKeep() -> Bool {
        guard !document.isProcessing else { NSSound.beep(); return false }
        document.commitText?()
        guard document.hasUnsavedChanges else { removeDraft(); return true }
        let alert = NSAlert()
        alert.messageText = L("标注尚未保存")
        alert.informativeText = L("可保留草稿，下次标注这张截图时继续编辑。")
        alert.addButton(withTitle: L("保留草稿"))
        alert.addButton(withTitle: L("丢弃更改"))
        alert.addButton(withTitle: L("取消"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do {
                try saveDraft()
                return true
            } catch {
                let failure = NSAlert(); failure.messageText = L("保存失败：%@", error.localizedDescription); failure.runModal()
                return false
            }
        case .alertSecondButtonReturn: removeDraft(); return true
        default: return false
        }
    }
    func saveDraft() throws {
        try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(document.marks).write(to: draftURL, options: .atomic)
    }
    private func removeDraft() { try? FileManager.default.removeItem(at: draftURL) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { confirmDiscardOrKeep() }
    func windowWillClose(_ notification: Notification) { onClosed?() }
}
