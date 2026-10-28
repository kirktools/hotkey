import AppKit
import Combine
import HotkeyCore
import AppSwitchPlugin
import PluginSDK

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var configuration = Configuration()
    @Published private(set) var bindingErrors: [UUID: String] = [:]
    @Published private(set) var pluginStatus: [String: String] = [:]
    @Published var message: String?
    @Published private(set) var paused = false
    @Published private(set) var busy = false
    @Published private(set) var recording = false
    @Published private(set) var storageBlocked = false
    let store: ConfigurationStore
    private let registrar = HotkeyRegistrar()
    private let appPlugin = AppSwitchPlugin()
    private let dispatcher = CommandDispatcher()
    private var external: [String: ExternalPlugin] = [:]
    private var inFlight = Set<UUID>()
    private var shuttingDown = false
    var applicationName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Hotkey" }

    init() {
        var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.object(forInfoDictionaryKey: "HotkeyDataDirectoryName") as? String ?? "Hotkey", isDirectory: true)
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HOTKEY_DATA_DIRECTORY"] {
            root = URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        store = ConfigurationStore(root: root)
        do { configuration = try store.load() }
        catch { storageBlocked = true; message = "配置读取失败，原文件已保留。请恢复备份，或打开配置目录检查：\(error.localizedDescription)" }
        registrar.onTrigger = { [weak self] id in self?.invoke(id) }
        dispatcher.register(appPlugin)
    }
    var issueCount: Int { bindingErrors.count + pluginStatus.values.filter { $0 != "已就绪" && $0 != "已停用" }.count + (storageBlocked ? 1 : 0) }
    func start() async {
        guard !storageBlocked else { return }
        busy = true
        for item in configuration.plugins where item.enabled { await loadPlugin(item) }
        busy = false
        syncShortcuts()
    }
    private func available(_ pluginID: String) -> Bool {
        if pluginID == AppSwitchPlugin.id { return configuration.appPluginEnabled }
        return external[pluginID]?.ready == true && configuration.plugins.first(where: { $0.id == pluginID })?.enabled == true
    }
    private func persist(_ next: Configuration) throws {
        guard !storageBlocked else { throw PluginError.message("请先处理配置读取错误。") }
        try store.save(next); configuration = next
    }
    private func syncShortcuts() {
        guard !paused, !recording, !shuttingDown, !storageBlocked else { registrar.removeAll(); return }
        let active = configuration.bindings.filter { $0.enabled && available($0.pluginID) && $0.shortcut != nil }
        registrar.retainOnly(Set(active.map(\.id)))
        for binding in active {
            do { try registrar.replace(id: binding.id, shortcut: binding.shortcut); bindingErrors[binding.id] = nil }
            catch { bindingErrors[binding.id] = error.localizedDescription }
        }
    }
    func setRecording(_ value: Bool) { recording = value; syncShortcuts() }
    func togglePause() { paused.toggle(); syncShortcuts() }
    func retryShortcuts() { syncShortcuts() }

    func addApplication() {
        let picker = NSOpenPanel(); picker.title = "选择要绑定的应用"; picker.allowedContentTypes = [.applicationBundle]
        picker.directoryURL = URL(fileURLWithPath: "/Applications"); picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        guard id != Bundle.main.bundleIdentifier else { message = "请通过菜单栏打开 Hotkey 设置。"; return }
        guard !configuration.bindings.contains(where: { $0.pluginID == AppSwitchPlugin.id && $0.configuration["bundleID"] == id }) else {
            message = "此应用已经添加。"; return
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        var next = configuration
        next.bindings.append(.init(pluginID: AppSwitchPlugin.id, command: "toggle", title: name,
                                   configuration: ["bundleID": id, "path": url.path, "name": name]))
        do { try persist(next) } catch { message = error.localizedDescription }
    }
    func updateShortcut(_ id: UUID, _ key: Shortcut?) {
        guard let index = configuration.bindings.firstIndex(where: { $0.id == id }) else { return }
        let old = configuration.bindings[index]
        if let key, let duplicate = configuration.bindings.first(where: { $0.id != id && $0.shortcut == key }) {
            message = "此快捷键已绑定到「\(duplicate.title)」。"; return
        }
        var next = configuration; next.bindings[index].shortcut = key
        do {
            // 先尝试新注册；失败时保留旧绑定。录入结束会重新同步。
            if old.enabled && available(old.pluginID) && !paused {
                try registrar.replace(id: id, shortcut: key)
            }
            do { try persist(next) }
            catch {
                try? registrar.replace(id: id, shortcut: old.shortcut)
                throw error
            }
            bindingErrors[id] = nil
        } catch { message = error.localizedDescription }
    }
    func setBindingEnabled(_ id: UUID, _ enabled: Bool) {
        var next = configuration
        guard let index = next.bindings.firstIndex(where: { $0.id == id }) else { return }
        next.bindings[index].enabled = enabled
        do { try persist(next); bindingErrors[id] = nil; syncShortcuts() } catch { message = error.localizedDescription }
    }
    func removeBinding(_ id: UUID) {
        var next = configuration; next.bindings.removeAll { $0.id == id }
        do { try persist(next); registrar.remove(id); bindingErrors[id] = nil } catch { message = error.localizedDescription }
    }
    func invoke(_ id: UUID) {
        guard !shuttingDown, !busy, !recording, let binding = configuration.bindings.first(where: { $0.id == id }),
              binding.enabled, available(binding.pluginID), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task {
            defer { inFlight.remove(id) }
            do {
                try await dispatcher.execute(pluginID: binding.pluginID, command: binding.command, configuration: binding.configuration)
                bindingErrors[id] = nil
            } catch { bindingErrors[id] = error.localizedDescription }
        }
    }
    func setAppPluginEnabled(_ enabled: Bool) {
        var next = configuration; next.appPluginEnabled = enabled
        do { try persist(next); syncShortcuts() } catch { message = error.localizedDescription }
    }
    private func loadPlugin(_ item: InstalledPlugin) async {
        guard !shuttingDown else { return }
        do {
            let package = try PluginPackage(root: store.pluginsDirectory.appendingPathComponent(item.directory))
            guard package.manifest.id == item.id else { throw PluginError.message("插件标识与安装记录不一致。") }
            let adapter = ExternalPlugin(package: package)
            adapter.onFailure = { [weak self] error in
                self?.pluginStatus[item.id] = error; self?.syncShortcuts()
            }
            external[item.id] = adapter
            try await adapter.enable()
            guard !shuttingDown else { await adapter.disable(); return }
            dispatcher.register(adapter)
            pluginStatus[item.id] = "已就绪"
        } catch { pluginStatus[item.id] = error.localizedDescription }
    }
    func setPluginEnabled(_ id: String, _ enabled: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var next = configuration
        guard let index = next.plugins.firstIndex(where: { $0.id == id }) else { return }
        next.plugins[index].enabled = enabled
        do { try persist(next) } catch { message = error.localizedDescription; return }
        syncShortcuts()
        if enabled { await external[id]?.disable(); await loadPlugin(next.plugins[index]) }
        else { dispatcher.unregister(id); await external[id]?.disable(); external[id] = nil; pluginStatus[id] = "已停用" }
        syncShortcuts()
    }
    func pluginName(_ id: String) -> String {
        if let adapter = external[id] { return adapter.displayName }
        let root = store.pluginsDirectory.appendingPathComponent(id)
        return (try? PluginPackage(root: root).manifest.name) ?? id
    }
    func installPlugin() async {
        let picker = NSOpenPanel(); picker.title = "添加本地插件包"; picker.canChooseDirectories = true
        picker.canChooseFiles = false; picker.treatsFilePackagesAsDirectories = true
        guard picker.runModal() == .OK, let source = picker.url else { return }
        do {
            let package = try PluginPackage(root: source)
            let confirmation = NSAlert()
            confirmation.messageText = "添加「\(package.manifest.name)」？"
            confirmation.informativeText = "版本 \(package.manifest.version)\n此插件包含本机可执行代码，请仅添加可信来源的插件。\n来源：\(source.path)\n\n同标识插件将被替换，快捷键保留。"
            confirmation.addButton(withTitle: "添加并启用"); confirmation.addButton(withTitle: "取消")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }
            try await install(from: source)
        } catch { message = error.localizedDescription }
    }
    private func install(from source: URL) async throws {
        guard !busy else { return }; busy = true; defer { busy = false; syncShortcuts() }
        let package = try PluginPackage(root: source), fm = FileManager.default
        try fm.createDirectory(at: store.pluginsDirectory, withIntermediateDirectories: true)
        let staged = store.pluginsDirectory.appendingPathComponent(".stage-\(UUID().uuidString)")
        let destination = store.pluginsDirectory.appendingPathComponent(package.manifest.id)
        let previous = store.pluginsDirectory.appendingPathComponent(".previous-\(UUID().uuidString)")
        try fm.copyItem(at: package.root, to: staged)
        defer { try? fm.removeItem(at: staged) }
        _ = try PluginPackage(root: staged)
        let oldConfig = configuration
        registrar.removeAll()
        await external[package.manifest.id]?.disable(); external[package.manifest.id] = nil
        dispatcher.unregister(package.manifest.id)
        let hadPrevious = fm.fileExists(atPath: destination.path)
        var movedPrevious = false
        do {
            if hadPrevious { try fm.moveItem(at: destination, to: previous); movedPrevious = true }
            try fm.moveItem(at: staged, to: destination)
            let installed = try PluginPackage(root: destination)
            let adapter = ExternalPlugin(package: installed)
            external[installed.manifest.id] = adapter
            try await adapter.enable()
            guard !shuttingDown else {
                await adapter.disable()
                throw PluginError.message("应用正在退出，已取消插件安装。")
            }
            var next = configuration
            next.plugins.removeAll { $0.id == installed.manifest.id }
            next.plugins.append(.init(id: installed.manifest.id, directory: installed.manifest.id))
            let commandIDs = Set(installed.manifest.commands.map(\.id))
            next.bindings.removeAll { $0.pluginID == installed.manifest.id && !commandIDs.contains($0.command) }
            for command in installed.manifest.commands where !next.bindings.contains(where: { $0.pluginID == installed.manifest.id && $0.command == command.id }) {
                next.bindings.append(.init(pluginID: installed.manifest.id, command: command.id, title: command.title))
            }
            for index in next.bindings.indices where next.bindings[index].pluginID == installed.manifest.id {
                if let command = installed.manifest.commands.first(where: { $0.id == next.bindings[index].command }) {
                    next.bindings[index].title = command.title
                }
            }
            try persist(next)
            dispatcher.register(adapter)
            adapter.onFailure = { [weak self] error in self?.pluginStatus[installed.manifest.id] = error; self?.syncShortcuts() }
            pluginStatus[installed.manifest.id] = "已就绪"
            if hadPrevious { try? fm.removeItem(at: previous) }
        } catch {
            await external[package.manifest.id]?.disable(); external[package.manifest.id] = nil
            if movedPrevious || !hadPrevious { try? fm.removeItem(at: destination) }
            if movedPrevious { try fm.moveItem(at: previous, to: destination) }
            if let item = oldConfig.plugins.first(where: { $0.id == package.manifest.id && $0.enabled }) { await loadPlugin(item) }
            throw error
        }
    }
    func removePlugin(_ id: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        // 先持久化移除记录，再清理进程与文件；用户配置保留。
        var next = configuration; next.plugins.removeAll { $0.id == id }
        do { try persist(next) } catch { message = error.localizedDescription; return }
        syncShortcuts(); dispatcher.unregister(id); await external[id]?.disable(); external[id] = nil; pluginStatus[id] = nil
        do { try FileManager.default.removeItem(at: store.pluginsDirectory.appendingPathComponent(id)) }
        catch { message = "插件已停用，但清理文件失败：\(error.localizedDescription)" }
    }
    func exportConfiguration() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "hotkey-configuration.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(configuration).write(to: url, options: .atomic) }
        catch { message = error.localizedDescription }
    }
    func importConfiguration() async {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.json]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let next = try store.decode(Data(contentsOf: url))
            let alert = NSAlert(); alert.messageText = "替换当前配置？"
            alert.informativeText = "旧配置将备份。外部插件需已在本机安装；导入配置不会运行新插件文件。"
            alert.addButton(withTitle: "替换"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try persist(next); await reload()
        } catch { message = error.localizedDescription }
    }
    func restoreBackup() async {
        do { configuration = try store.restoreBackup(); storageBlocked = false; await reload(); message = "已恢复备份，恢复前的文件也已保留。" }
        catch { message = "恢复失败：\(error.localizedDescription)" }
    }
    private func reload() async {
        registrar.removeAll()
        for plugin in external.values { dispatcher.unregister(plugin.pluginID); await plugin.disable() }
        external.removeAll(); bindingErrors.removeAll(); pluginStatus.removeAll()
        await start()
    }
    func shutdown() async {
        shuttingDown = true; registrar.removeAll()
        for plugin in external.values { dispatcher.unregister(plugin.pluginID); await plugin.disable() }
        await appPlugin.disable()
    }
}
