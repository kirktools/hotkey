import Foundation
import Security
import PluginSDK

/// 仅证书签名能建立插件更新的发布者连续性。ad-hoc 和未签名包由用户明确核实来源。
public enum PluginPublisher {
    public static func replacementNotice(current: PluginPackage, candidate: PluginPackage) throws -> String {
        let previous = try certificate(of: current)
        let next = try certificate(of: candidate)
        if let previous {
            guard previous == next else {
                throw PluginError.message("新版插件与已安装版的签名证书不同，已拒绝替换。")
            }
            return "签名证书与已安装版一致。"
        }
        return "已安装版没有可验证的发布者证书，请核实新包的来源。"
    }

    private static func certificate(of package: PluginPackage) throws -> Data? {
        let executable = package.executable
        var container = executable.deletingLastPathComponent()
        var target = executable
        while container.path.hasPrefix(package.root.path + "/") {
            if container.pathExtension == "app" {
                guard Bundle(url: container)?.executableURL?.resolvingSymlinksInPath().path == executable.path else {
                    throw PluginError.message("插件入口与应用签名覆盖的可执行文件不一致。")
                }
                target = container
                break
            }
            container.deleteLastPathComponent()
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(target as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else {
            throw PluginError.message("无法读取插件签名。")
        }
        let status = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil)
        if status == errSecCSUnsigned { return nil }
        guard status == errSecSuccess else { throw PluginError.message("插件签名校验失败（\(status)）。") }

        var signing: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess else {
            throw PluginError.message("无法读取插件签名证书。")
        }
        let details = signing as? [String: Any]
        let certificates = details?[kSecCodeInfoCertificates as String] as? [SecCertificate]
        return certificates?.first.map { SecCertificateCopyData($0) as Data }
    }
}
