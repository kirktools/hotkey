import Foundation

public enum PluginProtocol {
    public static let version = 1
    public static let maximumMessageBytes = 262_144
}

public struct PluginCommand: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct PluginManifest: Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var protocolVersion: Int
    public var executable: String
    public var commands: [PluginCommand]
    public init(id: String, name: String, version: String, executable: String, commands: [PluginCommand]) {
        self.id = id; self.name = name; self.version = version
        self.protocolVersion = PluginProtocol.version
        self.executable = executable; self.commands = commands
    }
}

// 每行一个 JSON；stdout 专用于协议，诊断写到 stderr。
public struct PluginRequest: Codable {
    public var id: String
    public var method: String
    public var protocolVersion: Int
    public var command: String?
    public var configuration: [String: String]
    public init(id: String = UUID().uuidString, method: String, command: String? = nil, configuration: [String: String] = [:]) {
        self.id = id; self.method = method; self.protocolVersion = PluginProtocol.version
        self.command = command; self.configuration = configuration
    }
}

public struct PluginResponse: Codable {
    public var id: String
    public var protocolVersion: Int
    public var success: Bool
    public var error: String?
    public init(id: String, success: Bool = true, error: String? = nil) {
        self.id = id; self.protocolVersion = PluginProtocol.version
        self.success = success; self.error = error
    }
}

// 内置插件与外部插件适配器都通过此接口接入宿主。
@MainActor public protocol CommandPlugin: AnyObject {
    var pluginID: String { get }
    var displayName: String { get }
    func enable() async throws
    func execute(command: String, configuration: [String: String]) async throws
    func disable() async
}

public enum PluginError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
