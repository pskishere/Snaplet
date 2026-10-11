import SwiftUI
import AppKit

struct CaptureMenu: View {
    @ObservedObject private var language = AppLanguage.shared
    var openLibraryAction: (() -> Void)? = nil
    var closePanelAction: (() -> Void)? = nil
    @EnvironmentObject var store: CaptureStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(spacing: 7) {
                QuickCaptureButton(title: L("区域"), symbol: "crop", prominent: true) { capture("region") }
                QuickCaptureButton(title: L("窗口"), symbol: "macwindow", prominent: false) { capture("window") }
                QuickCaptureButton(title: L("全屏"), symbol: "display", prominent: false) { capture("full") }
            }.disabled(store.busy)
            HStack {
                if store.countdown > 0 {
                    Label(L("%@ 秒后截图", String(describing: store.countdown)), systemImage: "timer").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("取消")) { store.cancelCountdown() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(CaptureStyle.accent)
                } else {
                    Label(L("自动复制"), systemImage: "doc.on.clipboard").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Toggle(L("自动复制"), isOn: $store.autoCopy).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }.padding(.horizontal, 2)
            Divider().opacity(0.7)
            recentCapture
        }.padding(14).frame(width: 282).tint(CaptureStyle.accent)
            .environment(\.locale, Locale(identifier: AppLanguage.code))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 5)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { appeared = true } }
    }

    private var header: some View {
        HStack(spacing: 9) {
            SnapletLogo(size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Snaplet").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(-0.5)
            }
            Spacer()
            Menu {
                CaptureSettingsMenu { capture($0) }
                Button(L("打开图库"), systemImage: "photo.on.rectangle") { openLibrary() }
                Divider()
                Button(L("退出 Snaplet")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22).help(L("更多选项"))
        }
    }

    private var recentCapture: some View {
        Button { openLibrary() } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.045))
                    if let image = store.captures.first?.thumbnail {
                        Image(nsImage: image).resizable().scaledToFit().padding(4)
                    } else {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 17, weight: .light)).foregroundStyle(.tertiary)
                    }
                }.frame(width: 56, height: 42).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.05)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.captures.isEmpty ? L("截图图库") : L("最近一次捕捉")).font(.system(size: 11, weight: .medium))
                    if let latest = store.captures.first {
                        Text(latest.date, format: .dateTime.month().day().hour().minute()).font(.system(size: 9)).foregroundStyle(.secondary)
                    } else { Text(L("你的截图会自动收纳在这里")).font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(SpringButtonStyle()).help(L("打开图库 · %@ 张截图", String(describing: store.captures.count)))
    }

    private func capture(_ mode: String) {
        closePanelAction?()
        dismiss()
        store.capture(mode)
    }

    private func openLibrary() {
        closePanelAction?()
        dismiss()
        if let openLibraryAction { openLibraryAction() } else { openWindow(id: "main") }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct QuickCaptureButton: View {
    let title: String
    let symbol: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }.frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(prominent ? CaptureStyle.accent : Color.primary)
                .background(prominent ? CaptureStyle.accent.opacity(hovered ? 0.16 : 0.1) : Color.primary.opacity(hovered ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? CaptureStyle.accent.opacity(0.18) : Color.primary.opacity(0.06)))
        }.buttonStyle(SpringButtonStyle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}
