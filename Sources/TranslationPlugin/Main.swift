import AppKit
import NaturalLanguage
import PluginSDK
import SwiftUI
import Translation

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
        let selection = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Selection.read(from: pid))
            }
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
    }
}

private final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }

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
    @Published var message: String
    let needsPermission: Bool

    init(selection: Selection) {
        switch selection {
        case .text(let text):
            source = text
            if text.count <= Self.limit {
                request = Request(text: text)
                message = ""
            } else {
                message = "选区超过 8,000 字符，请缩短后再翻译。"
            }
            needsPermission = false
        case .permissionRequired:
            source = ""
            message = "划词需要辅助功能权限，也可以直接粘贴文本。"
            needsPermission = true
        case .unavailable:
            source = ""
            message = "未读到选区。可以复制原文，再粘贴到这里。"
            needsPermission = false
        }
    }

    func startAITranslation(settings: AITranslationSettings) {
        guard settings.destination != nil else {
            showingAISettings = true
            return
        }
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 12_000 else {
            message = "原文太长，请缩短后再翻译。"
            return
        }
        request = nil
        message = ""
        aiRequest = Request(text: text)
    }

    func startTranslation() {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= Self.limit else {
            message = "原文超过 8,000 字符，请缩短后再翻译。"
            return
        }
        message = ""
        request = Request(text: text)
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
        .task(id: model.aiRequest?.id) {
            guard let request = model.aiRequest else { return }
            do {
                let text = try await aiSettings.translate(request.text)
                guard !Task.isCancelled, model.aiRequest == request else { return }
                model.result = text
                model.isAIResult = true
            } catch {
                guard !Task.isCancelled, model.aiRequest == request else { return }
                model.message = AITranslationSettings.message(for: error)
            }
            model.aiRequest = nil
        }
        .onDisappear {
            model.request = nil
            model.aiRequest = nil
        }
    }

    private var translationForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("原文").font(.headline)
            TextEditor(text: $model.source)
                .accessibilityLabel("原文")
                .border(.quaternary)
                .frame(minHeight: 78)
            HStack {
                Button("本机翻译", action: model.startTranslation)
                    .disabled(model.request != nil || model.aiRequest != nil || sourceIsEmpty)
                Button("AI 翻译") { model.startAITranslation(settings: aiSettings) }
                    .disabled(model.aiRequest != nil || sourceIsEmpty)
                Button { model.showingAISettings = true } label: {
                    Image(systemName: "gearshape").accessibilityLabel("AI 翻译设置")
                }
                .disabled(model.aiRequest != nil)
                if model.needsPermission, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    Button("打开辅助功能设置") { NSWorkspace.shared.open(url) }
                }
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
            Text(model.isAIResult ? "AI 译文" : "译文").font(.headline)
            ScrollView {
                Text(model.result)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("关闭") { NSApp.keyWindow?.close() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("复制译文") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.result, forType: .string)
                }.disabled(model.result.isEmpty)
            }
        }
        .padding(18)
        .background {
            if let request = model.request {
                TranslationTaskView(text: request.text) { outcome in
                    guard model.request == request else { return }
                    model.request = nil
                    switch outcome {
                    case .success(let value):
                        model.result = value
                        model.isAIResult = false
                    case .failure(let error):
                        model.message = "翻译未完成。\(error.localizedDescription)"
                    }
                }
                .id(request.id)
            }
        }
    }

    private var sourceIsEmpty: Bool {
        model.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@available(macOS 15, *)
private struct TranslationTaskView: View {
    let text: String
    let completion: (Result<String, Error>) -> Void

    var body: some View {
        Color.clear
            .translationTask(source: nil, target: Locale.Language(identifier: "zh-Hans")) { session in
                do {
                    let result: String
                    if NLLanguageRecognizer.dominantLanguage(for: text) == .simplifiedChinese {
                        result = text
                    } else {
                        result = try await session.translate(text).targetText
                    }
                    if !Task.isCancelled { completion(.success(result)) }
                } catch {
                    if !Task.isCancelled { completion(.failure(error)) }
                }
            }
    }
}
