import Foundation
import Darwin
import PluginSDK

@MainActor public final class ExternalPlugin: CommandPlugin {
    public var pluginID: String { package.manifest.id }
    public var displayName: String { package.manifest.name }
    public let package: PluginPackage
    public private(set) var process: Process?
    public private(set) var ready = false
    public var onFailure: ((String) -> Void)?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var buffer = Data()
    private var stopping = false
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]
    public init(package: PluginPackage) { self.package = package }

    public func enable() async throws {
        guard !ready else { return }
        guard process == nil else { throw PluginError.message("插件正在启动或停止，请稍后重试。") }
        signal(SIGPIPE, SIG_IGN)
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = package.executable
        child.currentDirectoryURL = package.root
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        child.environment = ProcessInfo.processInfo.environment.merging(["HOTKEY_PLUGIN_PROTOCOL": "1"]) { _, new in new }
        input = stdin; output = stdout; errors = stderr; buffer.removeAll(); stopping = false
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.receive(data)
            }
        }
        // 持续排空 stderr，防止插件因日志管道写满而挂住。
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self, weak child] _ in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                let expected = self.stopping
                self.ready = false
                self.failPending("插件进程已退出。")
                self.cleanup()
                if !expected { self.onFailure?("插件进程意外退出，请停用后重新启用。") }
            }
        }
        process = child
        do {
            try child.run()
            try await request(.init(method: "initialize"), timeout: 3)
            ready = true
        } catch {
            await disable()
            throw error
        }
    }
    public func execute(command: String, configuration: [String: String]) async throws {
        guard ready, package.manifest.commands.contains(where: { $0.id == command }) else {
            throw PluginError.message("插件未就绪，或命令不存在。")
        }
        try await request(.init(method: "invoke", command: command, configuration: configuration), timeout: 30)
    }
    public func disable() async {
        ready = false; stopping = true
        guard let child = process else { return }
        if child.isRunning {
            try? await request(.init(method: "shutdown"), timeout: 0.5)
            try? input?.fileHandleForWriting.close()
            for _ in 0..<10 {
                if !child.isRunning { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if child.isRunning { child.terminate() }
            for _ in 0..<10 {
                if !child.isRunning { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            // 等待内核确认退出后才允许重新启用，避免留下第二个实例。
            while child.isRunning { try? await Task.sleep(nanoseconds: 20_000_000) }
        }
        if process === child { failPending("插件已停用。"); cleanup() }
    }
    private func request(_ request: PluginRequest, timeout: Double) async throws {
        guard let child = process, child.isRunning else { throw PluginError.message("插件未运行。") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending[request.id] = continuation
            do {
                var data = try JSONEncoder().encode(request); data.append(10)
                guard data.count <= PluginProtocol.maximumMessageBytes else { throw PluginError.message("命令参数过大。") }
                try input?.fileHandleForWriting.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: request.id)?.resume(throwing: error)
                return
            }
            Task { [weak self, weak child] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, self.process === child,
                      let waiting = self.pending.removeValue(forKey: request.id) else { return }
                waiting.resume(throwing: PluginError.message("插件响应超时。"))
            }
        }
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard line.count <= PluginProtocol.maximumMessageBytes,
                  let response = try? JSONDecoder().decode(PluginResponse.self, from: line),
                  response.protocolVersion == PluginProtocol.version else {
                protocolFailure(); return
            }
            guard let waiting = pending.removeValue(forKey: response.id) else { continue }
            if response.success { waiting.resume() }
            else { waiting.resume(throwing: PluginError.message(String((response.error ?? "插件执行失败。").prefix(1000)))) }
        }
        if buffer.count > PluginProtocol.maximumMessageBytes { protocolFailure() }
    }
    private func protocolFailure() {
        failPending("插件返回了无效协议消息。")
        ready = false
        onFailure?("插件协议错误，已停用进程。")
        Task { await disable() }
    }
    private func failPending(_ message: String) {
        let values = Array(pending.values); pending.removeAll()
        for item in values { item.resume(throwing: PluginError.message(message)) }
    }
    private func cleanup() {
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        try? errors?.fileHandleForReading.close()
        process = nil; input = nil; output = nil; errors = nil; buffer.removeAll()
    }
}
