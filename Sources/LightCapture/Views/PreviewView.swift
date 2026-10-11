import SwiftUI
import AppKit

struct PreviewView: View {
    let capture: Capture?
    @Binding var zoom: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let capture, let image = capture.image {
                InteractivePreview(image: image, url: capture.url, zoom: $zoom)
                    .help(L("双击缩放；拖动或滚动平移；⌘滚动缩放"))
                    .id(capture.id)
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                CaptureIllustration().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: capture?.id)
    }
}

private struct InteractivePreview: NSViewRepresentable {
    let image: NSImage
    let url: URL
    @Binding var zoom: Double
    func makeNSView(context: Context) -> PreviewCanvas { PreviewCanvas() }
    func updateNSView(_ view: PreviewCanvas, context: Context) {
        view.onZoom = { zoom = $0 }
        view.configure(image: image, url: url, zoom: zoom)
    }
}

struct CaptureIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Image(systemName: "viewfinder")
            .font(.system(size: 56, weight: .ultraLight))
            .foregroundStyle(Color.secondary.opacity(0.45))
            .opacity(breathing ? 0.85 : 0.55)
            .scaleEffect(breathing ? 1.02 : 1)
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
            .onAppear { breathing = !reduceMotion }
            .onChange(of: reduceMotion) { _, reduced in breathing = !reduced }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathing)
    }
}
