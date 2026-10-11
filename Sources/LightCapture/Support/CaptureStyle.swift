import SwiftUI

enum CaptureStyle {
    static let accent = Color(red: 0.92, green: 0.36, blue: 0.25)
    static let gradient = LinearGradient(colors: [Color(red: 0.98, green: 0.53, blue: 0.32), accent], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct CaptureAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let shortcut: String
    let key: KeyEquivalent
    static var all: [CaptureAction] { [
        CaptureAction(id: "region", title: L("区域截图"), detail: L("自由框选，精准捕捉"), symbol: "crop", shortcut: "⌘ ⇧ 2", key: "2"),
        CaptureAction(id: "window", title: L("窗口截图"), detail: L("选中窗口，完整留存"), symbol: "macwindow", shortcut: "⌘ ⇧ 3", key: "3"),
        CaptureAction(id: "full", title: L("全屏截图"), detail: L("记录整个主屏幕"), symbol: "display", shortcut: "⌘ ⇧ 4", key: "4")
    ] }
}

struct CaptureTile: View {
    let action: CaptureAction
    let compact: Bool
    let perform: () -> Void
    @State private var hovered = false
    private var primary: Bool { action.id == "region" }
    var body: some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                HStack {
                    Image(systemName: action.symbol).font(.system(size: compact ? 20 : 23, weight: .medium))
                    Spacer()
                    if !compact {
                        Text(action.shortcut).font(.system(size: 10, weight: .medium, design: .monospaced)).opacity(0.65)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(action.title).font(.system(size: compact ? 12 : 14, weight: .semibold))
                    if !compact { Text(action.detail).font(.system(size: 11)).opacity(0.7) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(compact ? 14 : 20)
                .foregroundStyle(primary ? Color.white : Color.primary)
                .background {
                    if primary { RoundedRectangle(cornerRadius: 16).fill(CaptureStyle.gradient) }
                    else { RoundedRectangle(cornerRadius: 16).fill(.regularMaterial) }
                }
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(primary ? Color.white.opacity(0.15) : Color.primary.opacity(hovered ? 0.16 : 0.07)))
                .shadow(color: primary ? CaptureStyle.accent.opacity(hovered ? 0.23 : 0.12) : .clear, radius: 12, y: 6)
                .offset(y: hovered ? -2 : 0)
        }.buttonStyle(.plain).onHover { hovered = $0 }.animation(.easeOut(duration: 0.16), value: hovered)
    }
}
