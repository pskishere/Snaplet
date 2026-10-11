import SwiftUI
import AppKit

struct CaptureSettingsMenu: View {
    @ObservedObject private var language = AppLanguage.shared
    @EnvironmentObject var store: CaptureStore
    let capture: (String) -> Void

    var body: some View {
        Toggle(L("自动复制截图"), isOn: $store.autoCopy)
        Toggle(L("登录时启动"), isOn: Binding(get: { store.loginEnabled }, set: { store.setLoginEnabled($0) }))
        Divider()
        Menu(store.captureDelay == 0 ? L("延时 · 关闭") : L("延时 · %@ 秒", String(describing: store.captureDelay)), systemImage: "clock") {
            Picker(L("延时 · 关闭"), selection: $store.captureDelay) {
                ForEach([0, 3, 5], id: \.self) { delay in
                    Text(delay == 0 ? L("关闭") : L("%@ 秒", String(describing: delay))).tag(delay)
                }
            }.pickerStyle(.inline).labelsHidden()
        }
        if store.countdown > 0 {
            Button(L("取消倒计时"), systemImage: "xmark.circle") { store.cancelCountdown() }
        }
        Menu(L("全局快捷键"), systemImage: "keyboard") {
            Button(L("区域截图     ⌃⌥⌘2")) { capture("region") }.disabled(store.busy)
            Button(L("窗口截图     ⌃⌥⌘3")) { capture("window") }.disabled(store.busy)
            Button(L("全屏截图     ⌃⌥⌘4")) { capture("full") }.disabled(store.busy)
            if let error = store.shortcutError {
                Divider()
                Text(error)
            }
        }
        Divider()
        Picker(L("语言"), selection: $language.selection) {
            Text(L("跟随系统")).tag("system")
            ForEach(AppLanguage.supported, id: \.code) { language in
                Text(verbatim: language.name).tag(language.code)
            }
        }
        Divider()
        Button(L("权限与更新"), systemImage: "gearshape") { store.openSystemSettings() }
        Button(L("检查更新…"), systemImage: "arrow.triangle.2.circlepath") { UpdateService.shared.check() }
        Divider()
        Button(L("打开截图文件夹"), systemImage: "folder") { NSWorkspace.shared.open(store.directory) }
    }
}
