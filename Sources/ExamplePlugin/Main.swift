import AppKit
import PluginSDK

@main enum ExampleMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = ExampleDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class ExampleDelegate: NSObject, NSApplicationDelegate {
    private var server: PluginServer!
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        server = PluginServer(execute: { [weak self] command, _ in
            guard command == "show-message" else { throw PluginError.message("未知命令") }
            self?.showMessage()
        }, shutdown: { [weak self] in
            self?.window?.close()
            NSApp.terminate(nil)
        })
        server.start()
    }
    private func showMessage() {
        if window == nil {
            let value = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            value.title = "外部插件示例"; value.isReleasedWhenClosed = false
            let label = NSTextField(wrappingLabelWithString: "外部插件已收到快捷键命令。\n\n这是插件自己的原生窗口。停用插件时，窗口与进程会一起退出。")
            label.frame = NSRect(x: 28, y: 28, width: 364, height: 110)
            value.contentView?.addSubview(label); value.center(); window = value
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
