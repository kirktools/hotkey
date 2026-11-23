import AppKit
import KirkTranslation
import HotkeyDiagnostics
import Security
import SwiftUI

enum AIProvider: String, CaseIterable {
    case chatGPT, apiKey

    var title: String {
        switch self {
        case .chatGPT: return "ChatGPT"
        case .apiKey: return "自带 API 密钥"
        }
    }
}

@MainActor final class AITranslationSettings: ObservableObject {
    static let shared = AITranslationSettings()
    private static let service = (Bundle.main.bundleIdentifier ?? "dev.hotkey.translation-plugin") + ".translation"

    let plan = ChatGPTPlan(
        service: AITranslationSettings.service,
        applicationName: Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "Hotkey Dev" : "Hotkey",
        hostPreferenceKey: AITranslationSettings.service + ".chatgpt.host"
    )
    @Published var provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "ai.provider") ?? "") ?? .chatGPT {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider") }
    }
    @Published private(set) var baseURL = UserDefaults.standard.string(forKey: "ai.baseURL") ?? ""
    @Published private(set) var model = UserDefaults.standard.string(forKey: "ai.model") ?? ""
    @Published private(set) var isSignedIn = false

    private init() { isSignedIn = plan.isSignedIn }

    var destination: String? {
        switch provider {
        case .chatGPT: return isSignedIn ? "ChatGPT（\(ChatGPTPlan.defaultTranslationModel)）" : nil
        case .apiKey:
            guard let config = try? CloudTranslation(baseURL: baseURL, model: model) else { return nil }
            return config.endpoint.absoluteString
        }
    }

    func translate(_ text: String, segmentMarker: String?) async throws -> String {
        switch provider {
        case .chatGPT:
            return try await plan.translate(text, target: "Simplified Chinese", model: ChatGPTPlan.defaultTranslationModel, segmentMarker: segmentMarker)
        case .apiKey:
            let config = try CloudTranslation(baseURL: baseURL, model: model)
            guard let key = apiKey(for: config.endpoint) else { throw SettingsError.missingKey }
            try Task.checkCancellation()
            return try await config.translate(text, target: "Simplified Chinese", apiKey: key, segmentMarker: segmentMarker)
        }
    }

    func signIn() async throws {
        defer { isSignedIn = plan.isSignedIn }
        let operation = HotkeyDiagnostics.shared.begin("translation", "authorization")
        do {
            try await plan.signIn { NSWorkspace.shared.open($0) }
            operation.finish()
        } catch {
            operation.finish(level: Task.isCancelled ? .info : .error,
                             errorCode: Task.isCancelled ? "cancelled" : "authorization_failed")
            throw error
        }
    }

    func signOut() async throws {
        defer { isSignedIn = plan.isSignedIn }
        try await plan.signOut()
    }

    func save(baseURL: String, model: String, key: String) throws {
        let config = try CloudTranslation(baseURL: baseURL, model: model)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            guard apiKey(for: config.endpoint) != nil else { throw SettingsError.missingKey }
        } else {
            guard !key.contains(where: \.isWhitespace) else { throw SettingsError.invalidKey }
            let query = keychainQuery(config.endpoint)
            let value = [kSecValueData as String: Data(key.utf8)]
            var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
            if status == errSecItemNotFound {
                status = SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = config.model
        UserDefaults.standard.set(self.baseURL, forKey: "ai.baseURL")
        UserDefaults.standard.set(self.model, forKey: "ai.model")
    }

    private func keychainQuery(_ endpoint: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: endpoint.absoluteString]
    }

    private func apiKey(for endpoint: URL) -> String? {
        var query = keychainQuery(endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private enum SettingsError: LocalizedError {
        case missingKey, invalidKey
        var errorDescription: String? {
            switch self {
            case .missingKey: return "请在 AI 翻译设置中填写 API 密钥。"
            case .invalidKey: return "API 密钥不能含空白字符。"
            }
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case ChatGPTPlan.Failure.signInRequired: return "请在 AI 翻译设置中登录 ChatGPT。"
        case ChatGPTPlan.Failure.signInTimedOut: return "授权超时，请重试。"
        case ChatGPTPlan.Failure.usageLimit: return "已达 ChatGPT 用量上限。"
        case ChatGPTPlan.Failure.accessDenied: return "ChatGPT 未授权此请求，请检查套餐和授权。"
        case ChatGPTPlan.Failure.invalidAuthorization: return "ChatGPT 未返回有效授权，请重新登录。"
        case let failure as ChatGPTPlan.HTTPFailure:
            return "ChatGPT 请求失败（HTTP \(failure.status)）。" + message(for: failure.reason)
        case let failure as ChatGPTPlan.Failure:
            return "ChatGPT 操作失败（\(failure.rawValue)）。"
        case CloudTranslation.Failure.invalidConfiguration: return "请填写有效的 HTTPS API 基础地址和模型名。"
        case CloudTranslation.Failure.inputTooLong: return "原文太长，请缩短后再翻译。"
        case CloudTranslation.Failure.invalidResponse: return "服务未返回可用的译文。"
        default: return error.localizedDescription
        }
    }
}

@MainActor final class AISetupModel: ObservableObject {
    enum Action { case signIn, signOut }

    @Published var baseURL: String
    @Published var model: String
    @Published var key = ""
    @Published var error = ""
    @Published var action: Action?

    init(settings: AITranslationSettings) {
        baseURL = settings.baseURL
        model = settings.model
    }
}

struct AITranslationSetupView: View {
    @ObservedObject var settings: AITranslationSettings
    @StateObject private var form: AISetupModel
    let close: () -> Void

    @MainActor init(settings: AITranslationSettings, close: @escaping () -> Void) {
        self.settings = settings
        self.close = close
        _form = StateObject(wrappedValue: AISetupModel(settings: settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI 翻译设置", systemImage: "sparkles").font(.headline)
            Picker("服务", selection: $settings.provider) {
                ForEach(AIProvider.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(form.action != nil)
            .onChange(of: settings.provider) { _, _ in form.error = ""; form.key = "" }

            switch settings.provider {
            case .chatGPT:
                Text("登录并授权使用自己的 ChatGPT 套餐额度。")
                    .foregroundStyle(.secondary)
                if let action = form.action {
                    ProgressView(action == .signIn ? "请在浏览器中完成授权…" : "正在退出…").controlSize(.small)
                } else if settings.isSignedIn {
                    Text(settings.plan.email ?? "已登录")
                    Button("退出 ChatGPT") { form.action = .signOut }
                } else {
                    Button("登录 ChatGPT") { form.action = .signIn }
                }
            case .apiKey:
                TextField("API 基础地址", text: $form.baseURL, prompt: Text("https://api.openai.com/v1"))
                TextField("模型名", text: $form.model)
                SecureField("API 密钥", text: $form.key, prompt: Text("留空则保留已保存密钥"))
                Button("保存") {
                    do {
                        try settings.save(baseURL: form.baseURL, model: form.model, key: form.key)
                        close()
                    } catch {
                        form.error = AITranslationSettings.message(for: error)
                    }
                }
            }

            if !form.error.isEmpty { Text(form.error).foregroundStyle(.secondary).textSelection(.enabled) }
            Spacer()
            Button(form.action == .signIn ? "取消授权" : "返回翻译", action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(form.action == .signOut)
        }
        .padding(18)
        .task(id: form.action) {
            guard let action = form.action else { return }
            form.error = ""
            do {
                switch action {
                case .signIn: try await settings.signIn()
                case .signOut: try await settings.signOut()
                }
            } catch {
                if !Task.isCancelled { form.error = AITranslationSettings.message(for: error) }
            }
            if !Task.isCancelled { form.action = nil }
        }
    }
}
