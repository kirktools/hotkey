import AppKit
import Carbon
import HotkeyCore
import PluginSDK

@MainActor final class HotkeyRegistrar {
    private struct Entry { let shortcut: Shortcut; let reference: EventHotKeyRef; let token: UInt32 }
    private var entries: [UUID: Entry] = [:]
    private var handler: EventHandlerRef?
    private var nextToken: UInt32 = 1
    private var heldTokens = Set<UInt32>()
    var onTrigger: ((UUID) -> Void)?
    init() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            let registrar = Unmanaged<HotkeyRegistrar>.fromOpaque(context).takeUnretainedValue()
            let token = identifier.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            Task { @MainActor in
                if released { registrar.heldTokens.remove(token); return }
                guard registrar.heldTokens.insert(token).inserted else { return }
                if let id = registrar.entries.first(where: { $0.value.token == token })?.key { registrar.onTrigger?(id) }
            }
            return noErr
        }, 2, &events, context, &handler)
    }
    func replace(id: UUID, shortcut: Shortcut?) throws {
        if entries[id]?.shortcut == shortcut { return }
        guard let shortcut else { remove(id); return }
        guard handler != nil else { throw PluginError.message("全局快捷键事件处理器不可用，请重启应用。") }
        try checkSystem(shortcut)
        let token = nextToken; nextToken &+= 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, Self.carbonModifiers(shortcut.modifiers),
                                        EventHotKeyID(signature: 0x484B4559, id: token), GetApplicationEventTarget(),
                                        OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else {
            throw PluginError.message("快捷键注册失败（\(status)），可能已被其他程序占用。")
        }
        remove(id)
        entries[id] = Entry(shortcut: shortcut, reference: reference, token: token)
    }
    func remove(_ id: UUID) {
        if let entry = entries.removeValue(forKey: id) {
            heldTokens.remove(entry.token)
            UnregisterEventHotKey(entry.reference)
        }
    }
    func removeAll() { for id in Array(entries.keys) { remove(id) } }
    func retainOnly(_ ids: Set<UUID>) { for id in Array(entries.keys) where !ids.contains(id) { remove(id) } }
    private func checkSystem(_ shortcut: Shortcut) throws {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let hotkeys = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            throw PluginError.message("暂时无法检查系统快捷键，请稍后重试。")
        }
        for item in hotkeys {
            if (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
               (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode,
               (item[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == Self.carbonModifiers(shortcut.modifiers) {
                throw PluginError.message("此组合已用于系统快捷键，请选择其他组合。")
            }
        }
        // 部分系统保留组合不在 symbolic hotkeys 列表中。
        if shortcut.keyCode == 12 && shortcut.modifiers == NSEvent.ModifierFlags([.command, .control]).rawValue {
            throw PluginError.message("⌃⌘Q 是系统锁屏快捷键。")
        }
    }
    static func carbonModifiers(_ raw: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: raw)
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
    static func keyLabel(_ code: UInt16) -> String {
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let label = special[code] { return label }
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        if let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var state: UInt32 = 0, count = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &state, chars.count, &count, &chars)
            if status == noErr, count > 0 { return String(utf16CodeUnits: chars, count: count).uppercased() }
        }
        return "键 \(code)"
    }
}

extension Shortcut {
    @MainActor var display: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
            (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + HotkeyRegistrar.keyLabel(UInt16(keyCode))
    }
}
