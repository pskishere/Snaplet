import SwiftUI
import AppKit

struct HistoryStrip: View {
    @ObservedObject private var language = AppLanguage.shared
    @EnvironmentObject var store: CaptureStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("最近捕捉")).font(.system(size: 11, weight: .semibold))
                Text(L("%@ 张截图", String(describing: store.captures.count))).font(.system(size: 10)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: true, vertical: false)
            if store.captures.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 22, weight: .light))
                    Text(L("你的第一张截图，即将出现在这里")).font(.system(size: 11))
                }.foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(store.captures) { capture in
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { store.selected = capture }
                            } label: {
                                VStack(spacing: 6) {
                                    if let image = capture.thumbnail {
                                        let ratio = image.size.width / max(image.size.height, 1)
                                        let width = min(88, 58 * ratio)
                                        Image(nsImage: image).resizable()
                                            .frame(width: width, height: width / max(ratio, 0.001))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .padding(2)
                                            .overlay {
                                                if capture.id == store.selected?.id {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .strokeBorder(CaptureStyle.accent, lineWidth: 1)
                                                        .matchedGeometryEffect(id: "selection", in: selection)
                                                }
                                            }
                                            .frame(width: 88, height: 58)
                                    }
                                    HStack(spacing: 4) {
                                        if capture.id == store.selected?.id {
                                            Circle().fill(CaptureStyle.accent).frame(width: 3, height: 3)
                                        }
                                        Text(capture.date, format: .dateTime.hour().minute())
                                            .font(.system(size: 9, weight: capture.id == store.selected?.id ? .medium : .regular, design: .monospaced))
                                    }.foregroundStyle(capture.id == store.selected?.id ? CaptureStyle.accent : .secondary)
                                }.padding(.vertical, 4)
                            }.buttonStyle(HistoryThumbnailStyle()).help(capture.url.lastPathComponent)
                                .contextMenu {
                                    Button(L("在 Finder 中显示"), systemImage: "folder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([capture.url])
                                    }
                                    Divider()
                                    Button(L("移到废纸篓"), systemImage: "trash", role: .destructive) {
                                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.delete(capture) }
                                    }
                                }
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.92)))
                                .onDrag { NSItemProvider(contentsOf: capture.url) ?? NSItemProvider(object: capture.url as NSURL) }
                                .overlay(alignment: .topTrailing) {
                                        let imageSize = capture.thumbnail?.size ?? NSSize(width: 88, height: 58)
                                        let ratio = imageSize.width / max(imageSize.height, 1)
                                        let imageWidth = min(88, 58 * ratio)
                                        let imageHeight = imageWidth / max(ratio, 0.001)
                                        let inset = (88 - imageWidth) / 2 + 3
                                        let topInset = 4 + (58 - imageHeight) / 2 + 3
                                        Button {
                                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.delete(capture) }
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                                                .foregroundStyle(.secondary).frame(width: 16, height: 16)
                                                .background(.regularMaterial, in: Circle())
                                                .overlay(Circle().strokeBorder(.primary.opacity(0.1)))
                                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                                .contentShape(Circle())
                                        }.buttonStyle(.plain).help(L("移到废纸篓"))
                                            .accessibilityLabel(L("删除这张截图"))
                                            .offset(x: -inset, y: topInset)
                                }

                        }
                    }.padding(.horizontal, 2)
                        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: store.captures.map(\.id))
                }
            }
        }.padding(.horizontal, 26).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

private struct HistoryThumbnailStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering ? 0.025 : 0)
            .offset(y: hovering && !reduceMotion ? -2 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
