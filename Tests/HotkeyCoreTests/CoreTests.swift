import Testing
import Foundation
import HotkeyCore
import PluginSDK

final class ConfigurationTests {
    private let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hotkey-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @Test func testBackupAndRecoveryPreserveDamagedFile() throws {
        let store = ConfigurationStore(root: root)
        var first = Configuration()
        first.bindings = [.init(pluginID: "builtin.app-switcher", command: "toggle", title: "测试应用")]
        try store.save(first)
        var second = first; second.appPluginEnabled = false
        try store.save(second)
        #expect(try store.load() == second)
        try Data("broken".utf8).write(to: store.file)
        #expect(throws: Error.self) { try store.load() }
        #expect(throws: Error.self) { try store.save(second) }
        #expect(try String(contentsOf: store.file, encoding: .utf8) == "broken")
        #expect(try store.restoreBackup() == first)
        #expect(try store.load() == first)
        let preserved = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("configuration-before-restore-") }
        #expect(preserved.count == 1)
        #expect(try String(contentsOf: preserved[0], encoding: .utf8) == "broken")
    }
    @Test func testDuplicateAndInvalidConfigurationsAreRejected() throws {
        var config = Configuration()
        var a = CommandBinding(pluginID: "example.plugin", command: "a", title: "A")
        a.shortcut = .init(keyCode: 0, modifiers: (1 << 19) | (1 << 20), label: "A")
        var b = CommandBinding(pluginID: "example.plugin", command: "b", title: "B")
        b.shortcut = .init(keyCode: 0, modifiers: (1 << 19) | (1 << 20), label: "不同标签仍然重复")
        config.bindings = [a, b]
        #expect(throws: Error.self) { try config.validate() }
        config.bindings[1].enabled = false
        #expect(throws: Never.self) { try config.validate() }
        config.plugins = [.init(id: "example.plugin", directory: "../escape")]
        #expect(throws: Error.self) { try config.validate() }
        config.plugins = []; config.schemaVersion = 99
        #expect(throws: Error.self) { try config.validate() }
    }
}

final class PluginTests {
    private let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hotkey-plugin-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    private func fixture(_ body: String, protocolVersion: Int = 1) throws -> PluginPackage {
        let executable = root.appendingPathComponent("fixture")
        try Data(("#!/bin/bash\n" + body).utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var manifest = PluginManifest(id: "test.fixture", name: "测试插件", version: "1.0", executable: "fixture", commands: [.init(id: "test", title: "测试")])
        manifest.protocolVersion = protocolVersion
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        return try PluginPackage(root: root)
    }
    private var responsiveScript: String {
        #"""
        while IFS= read -r line; do
          request_id=$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"id":"([^"]+)".*/\1/')
          printf '{"id":"%s","protocolVersion":1,"success":true}\n' "$request_id"
          if [[ "$line" == *'"shutdown"'* ]]; then exit 0; fi
        done
        """#
    }
    @Test func testManifestRejectsIncompatibleProtocolAndEscapingEntry() throws {
        #expect(throws: Error.self) { try fixture("exit 0\n", protocolVersion: 99) }
        _ = try fixture("exit 0\n")
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        var manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        manifest.executable = "/bin/sh"
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        #expect(throws: Error.self) { try PluginPackage(root: root) }
    }
    @Test func testManifestRejectsSymlinks() throws {
        _ = try fixture("exit 0\n")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: URL(fileURLWithPath: "/tmp"))
        #expect(throws: Error.self) { try PluginPackage(root: root) }
    }
    @Test func testInternalRelativeResourceLinkIsAccepted() throws {
        _ = try fixture("exit 0\n")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("resource-link").path, withDestinationPath: "manifest.json")
        #expect(throws: Never.self) { try PluginPackage(root: root) }
    }
    @Test @MainActor func testRealChildHandshakeInvocationAndDisable() async throws {
        let adapter = ExternalPlugin(package: try fixture(responsiveScript))
        try await adapter.enable()
        let process = try #require(adapter.process)
        #expect(process.isRunning)
        #expect(adapter.ready)
        try await adapter.execute(command: "test", configuration: [:])
        await adapter.disable()
        #expect(!(process.isRunning))
        #expect(!(adapter.ready))
        #expect(adapter.process == nil)
        try await adapter.enable()
        #expect(adapter.ready)
        await adapter.disable()
    }
    @Test @MainActor func testUncooperativeChildIsKilledOnDisable() async throws {
        let script = #"""
        trap '' TERM
        while IFS= read -r line; do
          request_id=$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"id":"([^"]+)".*/\1/')
          if [[ "$line" == *'"shutdown"'* ]]; then while :; do :; done; fi
          printf '{"id":"%s","protocolVersion":1,"success":true}\n' "$request_id"
        done
        """#
        let adapter = ExternalPlugin(package: try fixture(script))
        try await adapter.enable()
        let process = try #require(adapter.process)
        let start = Date()
        await adapter.disable()
        #expect(!(process.isRunning))
        #expect(Date().timeIntervalSince(start) < 5)
    }
    @Test @MainActor func testInvalidProtocolStopsProcess() async throws {
        let adapter = ExternalPlugin(package: try fixture("read line\nprintf 'not-json\\n'\nwhile :; do :; done\n"))
        do { try await adapter.enable(); Issue.record("应拒绝无效响应") } catch {}
        await adapter.disable()
        #expect(adapter.process == nil)
    }
    @Test @MainActor func testSDKServerRepliesBeforeInputIsClosed() async throws {
        _ = try fixture("exit 0\n")
        let fixturePath = try #require(ProcessInfo.processInfo.environment["HOTKEY_FIXTURE_EXECUTABLE"])
        let destination = root.appendingPathComponent("fixture")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: fixturePath), to: destination)
        let adapter = ExternalPlugin(package: try PluginPackage(root: root))
        try await adapter.enable()
        #expect(adapter.ready)
        try await adapter.execute(command: "test", configuration: [:])
        let process = try #require(adapter.process)
        await adapter.disable()
        #expect(!process.isRunning)
    }
    @Test @MainActor func testSDKServerExitsWhenHostPipeCloses() async throws {
        let fixturePath = try #require(ProcessInfo.processInfo.environment["HOTKEY_FIXTURE_EXECUTABLE"])
        let child = Process(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: fixturePath)
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        try input.fileHandleForWriting.close()
        for _ in 0..<100 {
            if !child.isRunning { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(!child.isRunning)
        if child.isRunning { child.terminate() }
    }
}
