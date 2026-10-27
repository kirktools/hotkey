import Foundation
import PluginSDK

public struct Shortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt32
    // NSEvent 的原始修饰键位；只存 command、option、control、shift。
    public var modifiers: UInt
    public var label: String
    public init(keyCode: UInt32, modifiers: UInt, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(keyCode); hasher.combine(modifiers) }
}

public struct CommandBinding: Codable, Identifiable, Equatable {
    public var id: UUID
    public var pluginID: String
    public var command: String
    public var title: String
    public var configuration: [String: String]
    public var shortcut: Shortcut?
    public var enabled: Bool
    public init(pluginID: String, command: String, title: String, configuration: [String: String] = [:]) {
        id = UUID(); self.pluginID = pluginID; self.command = command; self.title = title
        self.configuration = configuration; enabled = true
    }
}

public struct InstalledPlugin: Codable, Identifiable, Equatable {
    public var id: String
    public var directory: String
    public var enabled: Bool
    public init(id: String, directory: String, enabled: Bool = true) {
        self.id = id; self.directory = directory; self.enabled = enabled
    }
}

public struct Configuration: Codable, Equatable {
    public var schemaVersion = 1
    public var appPluginEnabled = true
    public var bindings: [CommandBinding] = []
    public var plugins: [InstalledPlugin] = []
    public init() {}

    public func validate() throws {
        guard schemaVersion == 1 else { throw PluginError.message("配置版本不受支持，请使用匹配的应用版本。") }
        guard Set(bindings.map(\.id)).count == bindings.count,
              Set(plugins.map(\.id)).count == plugins.count else {
            throw PluginError.message("配置中存在重复标识。")
        }
        var shortcuts = Set<Shortcut>()
        for binding in bindings {
            guard !binding.pluginID.isEmpty, !binding.command.isEmpty else {
                throw PluginError.message("配置包含无效命令。")
            }
            if let key = binding.shortcut {
                let allowed: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
                guard key.keyCode <= 127, key.modifiers != 0, key.modifiers & ~allowed == 0 else {
                    throw PluginError.message("配置包含无效快捷键。")
                }
                if binding.enabled && !shortcuts.insert(key).inserted {
                    throw PluginError.message("配置中存在重复快捷键。")
                }
            }
        }
        for plugin in plugins {
            guard PluginPackage.validID(plugin.id), plugin.directory == plugin.id else {
                throw PluginError.message("插件配置中的路径无效。")
            }
        }
    }
}

public final class ConfigurationStore {
    public let root: URL
    public var file: URL { root.appendingPathComponent("configuration.json") }
    public var backup: URL { root.appendingPathComponent("configuration.backup.json") }
    public var pluginsDirectory: URL { root.appendingPathComponent("Plugins", isDirectory: true) }
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }

    public func load() throws -> Configuration {
        guard fm.fileExists(atPath: file.path) else { return Configuration() }
        return try decode(Data(contentsOf: file))
    }
    public func decode(_ data: Data) throws -> Configuration {
        let config = try JSONDecoder().decode(Configuration.self, from: data)
        try config.validate()
        return config
    }
    public func save(_ config: Configuration) throws {
        try config.validate()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // 只用经过校验的旧文件更新备份，损坏文件保持原样供恢复。
        if fm.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try decode(old)
            try old.write(to: backup, options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: file, options: .atomic)
    }
    public func restoreBackup() throws -> Configuration {
        let data = try Data(contentsOf: backup)
        let config = try decode(data)
        if fm.fileExists(atPath: file.path) {
            let preserved = root.appendingPathComponent("configuration-before-restore-\(UUID().uuidString).json")
            try fm.copyItem(at: file, to: preserved)
        }
        try data.write(to: file, options: .atomic)
        return config
    }
}
