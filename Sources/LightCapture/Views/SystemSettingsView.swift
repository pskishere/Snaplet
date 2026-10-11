import SwiftUI
import AppKit

struct SystemSettingsView: View {
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject private var permissions = ScreenPermissionService.shared
    @ObservedObject private var updates = UpdateService.shared
    @State private var confirmRestart = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                WindowControls().frame(width: 60, height: 26)
                Text(L("权限与更新")).font(.system(size: 17, weight: .semibold))
                Spacer()
            }.frame(height: 36).padding(.leading, -8)
            VStack(alignment: .leading, spacing: 12) {
                Label(L("屏幕录制权限"), systemImage: "display").font(.system(size: 13, weight: .semibold))
                Label(permissions.granted ? L("已授权") : L("未授权"), systemImage: permissions.granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(permissions.granted ? Color.green : CaptureStyle.accent).font(.system(size: 12))
                Text(L("截图需要屏幕录制权限；在系统设置中允许 Snaplet，返回后会自动检查。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if !permissions.granted {
                        Button(L("请求授权")) { permissions.request() }
                    }
                    Button(L("打开系统设置")) { permissions.openSettings() }
                    Button(L("重新检测")) { permissions.refresh() }
                }.buttonStyle(.bordered)
                HStack {
                    Text(L("权限已开启但仍无法截图时，可重新启动应用。"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(L("重新启动")) { confirmRestart = true }.buttonStyle(.plain).font(.system(size: 11))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L("软件更新"), systemImage: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("Snaplet \(updates.version)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
                Toggle(L("自动检查更新"), isOn: $updates.automaticChecks).toggleStyle(.switch).controlSize(.small)
                Text(L("更新来自 GitHub Releases，安装前会验证签名。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("检查更新…")) { updates.check() }.disabled(!updates.canCheck).buttonStyle(.bordered)
                    Spacer()
                    Button(L("查看发布记录")) { NSWorkspace.shared.open(updates.releases) }.buttonStyle(.plain).font(.system(size: 11))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 22).frame(width: 480).tint(CaptureStyle.accent)
            .ignoresSafeArea(.container, edges: .top)
            .environment(\.locale, Locale(identifier: AppLanguage.code))
            .onAppear { permissions.refresh() }
            .confirmationDialog(L("重新启动"), isPresented: $confirmRestart) {
                Button(L("重新启动")) { permissions.restart() }
                Button(L("取消"), role: .cancel) { }
            } message: { Text(L("重新启动会关闭窗口，请先保存正在编辑的标注。")) }
    }
}
