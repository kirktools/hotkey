import AppKit
import SwiftUI
import Combine

@main enum HotkeyMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var quitting = false
    private var terminationSignal: DispatchSourceSignal?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.hotkey.app")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate(options: [])
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Hotkey")
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(); let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 Hotkey", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem); appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem); NSApp.mainMenu = mainMenu
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        // terminateLater 会进入 AppKit 的嵌套事件循环。先离开 GCD 回调，
        // 避免该循环阻塞同一主队列上的异步插件清理任务。
        source.setEventHandler {
            RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
        }
        source.resume(); terminationSignal = source
        rebuildMenu()
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        Task { await model.start() }
        if model.configuration.bindings.isEmpty || model.storageBlocked || CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    private func rebuildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let summary = NSMenuItem(title: model.issueCount > 0 ? "\(model.issueCount) 项需要检查" : (model.paused ? "快捷键已暂停" : "快捷键运行中"), action: nil, keyEquivalent: "")
        menu.addItem(summary); menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self
        menu.addItem(settings)
        let pause = NSMenuItem(title: model.paused ? "恢复全部快捷键" : "暂停全部快捷键", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self; menu.addItem(pause); menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Hotkey", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.toolTip = "Hotkey · \(summary.title)"
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Hotkey 设置"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.setFrameAutosaveName("HotkeySettings"); window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func togglePause() { model.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task { await model.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
