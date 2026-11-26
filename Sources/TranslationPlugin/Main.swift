import AppKit
import HotkeyDiagnostics
import KirkTranslation
import KirkTranslationUI
import NaturalLanguage
import PluginSDK
import SwiftUI

@main enum TranslationMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = TranslationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class TranslationDelegate: NSObject, NSApplicationDelegate {
    private var server: PluginServer?
    private var window: TranslationPanel?
    private var readingSelection = false
    private var requestedAccessibilityPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = PluginServer(execute: { [weak self] command, _ in
            guard command == "translate-selection" else { throw PluginError.message("未知命令") }
            guard #available(macOS 15, *) else {
                throw PluginError.message("划词翻译需要 macOS 15 或更新版本。")
            }
            await self?.translateSelection()
        }, shutdown: {
            NSApp.terminate(nil)
        })
        server?.start()
    }

    @available(macOS 15, *)
    private func translateSelection() async {
        guard !readingSelection else { return }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if pid == ProcessInfo.processInfo.processIdentifier, window?.isVisible == true { return }

        readingSelection = true
        defer { readingSelection = false }
        let operation = HotkeyDiagnostics.shared.begin("translation", "selection")
        let selection = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Selection.read(from: pid))
            }
        }

        switch selection {
        case .text: operation.finish()
        case .permissionRequired: operation.finish(level: .warning, errorCode: "permission_required")
        case .unavailable(let reason): operation.finish(level: .warning, errorCode: reason.code)
        }

        let panel = window ?? TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "划词翻译"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.showTranslation(TranslationView(model: TranslationModel(selection: selection)))
        if window == nil { panel.center() }
        window = panel
        panel.orderFrontRegardless()
        panel.makeKey()
        if case .permissionRequired = selection, !requestedAccessibilityPermission {
            requestedAccessibilityPermission = true
            Selection.requestAccessibilityPermission()
        }
    }
}

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 非激活面板没有编辑菜单，直接把 ⌘V 交给正在编辑的文本框。
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v",
           let editor = firstResponder as? NSTextView, editor.isEditable {
            editor.paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @available(macOS 15, *)
    func showTranslation(_ view: TranslationView) {
        let previousFrame = frame
        let hosting = NSHostingController(rootView: view)
        // 窗口由 AppKit 定尺寸，切换到较窄的设置页时保留用户调整的宽度。
        hosting.sizingOptions = []
        let container = NSViewController()
        container.view = NSView(frame: NSRect(origin: .zero, size: contentRect(forFrameRect: previousFrame).size))
        container.addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        contentViewController = container
        minSize = NSSize(width: 420, height: 350)
        if frame != previousFrame { setFrame(previousFrame, display: false) }
    }
}

@MainActor private final class TranslationModel: ObservableObject {
    struct Request: Equatable {
        let id = UUID()
        let text: String
    }

    private static let limit = 8_000
    @Published var source: String
    @Published var request: Request?
    @Published var aiRequest: Request?
    @Published var showingAISettings = false
    @Published var isAIResult = false
    @Published var result = ""
    @Published var pairs: TranslationSentencePairs?
    private var localOperation: DiagnosticOperation?
    @Published var message: String
    let needsPermission: Bool

    init(selection: Selection) {
        switch selection {
        case .text(let text):
            source = text
            if text.count <= Self.limit {
                message = ""
            } else {
                message = "选区超过 8,000 字符，请缩短后再翻译。"
            }
            needsPermission = false
            if text.count <= Self.limit { startLocalRequest(text) }
        case .permissionRequired:
            source = ""
            message = ""
            needsPermission = true
        case .unavailable:
            source = ""
            message = "未读到选区。请在原应用复制文字，再点「粘贴原文」。"
            needsPermission = false
        }
    }

    func startAITranslation(settings: AITranslationSettings) {
        guard settings.destination != nil else {
            showingAISettings = true
            return
        }
        let text = source
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 12_000 else {
            message = "原文太长，请缩短后再翻译。"
            return
        }
        cancelLocalRequest()
        message = ""
        aiRequest = Request(text: text)
    }

    func startTranslation() {
        let text = source
        guard text.count <= Self.limit else {
            message = "原文超过 8,000 字符，请缩短后再翻译。"
            return
        }
        message = ""
        startLocalRequest(text)
    }

    private func startLocalRequest(_ text: String) {
        localOperation = HotkeyDiagnostics.shared.begin("translation", "local")
        request = Request(text: text)
    }

    func editSource(_ value: String) {
        guard source != value else { return }
        cancelLocalRequest()
        aiRequest = nil
        source = value
        result = ""
        pairs = nil
        isAIResult = false
        message = ""
    }

    func pasteSource() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "剪贴板中未读到文字。请先在原应用复制文本。"
            return
        }
        editSource(text)
        message = ""
    }

    func cancelLocalRequest() {
        localOperation?.finish(level: .info, errorCode: "cancelled")
        localOperation = nil
        request = nil
    }

    func mergeLocal(_ outcome: Result<String, Error>, for completed: Request) {
        guard request == completed else { return }
        request = nil
        switch outcome {
        case .success(let translated):
            result = translated
            pairs = TranslationSentencePairs(original: source, translation: translated)
            isAIResult = false
            localOperation?.finish()
        case .failure(let error):
            message = "翻译未完成。\(error.localizedDescription)"
            localOperation?.finish(errorCode: "local_translation_failed")
        }
        localOperation = nil
    }
}

@available(macOS 15, *)
private struct TranslationView: View {
    @ObservedObject var model: TranslationModel
    @ObservedObject private var aiSettings: AITranslationSettings

    @MainActor init(model: TranslationModel) {
        self.model = model
        aiSettings = .shared
    }

    var body: some View {
        Group {
            if model.showingAISettings {
                AITranslationSetupView(settings: aiSettings) { model.showingAISettings = false }
            } else {
                translationForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if let request = model.request {
                Group {
                    if NLLanguageRecognizer.dominantLanguage(for: request.text) == .simplifiedChinese {
                        Color.clear.task { model.mergeLocal(.success(request.text), for: request) }
                    } else {
                        Color.clear.modifier(KirkTranslationUI.SystemTranslation(
                            text: request.text, target: Locale.Language(identifier: "zh-Hans")
                        ) { model.mergeLocal($0, for: request) })
                    }
                }.id(request.id)
            }
        }
        .task(id: model.aiRequest?.id) {
            guard let request = model.aiRequest else { return }
            let operation = HotkeyDiagnostics.shared.begin("translation", "ai")
            let segmented = SegmentedTranslation(source: request.text, target: "zh-Hans")
            do {
                let text = try await aiSettings.translate(segmented.source, segmentMarker: segmented.marker)
                guard !Task.isCancelled, model.aiRequest == request else {
                    operation.finish(level: .info, errorCode: "cancelled")
                    return
                }
                let rendered = segmented.render(text)
                model.result = rendered.text
                model.pairs = rendered.pairs ?? TranslationSentencePairs(original: request.text, translation: rendered.text)
                model.isAIResult = true
                operation.finish()
            } catch {
                guard !Task.isCancelled, model.aiRequest == request else {
                    operation.finish(level: .info, errorCode: "cancelled")
                    return
                }
                model.message = AITranslationSettings.message(for: error)
                operation.finish(errorCode: "ai_translation_failed")
            }
            model.aiRequest = nil
        }
        .onDisappear {
            model.cancelLocalRequest()
            model.aiRequest = nil
        }
    }

    private var translationForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.needsPermission { selectionPermissionNotice }
            HStack {
                Button("本机翻译", action: model.startTranslation)
                    .disabled(model.request != nil || model.aiRequest != nil || sourceIsEmpty)
                Button("AI 翻译") { model.startAITranslation(settings: aiSettings) }
                    .disabled(model.aiRequest != nil || sourceIsEmpty)
                Button { model.showingAISettings = true } label: {
                    Image(systemName: "gearshape").accessibilityLabel("AI 翻译设置")
                }
                .disabled(model.aiRequest != nil)
                Button("粘贴原文", action: model.pasteSource)
                    .help("用剪贴板中的文字替换原文")
                Spacer()
                if model.request != nil || model.aiRequest != nil {
                    ProgressView().controlSize(.small).accessibilityLabel("正在翻译")
                }
            }
            if let destination = aiSettings.destination {
                Text("点击 AI 翻译会将原文发送给 \(destination)。")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.secondary) }
            TranslationTextColumns(
                original: model.source, translation: model.result, originalTitle: "原文",
                translationTitle: model.isAIResult ? "AI 译文" : "译文", copyTitle: "复制",
                pairs: model.pairs, approximateAlignmentNote: "句段对应关系为近似匹配。",
                onOriginalEdit: model.editSource
            )
            Button("关闭") { NSApp.keyWindow?.close() }.keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private var selectionPermissionNotice: some View {
        let applicationName = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "Hotkey Dev.app" : "Hotkey.app"
        return VStack(alignment: .leading, spacing: 8) {
            Label("无法读取选区：需要辅助功能权限", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("打开辅助功能设置，启用「\(applicationName)」。如果系统提示显示的是「划词翻译」，则启用该项。然后回到原应用，重新选中文字并按快捷键。")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开辅助功能设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("在 Finder 中显示插件") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .help("用于定位插件。系统提示要求添加「划词翻译」时，可从 Finder 选择这份插件。")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
    }

    private var sourceIsEmpty: Bool {
        model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
