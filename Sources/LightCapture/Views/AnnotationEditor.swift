import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct AnnotationEditor: View {
    @ObservedObject private var language = AppLanguage.shared
    let capture: Capture
    var onClose: (() -> Void)? = nil
    @EnvironmentObject var store: CaptureStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var document: AnnotationDocument
    @State private var renderer: AnnotationRenderer?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 12) {
            header.padding(.leading, -8)
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(AnnotationTool.allCases, id: \.self) { tool in
                        Button {
                            document.commitText?(); document.tool = tool; document.select(nil)
                        } label: {
                            HStack(spacing: 5) {
                                if tool == .text {
                                    Text(verbatim: "A").font(.system(size: 14, weight: .medium, design: .serif)).frame(width: 15)
                                } else {
                                    Image(systemName: tool.symbol)
                                }
                                Text(L(tool.rawValue))
                            }
                                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).frame(height: 30)
                                .foregroundStyle(document.tool == tool ? Color.primary : Color.secondary)
                                .background(Color.primary.opacity(document.tool == tool ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(QuietToolbarStyle()).help(tool.hint)
                    }
                }.padding(3).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 0)
                Button { document.undo() } label: { Image(systemName:"arrow.uturn.backward").frame(width:26,height:30) }
                    .disabled(document.undoStates.isEmpty).help(L("撤销 · ⌘Z")).keyboardShortcut("z")
                Button { document.redo() } label: { Image(systemName:"arrow.uturn.forward").frame(width:26,height:30) }
                    .disabled(document.redoStates.isEmpty).help(L("重做 · ⇧⌘Z")).keyboardShortcut("z", modifiers:[.command,.shift])
            }.buttonStyle(QuietToolbarStyle())
            properties
            if let renderer {
                AnnotationCanvas(document: document, renderer: renderer)
                    .background(Color.primary.opacity(0.018),in:RoundedRectangle(cornerRadius:10))
                    .clipShape(RoundedRectangle(cornerRadius:10))
            } else { Spacer(); Text(error ?? L("正在加载图片…")).foregroundStyle(.secondary); Spacer() }
            HStack {
                Text(document.tool.hint).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(L("%@ 处标注", String(describing: document.marks.count))).font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary)
                if let error { Text(error).font(.system(size:10)).foregroundStyle(.red) }
            }
        }.disabled(document.isProcessing).overlay { if document.isProcessing { ProgressView() } }
            .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 22).frame(minWidth:780,minHeight:560).tint(CaptureStyle.accent)
            .environment(\.locale, Locale(identifier: AppLanguage.code))
            .ignoresSafeArea(.container, edges: .top)
            .task {
                let url = capture.url
                let needsMosaic = document.marks.contains { $0.tool == .mosaic }
                let loaded = await Task.detached(priority: .userInitiated) {
                    let renderer = AnnotationRenderer(url: url)
                    if needsMosaic { renderer?.prepareMosaic() }
                    return renderer
                }.value
                guard !Task.isCancelled else { return }
                renderer = loaded
                if let loaded {
                    document.lineWidth = max(2, loaded.size.width / 500)
                    document.fontSize = max(16, loaded.size.width / 70)
                } else { error = L("无法读取截图") }
            }
            .onChange(of: document.tool) { _, tool in
                guard tool == .mosaic, let renderer else { return }
                document.isProcessing = true
                Task { @MainActor in
                    await Task.detached(priority: .userInitiated) { renderer.prepareMosaic() }.value
                    document.isProcessing = false
                }
            }
    }
    private var header: some View {
        HStack(spacing:10) {
            WindowControls().frame(width: 60, height: 26).padding(.trailing, 6)
            Image(systemName:"pencil.tip.crop.circle").font(.system(size:18)).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:3) {
                Text(L("标注截图")).font(.system(size:15,weight:.semibold))
            }
            Spacer()
            HStack(spacing:2) {
                Button { closeEditor() } label: { Text(L("取消")).padding(.horizontal,10).frame(height:30) }.keyboardShortcut(.cancelAction)
                Divider().frame(height:14).padding(.horizontal,3)
                Button { output(copy:false) } label: { Label(L("保存副本"),systemImage:"square.and.arrow.down").padding(.horizontal,10).frame(height:30) }.disabled(renderer == nil)
                Button { output(copy:true) } label: { Label(L("复制图片"),systemImage:"doc.on.doc").padding(.horizontal,10).frame(height:30) }.keyboardShortcut(.defaultAction).disabled(renderer == nil)
            }.font(.system(size:11,weight:.medium)).buttonStyle(QuietToolbarStyle()).padding(4)
                .background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
        }.frame(height: 40).tint(.secondary)
    }
    private var properties: some View {
        HStack(spacing:10) {
            ForEach(AnnotationDocument.colors.indices,id:\.self) { index in
                Button { document.style(color:index) } label: {
                    Circle().fill(Color(nsColor:AnnotationDocument.colors[index])).frame(width:14,height:14)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                        .padding(3).overlay(Circle().strokeBorder(document.colorIndex == index ? Color.primary.opacity(0.55) : .clear))
                }.buttonStyle(.plain).help([L("橘色"),L("黄色"),L("绿色"),L("蓝色"),L("紫色"),L("白色"),L("黑色")][index])
            }
            Divider().frame(height:16)
            Menu {
                ForEach([CGFloat(2),4,8,12],id:\.self) { width in
                    Button("\(Int(width)) px") { document.style(width:width) }
                }
            } label: { Text(L("粗细 %@ px", String(describing: Int(document.lineWidth)))).font(.system(size:10)) }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                ForEach([CGFloat(16),24,32,48,64,96],id:\.self) { size in
                    Button("\(Int(size)) px") { document.style(font:size) }
                }
            } label: { Text(L("字号 %@ px", String(describing: Int(document.fontSize)))).font(.system(size:10)) }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Button { document.deleteSelected() } label: { Label(L("删除标注"),systemImage:"trash").font(.system(size:10)).padding(.horizontal,6).frame(height:26) }
                .buttonStyle(QuietToolbarStyle()).disabled(document.selected == nil).help(L("选中标注后按 Delete 删除"))
        }.frame(height:26)
    }
    private func output(copy: Bool) {
        guard !document.isProcessing, let renderer else { return }
        document.commitText?()
        let marks = document.marks
        let url = copy ? nil : store.directory.appendingPathComponent(capture.url.deletingPathExtension().lastPathComponent + "_标注_" + UUID().uuidString + ".png")
        document.isProcessing = true
        Task { @MainActor in
            do {
                let result = try await ImageOutput.annotate(original: renderer.original, marks: marks, destinationURL: url)
                if copy {
                    let clipboard = NSPasteboard.general
                    guard let image = NSImage(data: result.data) else { throw CocoaError(.fileReadCorruptFile) }
                    clipboard.clearContents()
                    guard clipboard.writeObjects([image]) else { throw CocoaError(.fileWriteUnknown) }
                    clipboard.setData(result.data, forType: .png)
                    store.message = L("标注图片已复制，可以直接粘贴。")
                } else if let url {
                    store.reload(); store.selected = store.captures.first { $0.id == url.resolvingSymlinksInPath().path }
                    store.message = L("标注副本已保存。")
                }
                document.acceptOutput()
                document.isProcessing = false
                closeEditor()
            } catch {
                document.isProcessing = false
                self.error = L("保存失败：%@", error.localizedDescription)
            }
        }
    }
    private func closeEditor() {
        if let onClose { onClose() } else { dismiss() }
    }
}
