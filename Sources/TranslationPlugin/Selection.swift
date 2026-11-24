import AppKit
import ApplicationServices

enum Selection: Sendable {
    case text(String), permissionRequired, unavailable

    @MainActor static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func read(from pid: pid_t?) -> Self {
        guard AXIsProcessTrusted() else { return .permissionRequired }
        guard let pid else { return .unavailable }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        if let focused = element(attribute(app, kAXFocusedUIElementAttribute)) {
            AXUIElementSetMessagingTimeout(focused, 0.4)
            if attribute(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                return .unavailable
            }
            if let text = nonEmptyText(attribute(focused, kAXSelectedTextAttribute)) {
                return .text(text)
            }
            if let range = attribute(focused, kAXSelectedTextRangeAttribute),
               CFGetTypeID(range) == AXValueGetTypeID() {
                var selected: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    focused, kAXStringForRangeParameterizedAttribute as CFString, range, &selected
                ) == .success, let text = nonEmptyText(selected) {
                    return .text(text)
                }
            }
        }

        guard let menuItem = copyMenuItem(in: app) else { return .unavailable }
        let text = SelectionPasteboard.readByCopying(on: .general) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            return AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success
        }
        return text.map(Self.text) ?? .unavailable
    }

    private static func copyMenuItem(in app: AXUIElement) -> AXUIElement? {
        guard let menuBar = element(attribute(app, kAXMenuBarAttribute)) else { return nil }
        let deadline = DispatchTime.now() + .milliseconds(600)
        var menus = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] ?? []
        // 优先找编辑菜单。最终按菜单项的键位识别，无需匹配本地化的“复制”标题。
        if menus.count > 3 { menus.insert(menus.remove(at: 3), at: 0) }
        for menu in menus {
            guard DispatchTime.now() < deadline else { return nil }
            let containers = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for container in containers {
                let items = attribute(container, kAXChildrenAttribute) as? [AXUIElement] ?? []
                for item in items {
                    guard DispatchTime.now() < deadline else { return nil }
                    let keys = [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute, kAXEnabledAttribute] as CFArray
                    var values: CFArray?
                    guard AXUIElementCopyMultipleAttributeValues(item, keys, [], &values) == .success,
                          let values = values as? [Any], values.count == 3,
                          (values[0] as? String)?.lowercased() == "c",
                          (values[1] as? NSNumber)?.intValue == 0,
                          (values[2] as? NSNumber)?.boolValue == true else { continue }
                    return item
                }
            }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func nonEmptyText(_ value: CFTypeRef?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

enum SelectionPasteboard {
    static func readByCopying(on board: NSPasteboard, performCopy: () -> Bool) -> String? {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { return nil }
        let originalCount = board.changeCount
        guard let snapshot = snapshot(of: board), board.changeCount == originalCount,
              performCopy() else { return nil }

        let deadline = DispatchTime.now() + .milliseconds(350)
        while board.changeCount == originalCount {
            guard DispatchTime.now() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.015)
        }
        let copiedCount = board.changeCount
        let text = board.string(forType: .string)
        // 如果之后已有其他复制操作，保留新内容。
        guard board.changeCount == copiedCount else { return nil }
        board.clearContents()
        if !snapshot.isEmpty { board.writeObjects(snapshot) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func snapshot(of board: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = board.pasteboardItems else {
            return board.types?.isEmpty == false ? nil : []
        }
        var remainingBytes = 8 * 1024 * 1024
        var snapshot: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard !["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                        "com.apple.pasteboard.promised-file-url", "com.apple.pasteboard.promised-file-content-type"]
                    .contains(type.rawValue),
                      let data = item.data(forType: type), data.count <= remainingBytes,
                      copy.setData(data, forType: type) else { return nil }
                remainingBytes -= data.count
            }
            snapshot.append(copy)
        }
        return snapshot
    }
}
