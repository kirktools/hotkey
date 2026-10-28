import PluginSDK
import AppSwitchPlugin

@MainActor enum BuiltinAssembly {
    static func make() -> [any BuiltinPlugin] { [AppSwitchPlugin()] }
}
