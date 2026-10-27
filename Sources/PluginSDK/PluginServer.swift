import Foundation
import Darwin

/// 外部原生插件的协议入口。宿主退出造成 stdin EOF 时，插件自动退出。
@MainActor public final class PluginServer {
    private let execute: (String, [String: String]) async throws -> Void
    private let shutdown: () -> Void
    public init(execute: @escaping (String, [String: String]) async throws -> Void, shutdown: @escaping () -> Void) {
        self.execute = execute; self.shutdown = shutdown
    }
    public func start() {
        signal(SIGPIPE, SIG_IGN)
        Thread.detachNewThread { [self] in
            var buffer = Data()
            do {
                while true {
                    // read(upToCount:) 可能等待填满长度；协议短消息须立即处理。
                    let data = FileHandle.standardInput.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let end = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                        guard line.count <= PluginProtocol.maximumMessageBytes else { exit(65) }
                        let request = try JSONDecoder().decode(PluginRequest.self, from: line)
                        Task { @MainActor in await self.receive(request) }
                    }
                    guard buffer.count <= PluginProtocol.maximumMessageBytes else { exit(65) }
                }
            } catch { /* 管道关闭或无效协议均结束此插件实例。 */ }
            Task { @MainActor in self.shutdown() }
        }
    }
    private func receive(_ request: PluginRequest) async {
        guard request.protocolVersion == PluginProtocol.version else {
            reply(.init(id: request.id, success: false, error: "协议版本不兼容")); return
        }
        do {
            switch request.method {
            case "initialize": break
            case "invoke":
                guard let command = request.command else { throw PluginError.message("缺少命令") }
                try await execute(command, request.configuration)
            case "shutdown":
                reply(.init(id: request.id)); shutdown(); return
            default: throw PluginError.message("未知方法")
            }
            reply(.init(id: request.id))
        } catch {
            reply(.init(id: request.id, success: false, error: error.localizedDescription))
        }
    }
    private func reply(_ response: PluginResponse) {
        do {
            var data = try JSONEncoder().encode(response); data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch { shutdown() }
    }
}
