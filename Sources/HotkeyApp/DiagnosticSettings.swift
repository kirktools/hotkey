import AppKit
import HotkeyDiagnostics
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class DiagnosticSettingsModel: ObservableObject {
    enum Module: String, CaseIterable {
        case all = "全部"
        case configuration = "配置"
        case shortcuts = "快捷键"
        case appSwitch = "应用切换"
        case plugins = "插件"
        case updates = "应用更新"
        case translation = "翻译"

        var code: StaticString? {
            switch self {
            case .all: return nil
            case .configuration: return "configuration"
            case .shortcuts: return "shortcuts"
            case .appSwitch: return "app_switch"
            case .plugins: return "plugins"
            case .updates: return "updates"
            case .translation: return "translation"
            }
        }
    }

    @Published private(set) var recordingLevel = HotkeyDiagnostics.shared.recordingLevel
    @Published var days = 1
    @Published var module: Module = .all
    @Published var failuresOnly = false
    @Published private(set) var exporting = false
    @Published private(set) var status: String?

    func setRecordingLevel(_ value: DiagnosticRecordingLevel) {
        do {
            try HotkeyDiagnostics.shared.setRecordingLevel(value)
            status = nil
        } catch {
            status = "未能应用日志设置，请重试。"
        }
        recordingLevel = HotkeyDiagnostics.shared.recordingLevel
    }

    func export() async {
        guard !exporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Hotkey-Diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        defer { exporting = false }
        let since = days == 0 ? nil : Date().addingTimeInterval(-Double(days) * 86400)
        do {
            let count = try await HotkeyDiagnostics.shared.export(to: url, since: since,
                                                                 module: module.code, failuresOnly: failuresOnly)
            status = "已导出 \(count) 条诊断记录。"
        } catch {
            status = "无法导出，请检查目录写入权限后重试。"
        }
    }
}

struct DiagnosticSettings: View {
    @ObservedObject var model: DiagnosticSettingsModel

    var body: some View {
        Section("本机诊断日志") {
            Picker("记录级别", selection: Binding(get: { model.recordingLevel }, set: model.setRecordingLevel)) {
                Text("关闭").tag(DiagnosticRecordingLevel.off)
                Text("仅错误").tag(DiagnosticRecordingLevel.error)
                Text("警告及错误").tag(DiagnosticRecordingLevel.warning)
                Text("全部").tag(DiagnosticRecordingLevel.all)
            }
            Text("记录级别适用于新日志。关闭后仍可导出已有记录。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("导出时段", selection: $model.days) {
                Text("最近 24 小时").tag(1)
                Text("最近 7 天").tag(7)
                Text("全部保留记录").tag(0)
            }
            Picker("导出模块", selection: $model.module) {
                ForEach(DiagnosticSettingsModel.Module.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("仅导出警告及错误", isOn: $model.failuresOnly)
            Button("导出筛选结果…") { Task { await model.export() } }.disabled(model.exporting)
            if let status = model.status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
