import SwiftUI
import AppSwitchPlugin
import HotkeyCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "command.square.fill").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.applicationName).font(.title2.bold())
                    Text("让常用操作触手可及").foregroundStyle(.secondary)
                }
                Spacer()
                if model.paused { Text("快捷键已暂停").foregroundStyle(.orange) }
                Button(model.paused ? "恢复快捷键" : "暂停快捷键") { model.togglePause() }
            }.padding(22)
            TabView {
                applications.tabItem { Label("应用", systemImage: "app.badge") }
                plugins.tabItem { Label("插件", systemImage: "puzzlepiece.extension") }
                general.tabItem { Label("通用", systemImage: "gearshape") }
            }.padding([.horizontal, .bottom], 18)
        }
        .frame(minWidth: 760, minHeight: 520)
        .disabled(model.busy)
        .overlay(alignment: .bottom) {
            if model.busy { ProgressView("正在处理插件…").padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12) }
        }
        .alert("提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private var applications: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("按键打开或显示应用，已在前台时再次按下可隐藏。").foregroundStyle(.secondary)
                Spacer()
                Button { model.addApplication() } label: { Label("添加应用", systemImage: "plus") }
                    .disabled(model.storageBlocked)
            }.padding(.top, 14)
            if !model.configuration.appPluginEnabled {
                Text("应用快捷切换插件已停用，可在「插件」中启用。").foregroundStyle(.orange)
            }
            let bindings = model.configuration.bindings.filter { $0.pluginID == AppSwitchPlugin.id }
            if bindings.isEmpty { empty("添加第一个应用", detail: "选择常用应用，再录入 ⌘⌥ 加字母或数字。", icon: "app.dashed") }
            else { bindingList(bindings) }
            Text("默认前缀 ⌘⌥ · 支持自定义组合 · Esc 取消录入").font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }
    private var plugins: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("内置与外部插件共享快捷键管理。").foregroundStyle(.secondary)
                Spacer()
                Button { Task { await model.installPlugin() } } label: { Label("添加插件", systemImage: "plus") }.disabled(model.storageBlocked)
            }.padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        HStack {
                            Label("应用快捷切换", systemImage: "app.badge").font(.headline)
                            Text("内置").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("启用", isOn: Binding(get: { model.configuration.appPluginEnabled }, set: model.setAppPluginEnabled))
                                .toggleStyle(.switch).fixedSize()
                        }.padding(8)
                    }
                    ForEach(model.configuration.plugins) { plugin in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(model.pluginName(plugin.id), systemImage: "puzzlepiece.extension").font(.headline)
                                    Spacer()
                                    Toggle("启用", isOn: Binding(get: { plugin.enabled }, set: { value in Task { await model.setPluginEnabled(plugin.id, value) } }))
                                        .toggleStyle(.switch).fixedSize()
                                    Button("移除") { Task { await model.removePlugin(plugin.id) } }
                                }
                                Text(model.pluginStatus[plugin.id] ?? (plugin.enabled ? "等待启动" : "已停用"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 18)
                                ForEach(model.configuration.bindings.filter { $0.pluginID == plugin.id }) { binding in
                                    BindingRow(model: model, binding: binding, application: false)
                                }
                            }.padding(8)
                        }
                    }
                    if model.configuration.plugins.isEmpty {
                        empty("扩展更多快捷操作", detail: "添加本地 .hotkeyplugin 插件包。插件停用后，其进程也会退出。", icon: "puzzlepiece.extension")
                    }
                }
            }
        }.padding(12)
    }
    private var general: some View {
        Form {
            Section("快捷键") {
                LabeledContent("建议前缀", value: "⌘⌥ Command + Option")
                Text("系统与本工具内的重复绑定会提示；其他软件的内部快捷键无法完整检测。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重新检查快捷键") { model.retryShortcuts() }
            }
            Section("本机配置") {
                HStack {
                    Button("导出配置…") { model.exportConfiguration() }.disabled(model.storageBlocked)
                    Button("导入配置…") { Task { await model.importConfiguration() } }.disabled(model.storageBlocked)
                    Button("恢复上一份备份") { Task { await model.restoreBackup() } }
                }
                Button("打开配置目录") {
                    try? FileManager.default.createDirectory(at: model.store.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.store.root)
                }
                Text("配置只保存在本机。导出文件包含所选应用的本机路径，请按需保管。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.storageBlocked { Text("配置读取失败。请恢复备份或检查原文件；当前不会覆盖原配置。").foregroundStyle(.red) }
            }
            Section("窗口与桌面") {
                Text("应用未启动时启动；前台再次触发时隐藏。多个窗口、最小化和其他桌面的恢复遵循系统与目标应用的行为。")
                Text("此版本不申请辅助功能、输入监控或屏幕录制权限。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func bindingList(_ bindings: [CommandBinding]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(bindings) { binding in
                    BindingRow(model: model, binding: binding, application: true)
                    Divider()
                }
            }
        }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
    private func empty(_ title: String, detail: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
    }
}

private struct BindingRow: View {
    @ObservedObject var model: AppModel
    let binding: CommandBinding
    let application: Bool
    var body: some View {
        HStack(spacing: 12) {
            if application, let path = binding.configuration["path"] {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(binding.title).font(.headline).lineLimit(1)
                Text(model.bindingErrors[binding.id] ?? (binding.shortcut == nil ? "尚未绑定快捷键" : " "))
                    .font(.caption).foregroundStyle(model.bindingErrors[binding.id] == nil ? Color.secondary : Color.red)
                    .lineLimit(1).help(model.bindingErrors[binding.id] ?? "")
            }.frame(maxWidth: .infinity, alignment: .leading)
            ShortcutRecorder(shortcut: binding.shortcut, onRecording: model.setRecording) { model.updateShortcut(binding.id, $0) }
                .frame(width: 180, height: 28)
            Button { model.updateShortcut(binding.id, nil) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("清除快捷键").disabled(binding.shortcut == nil)
            Button { model.invoke(binding.id) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless).help("试运行命令").disabled(!binding.enabled)
            Toggle("启用", isOn: Binding(get: { binding.enabled }, set: { model.setBindingEnabled(binding.id, $0) }))
                .labelsHidden().toggleStyle(.switch).fixedSize()
            if application {
                Button { model.removeBinding(binding.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("移除应用")
            }
        }.padding(.horizontal, 12).frame(height: 76).disabled(model.storageBlocked)
    }
}
