import SwiftUI
import AppKit
import PluginSDK

extension AppSwitchPlugin: BuiltinPlugin {
    public var settingsTitle: String { "应用" }
    public var settingsSymbol: String { "app.badge" }
    public func makeSettings(context: PluginSettingsContext) -> AnyView {
        AnyView(AppSettings(context: context))
    }
}

private struct AppSettings: View {
    let context: PluginSettingsContext
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("按键打开或显示应用，已在前台时再次按下可隐藏。").foregroundStyle(.secondary)
                Spacer()
                Button(action: addApplication) { Label("添加应用", systemImage: "plus") }
            }.padding(.top, 14)
            if !context.enabled { Text("应用快捷切换插件已停用，可在「插件」中启用。").foregroundStyle(.orange) }
            if context.bindings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed").font(.system(size: 32))
                    Text("添加第一个应用").font(.headline)
                    Text("选择常用应用，再录入 ⌘⌥ 加字母或数字。")
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(context.bindings) { binding in
                            context.bindingRow(binding, binding.configuration["path"].map { NSWorkspace.shared.icon(forFile: $0) })
                            Divider()
                        }
                    }
                }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("多窗口、最小化和其他桌面的恢复遵循系统与目标应用的行为。").font(.caption).foregroundStyle(.secondary)
            Text("默认前缀 ⌘⌥ · 支持自定义组合 · Esc 取消录入").font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private func addApplication() {
        let picker = NSOpenPanel(); picker.title = "选择要绑定的应用"; picker.allowedContentTypes = [.applicationBundle]
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        guard picker.runModal() == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard id != Bundle.main.bundleIdentifier else { context.reportError("请通过菜单栏打开 Hotkey 设置。"); return }
        guard !context.bindings.contains(where: { $0.configuration["bundleID"] == id }) else {
            context.reportError("此应用已经添加。"); return
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        do {
            try context.addBinding(.init(pluginID: AppSwitchPlugin.id, command: "toggle", title: name,
                                         configuration: ["bundleID": id, "path": url.path, "name": name]))
        } catch { context.reportError(error.localizedDescription) }
    }
}
