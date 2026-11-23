import Testing
@testable import HotkeyDiagnostics

struct DiagnosticRecordingLevelTests {
    @Test func defaultsAndSavedChoices() {
        #expect(DiagnosticRecordingLevel.resolve(saved: nil, legacyEnabled: nil, channel: .release) == .warning)
        #expect(DiagnosticRecordingLevel.resolve(saved: nil, legacyEnabled: nil, channel: .dev) == .all)
        #expect(DiagnosticRecordingLevel.resolve(saved: nil, legacyEnabled: false, channel: .dev) == .off)
        #expect(DiagnosticRecordingLevel.resolve(saved: nil, legacyEnabled: true, channel: .release) == .all)
        #expect(DiagnosticRecordingLevel.resolve(saved: "error", legacyEnabled: false, channel: .dev) == .error)
        #expect(DiagnosticRecordingLevel.resolve(saved: "unknown", legacyEnabled: nil, channel: .release) == .warning)
    }

    @Test func filtersNewRecordsByLevel() {
        #expect(!DiagnosticRecordingLevel.off.includes(.error))
        #expect(!DiagnosticRecordingLevel.error.includes(.warning))
        #expect(DiagnosticRecordingLevel.error.includes(.error))
        #expect(!DiagnosticRecordingLevel.warning.includes(.info))
        #expect(DiagnosticRecordingLevel.warning.includes(.warning))
        #expect(DiagnosticRecordingLevel.warning.includes(.error))
        #expect(DiagnosticRecordingLevel.all.includes(.debug))
        #expect(DiagnosticRecordingLevel.all.includes(.info))
    }
}
