import Foundation
import PluginSDK

// 使用与原生插件相同的 SDK 服务，验证短消息无需关闭 stdin 即可响应。
@main enum FixtureMain {
    @MainActor static func main() {
        let server = PluginServer(execute: { command, _ in
            guard command == "test" else { throw PluginError.message("未知命令") }
        }, shutdown: { exit(0) })
        server.start()
        withExtendedLifetime(server) { dispatchMain() }
    }
}
