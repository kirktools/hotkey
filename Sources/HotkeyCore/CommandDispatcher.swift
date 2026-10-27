import PluginSDK

/// 分发层只依赖插件接口；具体插件由宿主装配，不在此判断功能类型。
@MainActor public final class CommandDispatcher {
    private var plugins: [String: any CommandPlugin] = [:]
    public init() {}
    public func register(_ plugin: any CommandPlugin) { plugins[plugin.pluginID] = plugin }
    public func unregister(_ id: String) { plugins[id] = nil }
    public func execute(pluginID: String, command: String, configuration: [String: String]) async throws {
        guard let plugin = plugins[pluginID] else { throw PluginError.message("插件未启用或不可用。") }
        try await plugin.execute(command: command, configuration: configuration)
    }
}
