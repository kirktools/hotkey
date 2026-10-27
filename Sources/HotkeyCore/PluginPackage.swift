import Foundation
import PluginSDK

public struct PluginPackage {
    public let root: URL
    public let manifest: PluginManifest
    public let executable: URL
    public static func validID(_ text: String) -> Bool {
        text.range(of: "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$", options: .regularExpression) != nil && text.count < 160
    }
    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: self.root.appendingPathComponent("manifest.json"))
        guard data.count < 65_536 else { throw PluginError.message("插件清单过大。") }
        manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        guard Self.validID(manifest.id), manifest.id != "builtin.app-switcher",
              !manifest.name.isEmpty, !manifest.version.isEmpty,
              manifest.protocolVersion == PluginProtocol.version,
              !manifest.commands.isEmpty,
              Set(manifest.commands.map(\.id)).count == manifest.commands.count,
              manifest.commands.allSatisfy({ Self.validID("command." + $0.id) && !$0.title.isEmpty }),
              !manifest.executable.hasPrefix("/") else {
            throw PluginError.message("插件清单无效，或协议版本不兼容。")
        }
        executable = self.root.appendingPathComponent(manifest.executable).standardizedFileURL.resolvingSymlinksInPath()
        guard executable.path.hasPrefix(self.root.path + "/"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw PluginError.message("插件入口必须是包内可执行文件。")
        }
        // 原生 framework 常含相对符号链接，只接受仍指向包内的链接。
        if let items = FileManager.default.enumerator(at: self.root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in items {
                if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: item.path)
                    guard !target.hasPrefix("/"), item.resolvingSymlinksInPath().path.hasPrefix(self.root.path + "/") else {
                        throw PluginError.message("插件包含指向包外的符号链接，请提供完整独立的插件包。")
                    }
                }
            }
        }
    }
}
