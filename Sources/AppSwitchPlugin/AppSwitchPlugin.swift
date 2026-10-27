import AppKit
import PluginSDK

@MainActor public final class AppSwitchPlugin: CommandPlugin {
    public static let id = "builtin.app-switcher"
    public let pluginID = AppSwitchPlugin.id
    public let displayName = "应用快捷切换"
    private var launching = Set<String>()
    public init() {}
    public func enable() async throws {}
    public func disable() async {}
    public func execute(command: String, configuration: [String: String]) async throws {
        guard command == "toggle", let identifier = configuration["bundleID"],
              let path = configuration["path"] else { throw PluginError.message("应用绑定不完整。") }
        guard !launching.contains(identifier) else { return }
        let workspace = NSWorkspace.shared
        // 优先使用用户选定的副本；应用被移动后再交给 Launch Services 查找。
        let saved = URL(fileURLWithPath: path)
        let url: URL
        if Bundle(url: saved)?.bundleIdentifier == identifier { url = saved }
        else if let found = workspace.urlForApplication(withBundleIdentifier: identifier) { url = found }
        else { throw PluginError.message("找不到 \(configuration["name"] ?? "应用")，请重新添加。") }
        let running = workspace.runningApplications.filter {
            $0.bundleIdentifier == identifier && !$0.isTerminated
        }
        if let active = running.first(where: { $0.isActive }) {
            guard active.hide() else { throw PluginError.message("应用没有接受隐藏请求。") }
            return
        }
        launching.insert(identifier)
        defer { launching.remove(identifier) }
        if let app = running.first(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }) ?? running.first {
            if app.isHidden { _ = app.unhide() }
        }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        options.createsNewApplicationInstance = false
        options.addsToRecentItems = false
        // 打开运行中的应用会走其 reopen 路径，允许目标应用自行恢复窗口。
        _ = try await workspace.openApplication(at: url, configuration: options)
    }
}
