// 应用验签和兼容性检查改编自 kirktools/screenshot，许可见 LICENSE-Screenshot。
import Foundation
import Security
import CryptoKit
import Darwin

struct UpdateBundle {
    let version: ReleaseVersion, minimumOS: ReleaseVersion
    let team: String?
    let certificate: String?
    static func inspect(_ app: URL) throws -> UpdateBundle {
        let fm = FileManager.default
        guard app.lastPathComponent == "Hotkey.app", let iterator = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey]) else { throw UpdateError("更新中没有正确的应用目录。") }
        var total = 0
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw UpdateError("更新应用含不支持的符号链接。") }
            total += values.fileSize ?? 0
            guard total <= 512 * 1024 * 1024 else { throw UpdateError("更新应用内容超过大小限制。") }
        }
        guard try app.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw UpdateError("应用根目录不能是链接。") }
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard (try infoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1024 * 1024 else { throw UpdateError("应用版本信息过大。") }
        let data = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "dev.hotkey.app",
              let executableName = info["CFBundleExecutable"] as? String,
              executableName == "Hotkey",
              let versionText = info["CFBundleShortVersionString"] as? String else { throw UpdateError("更新应用的标识或版本信息无效。") }
        let version = try ReleaseVersion(versionText)
        let minimum = info["LSMinimumSystemVersion"] as? String ?? "14.0"
        let minimumOS = try ReleaseVersion(minimum.split(separator: ".").count == 2 ? minimum + ".0" : minimum)
        _ = try UpdateCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard try supportsArchitecture(app.appendingPathComponent("Contents/MacOS/" + executableName), cpu: architecture == "arm64" ? 0x0100000c : 0x01000007) else { throw UpdateError("更新应用不包含当前芯片架构。") }

        var code: SecStaticCode?, signing: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess else { throw UpdateError("无法读取更新应用的签名身份。") }
        let details = signing as? [String: Any]
        let team = details?[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = details?[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let certificate = certificates?.first.map { SHA256.hash(data: SecCertificateCopyData($0) as Data).map { String(format: "%02x", $0) }.joined() }
        return UpdateBundle(version: version, minimumOS: minimumOS, team: team, certificate: certificate)
    }
    /// 仅供已通过 inspect / requireCompatible 的更新包使用。
    /// 固定证书可把当前用户信任的安装与新版关联；ad-hoc 不具备稳定发布者身份。
    func continuesPublisher(of current: UpdateBundle) -> Bool {
        guard let certificate = current.certificate, !certificate.isEmpty else { return false }
        return self.certificate == certificate && team == current.team
    }
    func applyDownloadReview(to app: URL, current: UpdateBundle) throws {
        // 不删除下载器或系统已有的隔离标记；仅避免对同证书更新主动新增标记。
        guard !continuesPublisher(of: current) else { return }
        _ = try UpdateCommand.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));Hotkey;", app.path])
    }
    /// 直接读取 Mach-O 头；发行应用不能依赖需安装 Xcode/CLT 的 lipo。
    static func supportsArchitecture(_ executable: URL, cpu: UInt32) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: executable); defer { try? handle.close() }
        let data = [UInt8](try handle.read(upToCount: 4096) ?? Data())
        guard data.count >= 8 else { return false }
        func word(_ offset: Int, little: Bool) -> UInt32 {
            let bytes = Array(data[offset..<(offset + 4)])
            return little ? bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) } : bytes.reduce(0) { ($0 << 8) | UInt32($1) }
        }
        let magic = word(0, little: false)
        if magic == 0xcffaedfe { return word(4, little: true) == cpu }
        if magic == 0xfeedfacf { return word(4, little: false) == cpu }
        let little = magic == 0xbebafeca || magic == 0xbfbafeca
        guard [0xcafebabe, 0xcafebabf, 0xbebafeca, 0xbfbafeca].contains(magic) else { return false }
        let count = Int(word(4, little: little)), stride = (magic == 0xcafebabf || magic == 0xbfbafeca) ? 32 : 20
        guard count > 0, count <= 64, 8 + count * stride <= data.count else { return false }
        return (0..<count).contains { word(8 + $0 * stride, little: little) == cpu }
    }
    func requireCompatible(expected: ReleaseVersion, currentTeam: String?, currentCertificate: String? = nil) throws {
        guard version == expected else { throw UpdateError("更新包内版本与 Release 标签不一致。") }
        if let currentTeam, team != currentTeam { throw UpdateError("更新签名身份与当前应用不同，不能自动替换。") }
        // 无 Apple Team ID 的固定自签名也必须延续同一证书，不能降级为 ad-hoc 或换发布者。
        if currentTeam == nil, let currentCertificate, certificate != currentCertificate {
            throw UpdateError("更新证书与当前应用不同，已拒绝替换以保护签名身份和已有授权。")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let running = try ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        guard minimumOS <= running else { throw UpdateError("新版需要 macOS \(minimumOS) 或更新版本。") }
    }
}

public enum UpdatePaths {
    public static var cache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.hotkey.app/Updates", isDirectory: true)
    }
    public static var receipt: URL { cache.appendingPathComponent("last-result.txt") }

    public static func canInstall(at app: URL) -> Bool {
        let app = app.standardizedFileURL
        let parent = app.deletingLastPathComponent()
        let homeApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        return app.lastPathComponent == "Hotkey.app"
            && ["/Applications", homeApps.path].contains(parent.path)
            && app.resolvingSymlinksInPath().path == app.path
            && FileManager.default.isWritableFile(atPath: parent.path)
    }
}

private struct UpdateJob: Codable {
    let pid: Int32
    let current: String
    let version: ReleaseVersion
}

public struct PreparedUpdate {
    let root: URL
    let version: ReleaseVersion

    public func clean() { try? FileManager.default.removeItem(at: root) }

    public func startHelper(current: URL) async throws -> Process {
        guard UpdatePaths.canInstall(at: current), let executable = Bundle.main.executableURL else {
            throw UpdateError("请从可写的「应用程序」目录运行正式版 Hotkey。")
        }
        let helper = root.appendingPathComponent("UpdateInstaller")
        let ready = root.appendingPathComponent("ready")
        try? FileManager.default.removeItem(at: helper)
        try? FileManager.default.removeItem(at: ready)
        try FileManager.default.copyItem(at: executable, to: helper)
        let job = UpdateJob(pid: ProcessInfo.processInfo.processIdentifier, current: current.path, version: version)
        let file = root.appendingPathComponent("update-job.json")
        try JSONEncoder().encode(job).write(to: file, options: .atomic)
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--apply-update", file.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        do {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(30)
            while clock.now < deadline {
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: ready.path), process.isRunning { return process }
                if !process.isRunning { throw UpdateError("安装助手未就绪。请查看更新结果或重试。") }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw UpdateError("安装助手未在规定时间内就绪。")
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
    }
}

public enum UpdateInstaller {
    /// 在目标同盘完成验证后交换目录。交换失败时旧版始终在原位置。
    static func swap(source: URL, destination: URL, backupDirectory: URL, validate: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".hotkey-update-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let stagedApp = staging.appendingPathComponent("Hotkey.app")
        _ = try UpdateCommand.run("/usr/bin/ditto", [source.path, stagedApp.path])
        try validate(stagedApp)
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let backup = backupDirectory.appendingPathComponent("Hotkey-\(UUID().uuidString).zip")
        do {
            _ = try UpdateCommand.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", destination.path, backup.path])
        } catch {
            try? fm.removeItem(at: backup)
            throw error
        }
        guard renameatx_np(AT_FDCWD, stagedApp.path, AT_FDCWD, destination.path, UInt32(RENAME_SWAP)) == 0 else {
            throw UpdateError("无法在此磁盘替换应用，已保留原版（\(errno)）。")
        }
    }

    public static func runHelper(jobPath: String) -> Int32 {
        let fm = FileManager.default
        let file = URL(fileURLWithPath: jobPath).standardizedFileURL
        let root = file.deletingLastPathComponent()
        guard file.lastPathComponent == "update-job.json",
              root.deletingLastPathComponent().path == UpdatePaths.cache.standardizedFileURL.path,
              root.lastPathComponent.hasPrefix("pending-"),
              root.resolvingSymlinksInPath().path == root.path,
              file.resolvingSymlinksInPath().path == file.path else { return 1 }
        let source = root.appendingPathComponent("extracted/Hotkey.app")
        var exited = false
        var destination: URL?
        do {
            guard try (file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 8192 else {
                throw UpdateError("更新任务无效。")
            }
            let job = try JSONDecoder().decode(UpdateJob.self, from: Data(contentsOf: file))
            let installed = URL(fileURLWithPath: job.current)
            guard job.pid == getppid(), job.pid > 1, UpdatePaths.canInstall(at: installed),
                  source.resolvingSymlinksInPath().path == source.path else { throw UpdateError("更新任务路径无效。") }
            destination = installed
            let lock = open(UpdatePaths.cache.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard lock >= 0 else { throw UpdateError("无法锁定更新目录。") }
            defer { close(lock) }
            guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw UpdateError("另一个更新正在安装。") }
            let current = try UpdateBundle.inspect(installed)
            guard current.version < job.version else { throw UpdateError("当前应用版本已改变。") }
            func verify(_ app: URL) throws {
                try UpdateBundle.inspect(app).requireCompatible(expected: job.version, currentTeam: current.team,
                                                               currentCertificate: current.certificate)
            }
            try verify(source)
            try "ready".write(to: root.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
            let deadline = ProcessInfo.processInfo.systemUptime + 45
            while getppid() == job.pid && ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard getppid() != job.pid else { throw UpdateError("Hotkey 尚未退出，安装已取消。") }
            exited = true
            let installedNow = try UpdateBundle.inspect(installed)
            guard installedNow.version == current.version, installedNow.certificate == current.certificate,
                  installedNow.team == current.team else { throw UpdateError("原应用在等待期间发生变化。") }
            try swap(source: source, destination: installed, backupDirectory: UpdatePaths.cache.appendingPathComponent("Backups"),
                     validate: verify)
            let message = "已更新至 \(job.version)。旧版备份位于更新缓存的 Backups 目录。"
            try? message.write(to: UpdatePaths.receipt, atomically: true, encoding: .utf8)
            do { _ = try UpdateCommand.run("/usr/bin/open", [installed.path]) }
            catch {
                try? (message + " macOS 未能重新打开应用，请在 Finder 中打开。")
                    .write(to: UpdatePaths.receipt, atomically: true, encoding: .utf8)
            }
            try? fm.removeItem(at: root)
            return 0
        } catch {
            try? ("上次更新失败：" + error.localizedDescription).write(to: UpdatePaths.receipt, atomically: true, encoding: .utf8)
            if exited, let destination { _ = try? UpdateCommand.run("/usr/bin/open", [destination.path]) }
            try? fm.removeItem(at: root)
            return 1
        }
    }
}
