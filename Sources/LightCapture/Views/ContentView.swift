import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var language = AppLanguage.shared
    @EnvironmentObject var store: CaptureStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var copied = false
    @State private var zoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                WindowControls().frame(width: 60, height: 26).padding(.trailing, 6)
                SnapletLogo(size: 32)
                Text("Snaplet").font(.system(size: 19, weight: .semibold, design: .rounded)).tracking(-0.6)
                Spacer()
                ForEach(CaptureAction.all) { action in
                    Button { store.capture(action.id) } label: {
                        Label(action.title, systemImage: action.symbol).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 15).padding(.vertical, 10)
                            .foregroundStyle(action.id == "region" ? .white : .primary)
                            .background(action.id == "region" ? CaptureStyle.accent : Color.primary.opacity(0.05), in: Capsule())
                    }.buttonStyle(SpringButtonStyle()).keyboardShortcut(action.key, modifiers: [.command, .shift])
                        .help("\(action.title) · \(action.shortcut)").disabled(store.busy)
                        .offset(x: -6)
                }
                Menu {
                    CaptureSettingsMenu { store.capture($0) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .resizable().scaledToFit().frame(width: 18, height: 18)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(CaptureStyle.accent).frame(height: 36)
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(L("截图设置")).help(L("截图设置"))
            }.padding(.leading, 14).padding(.trailing, 24).padding(.vertical, 10)
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(store.busy ? Color.orange : CaptureStyle.accent).frame(width: 6, height: 6)
                    Text(store.countdown > 0 ? L("%@ 秒后截图", String(describing: store.countdown)) : store.busy ? L("正在捕捉…") : store.selected == nil ? L("屏幕上的灵感，随手留下") : L("已保存在这台 Mac")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if let capture = store.selected, let rep = capture.image?.representations.first {
                        Text("\(rep.pixelsWide) × \(rep.pixelsHigh)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Text("PNG").font(.system(size: 8, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(.quaternary, in: Capsule())
                    }
                }
                VStack(spacing: 0) {
                    PreviewView(capture: store.selected, zoom: $zoom)
                        if store.selected != nil {
                            HStack(spacing: 10) {
                                Button { store.previewSelected() } label: {
                                    Label(L("快速预览"), systemImage: "arrow.up.left.and.arrow.down.right")
                                }.buttonStyle(.plain).help(L("空格 · 系统快速预览"))
                                Spacer()
                                Button { zoom = max(1, zoom / 1.25) } label: {
                                    Image(systemName: "minus.magnifyingglass")
                                }.buttonStyle(.plain).disabled(zoom <= 1)

                                Slider(value: $zoom, in: 1...8).frame(width: 95).controlSize(.mini)
                                Button { zoom = min(8, zoom * 1.25) } label: {
                                    Image(systemName: "plus.magnifyingglass")
                                }.buttonStyle(.plain).disabled(zoom >= 8)
                                Menu {
                                    ForEach([100, 150, 200, 300, 400, 800], id: \.self) { percent in
                                        Button("\(percent)%") { zoom = Double(percent) / 100 }
                                    }
                                } label: {
                                    Text("\(Int(zoom * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 35)
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                Button(L("适应窗口")) { zoom = 1 }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                }.background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.055)))
                HStack(spacing: 8) {
                    Text(store.message).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    HStack(spacing: 2) {
                    Button { store.showAnnotations = true } label: {
                        Label(L("标注"), systemImage: "pencil.tip.crop.circle")
                            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 30)
                    }.buttonStyle(QuietToolbarStyle()).disabled(store.selected == nil).help(L("箭头、矩形、文字和马赛克"))
                    if let capture = store.selected, let image = capture.image {
                        ShareLink(item: capture.url, preview: SharePreview(L("Snaplet 截图"), image: Image(nsImage: image))) {
                            Label(L("分享"), systemImage: "square.and.arrow.up").padding(.horizontal, 10).frame(height: 30)
                        }.buttonStyle(QuietToolbarStyle()).help(L("系统分享"))
                    }
                    Button {
                        store.copy()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { copied = false } }
                    } label: {
                        Label(copied ? L("已复制") : L("复制"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : copied).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copied ? CaptureStyle.accent : .primary).padding(.horizontal, 10).frame(height: 30)
                    }.buttonStyle(QuietToolbarStyle()).disabled(store.selected == nil).keyboardShortcut("c", modifiers: [.command, .shift])
                    Button { store.showExport = true } label: {
                        Label(L("导出"), systemImage: "square.and.arrow.down")
                            .padding(.horizontal, 10).frame(height: 30)
                    }.buttonStyle(QuietToolbarStyle()).disabled(store.selected == nil).keyboardShortcut("s", modifiers: .command)
                    Divider().frame(height: 14).padding(.horizontal, 3)
                    Menu {
                        Button(L("快速预览 · 空格")) { store.previewSelected() }
                        Button(L("用预览打开")) {
                            if let url = store.selected?.url { NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"), configuration: NSWorkspace.OpenConfiguration()) }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 30) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24).disabled(store.selected == nil).help(L("更多操作"))
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(.primary).tint(.secondary)
                        .padding(4).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(24).frame(maxHeight: .infinity)
            HistoryStrip().frame(height: 104)
        }.frame(minWidth: 850, minHeight: 620).tint(CaptureStyle.accent)
            .environment(\.locale, Locale(identifier: AppLanguage.code))
            .ignoresSafeArea(.container, edges: .top)
            .sheet(isPresented: $store.showExport) { if let capture = store.selected { ExportView(capture: capture).environmentObject(store) } }
            .onChange(of: store.showAnnotations) { _, requested in
                if requested { store.openAnnotationWindow() }
            }
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 8)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { appeared = true } }
            .onChange(of: language.selection) { _, _ in
                if !store.busy { store.message = L("准备好，捕捉每一个瞬间。") }
            }
            .onChange(of: store.selected?.id) { _, _ in zoom = 1; copied = false }
            .alert(L("需要你的注意"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button(L("打开系统设置")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                Button(L("好的"), role: .cancel) { }
            } message: { Text(store.error ?? "") }
    }
}

struct SpringButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.94 : hovering ? 1.025 : 1)
            .offset(y: hovering && !configuration.isPressed && !reduceMotion ? -2 : 0)
            .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 5, y: 3)
            .brightness(hovering ? 0.025 : 0)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75), value: hovering)
    }
}

struct QuietToolbarStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.09 : hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}
