import Foundation

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

