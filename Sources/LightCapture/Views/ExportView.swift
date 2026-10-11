import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct ExportView: View {
    @ObservedObject private var language = AppLanguage.shared
    let capture: Capture
    @EnvironmentObject var store: CaptureStore
    @Environment(\.dismiss) private var dismiss
    @State private var format = "png"
    @State private var scale = 1.0
    @State private var quality = 0.85
    @State private var isExporting = false
    @State private var error: String?
    private var dimensions: String {
        guard let source = CGImageSourceCreateWithURL(capture.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return "" }
        let prefix = scale == 1 ? "" : L("约 ")
        return "\(prefix)\(max(1, Int(Double(width) * scale))) × \(max(1, Int(Double(height) * scale))) px"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                if let image = capture.image {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 48, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("导出截图")).font(.system(size: 16, weight: .semibold))
                    Text(dimensions).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("文件格式")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    formatOption("png", title: "PNG", detail: L("无损 · 保留透明"), symbol: "photo")
                    formatOption("jpg", title: "JPEG", detail: L("压缩 · 方便分享"), symbol: "photo.badge.arrow.down")
                }
            }
            HStack {
                Text(L("图片尺寸")).font(.system(size: 12))
                Spacer()
                Menu {
                    Button(L("原始尺寸")) { scale = 1 }
                    Button("75%") { scale = 0.75 }
                    Button("50%") { scale = 0.5 }
                    Button("25%") { scale = 0.25 }
                } label: {
                    HStack(spacing: 8) {
                        Text(scale == 1 ? L("原始尺寸") : "\(Int(scale * 100))%")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if format == "jpg" {
                VStack(spacing: 8) {
                    HStack {
                        Text(L("压缩质量")).font(.system(size: 12))
                        Spacer()
                        Text("\(Int(quality * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Slider(value: $quality, in: 0.1...1).controlSize(.small)
                }
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Text(L("原图将保留")).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered).controlSize(.regular)
                Button(L("导出…")) { export() }.keyboardShortcut(.defaultAction)
                    .buttonStyle(.bordered).controlSize(.regular)
            }.tint(.secondary)
        }.disabled(isExporting).overlay { if isExporting { ProgressView() } }
            .interactiveDismissDisabled(isExporting)
            .padding(22).frame(width: 350).tint(CaptureStyle.accent)
            .environment(\.locale, Locale(identifier: AppLanguage.code))
    }
    private func formatOption(_ value: String, title: String, detail: String, symbol: String) -> some View {
        Button { format = value } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: format == value ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12)).foregroundStyle(format == value ? CaptureStyle.accent : Color.secondary.opacity(0.3))
                }
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(format == value ? 0.045 : 0.02), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(format == value ? 0.12 : 0.045)))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(SpringButtonStyle()).accessibilityLabel("\(title)，\(detail)")
            .accessibilityAddTraits(format == value ? [.isSelected] : [])
    }
    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == "png" ? .png : .jpeg]
        panel.nameFieldStringValue = capture.url.deletingPathExtension().lastPathComponent + "." + format
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url != capture.url else { error = L("请选择新文件名，保留原始截图。"); return }
        guard !isExporting else { return }
        isExporting = true
        let selectedFormat = format, selectedScale = scale, selectedQuality = quality
        Task { @MainActor in
            defer { isExporting = false }
            do {
                let result = try await ImageOutput.export(sourceURL: capture.url, destinationURL: url, scale: selectedScale, format: selectedFormat, quality: selectedQuality)
                store.message = L("已导出 %@ × %@ 的 %@ 图片。", String(result.width), String(result.height), selectedFormat.uppercased())
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
