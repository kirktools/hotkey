import SwiftUI
import AppKit

/// 宿主提供通用存储与快捷键控件，插件提供功能界面及绑定内容。
@MainActor public struct PluginSettingsContext {
    public let bindings: [CommandBinding]
    public let enabled: Bool
    public let addBinding: (CommandBinding) throws -> Void
    public let reportError: (String) -> Void
    public let bindingRow: (CommandBinding, NSImage?) -> AnyView
    public init(bindings: [CommandBinding], enabled: Bool,
                addBinding: @escaping (CommandBinding) throws -> Void,
                reportError: @escaping (String) -> Void,
                bindingRow: @escaping (CommandBinding, NSImage?) -> AnyView) {
        self.bindings = bindings; self.enabled = enabled; self.addBinding = addBinding
        self.reportError = reportError; self.bindingRow = bindingRow
    }
}

@MainActor public protocol BuiltinPlugin: CommandPlugin {
    var settingsTitle: String { get }
    var settingsSymbol: String { get }
    func makeSettings(context: PluginSettingsContext) -> AnyView
}
