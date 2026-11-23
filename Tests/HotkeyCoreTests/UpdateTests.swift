import Foundation
import Testing
@testable import HotkeyCore

struct UpdateTests {
    @Test func officialReleaseSelectsVersionedArchiveAndRejectsConflictingHashes() throws {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let name = "Hotkey-1.10.0-macos-\(arch).zip"
        let hash = String(repeating: "a", count: 64)
        let url = URL(string: "https://github.com/kirktools/hotkey/releases/download/v1.10.0/")!
        let assets = [
            ReleaseAsset(id: 1, name: name, size: 1024, browser_download_url: url.appendingPathComponent(name), digest: "sha256:\(hash)"),
            ReleaseAsset(id: 2, name: "SHA256SUMS", size: 128, browser_download_url: url.appendingPathComponent("SHA256SUMS"), digest: nil)
        ]
        let release = AppRelease(tag_name: "v1.10.0", draft: false, prerelease: false, assets: assets)
        let previous = try ReleaseVersion("1.9.0")
        let offer = try release.package(current: previous)
        let package = try #require(offer)
        #expect(package.archive.name == name)
        #expect(try package.expectedHash("\(hash)  \(name)") == hash)
        #expect(throws: UpdateError.self) { try package.expectedHash("\(String(repeating: "b", count: 64))  \(name)") }
        #expect(try release.package(current: ReleaseVersion("1.10.0")) == nil)
        let other = AppRelease(tag_name: "v1.10.0", draft: false, prerelease: false, assets: [
            ReleaseAsset(id: 1, name: name, size: 1024, browser_download_url: URL(string: "https://github.com/other/hotkey/releases/download/v1.10.0/\(name)")!, digest: nil),
            assets[1]
        ])
        #expect(throws: UpdateError.self) { try other.package(current: previous) }
    }

    @Test func rejectedReplacementKeepsOldAppAndValidReplacementLeavesBackup() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hotkey-update-test-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let destination = root.appendingPathComponent("Hotkey.app")
        let source = root.appendingPathComponent("download/Hotkey.app")
        let backups = root.appendingPathComponent("backups")
        for (url, text) in [(destination, "old"), (source, "new")] {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url.appendingPathComponent("version"))
        }
        #expect(throws: UpdateError.self) {
            try UpdateInstaller.swap(source: source, destination: destination, backupDirectory: backups) { _ in
                throw UpdateError("候选包校验失败")
            }
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8) == "old")
        try UpdateInstaller.swap(source: source, destination: destination, backupDirectory: backups) { staged in
            guard try String(contentsOf: staged.appendingPathComponent("version"), encoding: .utf8) == "new" else {
                throw UpdateError("没有找到待安装的新内容")
            }
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("version"), encoding: .utf8) == "new")
        let archive = try #require(fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        let extracted = root.appendingPathComponent("backup-content")
        _ = try UpdateCommand.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        #expect(try String(contentsOf: extracted.appendingPathComponent("Hotkey.app/version"), encoding: .utf8) == "old")
    }
}
