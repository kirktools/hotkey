// 下载流程改编自 kirktools/screenshot，许可见 LICENSE-Screenshot。
import Foundation
import CryptoKit
import Darwin

/// 所有外部命令使用参数数组；不读取令牌、不启动 shell、不自动执行 gh auth login。
enum UpdateCommand {
    static func run(_ executable: String, _ arguments: [String], maximumOutput: Int = 1024 * 1024) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hotkey-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("output")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output); defer { try? handle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardOutput = handle
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        var exceeded = false
        while process.isRunning {
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if Date() > deadline || size > maximumOutput { exceeded = true; process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if exceeded {
            let timeout = Date().addingTimeInterval(2)
            while process.isRunning && Date() < timeout { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard !exceeded && process.terminationStatus == 0 else { throw UpdateError("\(URL(fileURLWithPath: executable).lastPathComponent) 执行失败或超时，已保留当前应用。") }
        let result = try Data(contentsOf: output)
        guard result.count <= maximumOutput else { throw UpdateError("更新命令输出超过大小限制。") }
        return result
    }

}

final class UpdateHTTPSPolicy: NSObject, URLSessionTaskDelegate {
    static func allowed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
            ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "objects-origin.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.allowed(request.url) ? request : nil)
    }
}

public actor UpdateDownload {
    private let session: URLSession
    private let cacheRoot: URL
    public init(session: URLSession? = nil, cacheRoot: URL = UpdatePaths.cache) {
        self.cacheRoot = cacheRoot
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: config, delegate: UpdateHTTPSPolicy(), delegateQueue: nil)
        }
    }
    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Hotkey-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }
    private func latestRelease() async throws -> AppRelease {
        let url = URL(string: "https://api.github.com/repos/kirktools/hotkey/releases/latest")!
        let (bytes, response) = try await session.bytes(for: request(url))
        guard let http = response as? HTTPURLResponse, UpdateHTTPSPolicy.allowed(http.url) else { throw UpdateError("更新接口响应无效。") }
        guard http.statusCode == 200 else { throw UpdateError("检查更新失败（HTTP \(http.statusCode)）。请稍后重试。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1024 * 1024 else { throw UpdateError("更新元数据超过大小限制。") }
            data.append(byte)
        }
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    public func check(current: ReleaseVersion) async throws -> ReleasePackage? {
        try await latestRelease().package(current: current)
    }

    public func officialPluginOffers() async throws -> [OfficialPluginOffer] {
        try await latestRelease().officialPluginOffers()
    }

    private func download(_ asset: ReleaseAsset, to file: URL, limit: Int) async throws {
        let (bytes, response) = try await session.bytes(for: URLRequest(url: asset.browser_download_url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, UpdateHTTPSPolicy.allowed(http.url),
              response.expectedContentLength <= Int64(limit) else { throw UpdateError("更新下载响应无效或超过大小限制。") }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var chunk = Data(), total = 0
        for try await byte in bytes {
            chunk.append(byte)
            total += 1
            guard total <= limit && total <= asset.size else {
                throw UpdateError("更新下载超过声明大小。", diagnosticCode: "download_size_mismatch")
            }
            if chunk.count == 65536 {
                try Task.checkCancellation()
                try handle.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        try handle.write(contentsOf: chunk)
        guard total == asset.size else {
            throw UpdateError("更新文件大小与 Release 声明不一致。", diagnosticCode: "download_size_mismatch")
        }
    }

    public func prepare(_ package: ReleasePackage, currentApp: URL) async throws -> PreparedUpdate {
        let root = try await extract(package, rootName: "Hotkey.app",
                                     required: ["Contents/Info.plist", "Contents/MacOS/Hotkey"])
        do {
            try await Task.detached {
                let app = root.appendingPathComponent("extracted/Hotkey.app")
                let current = try UpdateBundle.inspect(currentApp)
                let candidate = try UpdateBundle.inspect(app)
                do {
                    try candidate.requireCompatible(expected: package.version, currentTeam: current.team, currentCertificate: current.certificate)
                } catch {
                    throw UpdateError(error.localizedDescription, diagnosticCode: "bundle_incompatible")
                }
                try candidate.applyDownloadReview(to: app, current: current)
            }.value
            try Task.checkCancellation()
            return PreparedUpdate(root: root, version: package.version)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    public func prepareOfficialPlugin(_ offer: OfficialPluginOffer) async throws -> PreparedOfficialPlugin {
        let plugin = offer.plugin
        guard plugin.isSupported else { throw UpdateError(plugin.requirement) }
        let root = try await extract(offer.archive, rootName: plugin.directory,
                                     required: ["manifest.json", plugin.executable])
        do {
            let package = try await Task.detached {
                try offer.validatePackage(at: root.appendingPathComponent("extracted/" + plugin.directory))
            }.value
            try Task.checkCancellation()
            return PreparedOfficialPlugin(root: root, package: package)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func extract(_ package: ReleasePackage, rootName: String, required: [String]) async throws -> URL {
        let root = cacheRoot.appendingPathComponent("pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: root) } }
        let checksum = root.appendingPathComponent("SHA256SUMS"), archive = root.appendingPathComponent(package.archive.name)
        try await download(package.checksums, to: checksum, limit: 64 * 1024)
        let expected = try package.expectedHash(String(contentsOf: checksum, encoding: .utf8))
        try await download(package.archive, to: archive, limit: 128 * 1024 * 1024)
        try Task.checkCancellation()
        try await Task.detached {
            let data = try Data(contentsOf: archive)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else {
                throw UpdateError("更新包 SHA-256 不匹配，已拒绝安装。", diagnosticCode: "checksum_mismatch")
            }
            do { try UpdateZipPolicy.validate(data, root: rootName, required: required) }
            catch { throw UpdateError(error.localizedDescription, diagnosticCode: "archive_invalid") }
            let directory = root.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            _ = try UpdateCommand.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        }.value
        try Task.checkCancellation()
        keep = true
        return root
    }
}
