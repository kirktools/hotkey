import SwiftUI
import AppKit
import HotkeyCore

struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut?
    var onRecording: (Bool) -> Void
    var onChange: (Shortcut) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.target = button; button.action = #selector(RecorderButton.begin)
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onRecording = onRecording; view.onChange = onChange
        view.normalTitle = shortcut?.display ?? "录入快捷键"
        if !view.recording { view.title = view.normalTitle }
    }
    static func dismantleNSView(_ view: RecorderButton, coordinator: ()) { view.finish() }
}

final class RecorderButton: NSButton {
    var onRecording: ((Bool) -> Void)?
    var onChange: ((Shortcut) -> Void)?
    var normalTitle = "录入快捷键"
    private(set) var recording = false
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    @objc func begin() {
        if recording { finish(); return }
        window?.makeFirstResponder(self)
        recording = true; title = "按组合键 · Esc 取消"
        onRecording?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.recording, event.window === self.window else { return event }
            self.capture(event); return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.finish() }
    }
    override func resignFirstResponder() -> Bool { finish(); return true }
    func finish() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        title = normalTitle; onRecording?(false)
    }
    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { finish(); return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { title = "请同时按下修饰键"; return }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue, label: "")
        finish(); onChange?(shortcut)
    }
}
