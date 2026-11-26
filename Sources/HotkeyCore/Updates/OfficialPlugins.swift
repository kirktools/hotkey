import Foundation

public enum OfficialPlugin: CaseIterable, Identifiable {
    case translation

    public var id: String { "dev.hotkey.translation" }
    public var name: String { "划词翻译" }
    public var summary: String { "用快捷键翻译选中的文字，支持本机和 AI 翻译。" }
    public var requirement: String { "需要 macOS 15 或更新版本。" }
    var archiveName: String { "Plugin-Translation" }
    var archiveNames: [String] { [archiveName, "Hotkey-Plugin-Translation", "Translation"] }
    var releaseTagPrefix: String { "plugin-translation-v" }
    var directory: String { "Translation.hotkeyplugin" }
    var app: String { "TranslationPlugin.app" }
    var executable: String { "TranslationPlugin.app/Contents/MacOS/TranslationPlugin" }
    var bundleID: String { "dev.hotkey.translation-plugin" }

    public var isSupported: Bool {
        if #available(macOS 15, *) { return true }
        return false
    }
}

public struct OfficialPluginOffer {
    public let plugin: OfficialPlugin
    public var version: ReleaseVersion { archive.version }
    let archive: ReleasePackage

    func validatePackage(at url: URL) throws -> PluginPackage {
        let package = try PluginPackage(root: url)
        let appURL = url.appendingPathComponent(plugin.app)
        guard package.manifest.id == plugin.id, package.manifest.version == version.description,
              package.manifest.executable == plugin.executable,
              let app = Bundle(url: appURL), app.bundleIdentifier == plugin.bundleID,
              app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version.description,
              app.executableURL?.resolvingSymlinksInPath().path == package.executable.path else {
            throw UpdateError("官方插件的标识、版本或入口与发布信息不一致。")
        }
        let minimum = app.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? ""
        let minimumOS = try ReleaseVersion(minimum.split(separator: ".").count == 2 ? minimum + ".0" : minimum)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let running = try ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        guard minimumOS <= running else { throw UpdateError("官方插件需要 macOS \(minimumOS) 或更新版本。") }
        #if arch(arm64)
        let cpu: UInt32 = 0x0100000c
        #else
        let cpu: UInt32 = 0x01000007
        #endif
        guard try UpdateBundle.supportsArchitecture(package.executable, cpu: cpu) else {
            throw UpdateError("官方插件不支持当前芯片架构。")
        }
        _ = try UpdateCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        return package
    }
}

public struct PreparedOfficialPlugin {
    let root: URL
    public let package: PluginPackage
    public func clean() { try? FileManager.default.removeItem(at: root) }
}

extension AppRelease {
    func standalonePluginOffers() throws -> [OfficialPluginOffer] {
        guard !draft, !prerelease else { return [] }
        return try OfficialPlugin.allCases.compactMap { plugin in
            guard tag_name.hasPrefix(plugin.releaseTagPrefix) else { return nil }
            let value = String(tag_name.dropFirst(plugin.releaseTagPrefix.count))
            guard let version = try? ReleaseVersion(value), version.description == value else { return nil }
            let name = "\(plugin.archiveName)-\(version)-macos-\(Self.architecture).zip"
            guard assets.contains(where: { $0.name == name }) else { return nil }
            return OfficialPluginOffer(plugin: plugin, archive: try archive(named: name, version: version))
        }
    }

    func officialPluginOffers() throws -> [OfficialPluginOffer] {
        guard !draft, !prerelease, tag_name == "v\(try version)" else {
            throw UpdateError("官方插件只从正式 Release 提供。")
        }
        let suffix = "-macos-\(Self.architecture).zip"
        return try OfficialPlugin.allCases.compactMap { plugin in
            for archiveName in plugin.archiveNames {
                let prefix = archiveName + "-"
                let matches = assets.compactMap { asset -> (String, ReleaseVersion)? in
                    guard asset.name.hasPrefix(prefix), asset.name.hasSuffix(suffix),
                          asset.name.count > prefix.count + suffix.count else { return nil }
                    let value = String(asset.name.dropFirst(prefix.count).dropLast(suffix.count))
                    guard let version = try? ReleaseVersion(value), version.description == value else { return nil }
                    return (asset.name, version)
                }
                guard let (name, version) = matches.max(by: { $0.1 < $1.1 }) else { continue }
                return OfficialPluginOffer(plugin: plugin, archive: try archive(named: name, version: version))
            }
            return nil
        }
    }
}

extension OfficialPluginOffer {
    static func newest(legacy: [Self], standalone: [Self]) -> [Self] {
        OfficialPlugin.allCases.compactMap { plugin in
            (legacy + standalone).filter { $0.plugin == plugin }.reduce(nil as Self?) { newest, offer in
                guard let newest, newest.version > offer.version else { return offer }
                return newest
            }
        }
    }
}
