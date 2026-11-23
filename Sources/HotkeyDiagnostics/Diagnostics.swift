import Foundation
import KirkLogging

public enum DiagnosticRecordingLevel: String, Sendable {
    case off, error, warning, all

    static func resolve(saved: String?, legacyEnabled: Bool?, channel: DiagnosticChannel) -> Self {
        if let saved, let level = Self(rawValue: saved) { return level }
        if let legacyEnabled { return legacyEnabled ? .all : .off }
        return channel == .dev ? .all : .warning
    }

    func includes(_ level: DiagnosticLevel) -> Bool {
        switch self {
        case .off: return false
        case .error: return level == .error
        case .warning: return level == .warning || level == .error
        case .all: return true
        }
    }
}

/// 宿主和翻译插件共享记录级别，各角色独立写一组日志。
@MainActor public final class HotkeyDiagnostics {
    public static let shared = HotkeyDiagnostics()

    private let config: DiagnosticLog.Configuration
    private let preferenceDomain: CFString
    private let isAppProcess: Bool
    private var logger: DiagnosticLog?
    private static let preferenceKey = "diagnosticLoggingLevel" as CFString
    private static let legacyPreferenceKey = "diagnosticLoggingEnabled" as CFString

    private init() {
        let bundle = Bundle.main
        let id = bundle.bundleIdentifier ?? ""
        let isDev = id.hasSuffix(".dev")
        let baseID = isDev ? String(id.dropLast(".dev".count)) : id
        let isTranslation = baseID == "dev.hotkey.translation-plugin"
        isAppProcess = baseID == "dev.hotkey.app" || isTranslation
        preferenceDomain = (isDev ? "dev.hotkey.app.dev" : "dev.hotkey.app") as CFString
        config = .init(app: "Hotkey", channel: isDev ? .dev : .release,
                       role: isTranslation ? "translation" : "host",
                       version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                       build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }

    public var recordingLevel: DiagnosticRecordingLevel {
        CFPreferencesSynchronize(preferenceDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let saved = CFPreferencesCopyValue(Self.preferenceKey, preferenceDomain,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        let legacy = CFPreferencesCopyValue(Self.legacyPreferenceKey, preferenceDomain,
                                            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
        return .resolve(saved: saved, legacyEnabled: legacy, channel: config.channel)
    }

    public func setRecordingLevel(_ level: DiagnosticRecordingLevel) throws {
        if level != .off { _ = try writer() }
        CFPreferencesSetValue(Self.preferenceKey, level.rawValue as CFString, preferenceDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        // 只识别开关的旧插件无法按级别过滤，仅在选择全部时允许写入。
        CFPreferencesSetValue(Self.legacyPreferenceKey, level == .all ? kCFBooleanTrue : kCFBooleanFalse, preferenceDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(preferenceDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw CocoaError(.fileWriteUnknown)
        }
        logger?.setEnabled(level != .off)
    }

    private func writer() throws -> DiagnosticLog {
        if let logger { return logger }
        let result = try DiagnosticLog(configuration: config, enabled: false)
        logger = result
        return result
    }

    public func record(_ level: DiagnosticLevel, module: StaticString, event: StaticString,
                       operationID: UUID? = nil, errorCode: StaticString? = nil, elapsedMS: Double? = nil) {
        // 测试直接调用核心模块时，不写入用户的应用日志。
        guard isAppProcess, recordingLevel.includes(level), let logger = try? writer() else { return }
        logger.setEnabled(true)
        logger.record(level, module: module, event: event, operationID: operationID,
                      errorCode: errorCode, elapsedMS: elapsedMS)
    }

    public func begin(_ module: StaticString, _ event: StaticString) -> DiagnosticOperation {
        let operation = DiagnosticOperation(module: module, event: event)
        record(.info, module: module, event: event, operationID: operation.id)
        return operation
    }

    public func export(to url: URL, since: Date?, module: StaticString?, failuresOnly: Bool) async throws -> Int {
        let levels: Set<DiagnosticLevel> = failuresOnly ? [.warning, .error] : []
        return try await writer().export(to: url, matching: .init(since: since, module: module, levels: levels),
                                         including: ["translation"])
    }
}

public struct DiagnosticOperation {
    let module: StaticString
    let event: StaticString
    let id = UUID()
    private let start = ContinuousClock.now

    @MainActor public func finish(level: DiagnosticLevel? = nil, errorCode: StaticString? = nil) {
        let duration = start.duration(to: .now).components
        let millis = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        HotkeyDiagnostics.shared.record(level ?? (errorCode == nil ? .info : .error), module: module, event: event,
                                         operationID: id, errorCode: errorCode, elapsedMS: millis)
    }
}
