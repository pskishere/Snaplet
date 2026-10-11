import AppKit
import QuickLookUI

@MainActor final class QuickLookService: NSResponder, @preconcurrency QLPreviewPanelDataSource {
    private var url: URL?
    func show(_ url: URL) {
        self.url = url
        if NSApp.nextResponder !== self {
            nextResponder = NSApp.nextResponder
            NSApp.nextResponder = self
        }
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = self }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}
