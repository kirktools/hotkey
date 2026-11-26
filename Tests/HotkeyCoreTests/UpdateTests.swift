import Foundation
import Testing
@testable import HotkeyCore

struct UpdateTests {
    @Test func identifiesTranslocatedAppWithoutAllowingInstall() {
        let temporary = URL(fileURLWithPath: "/private/var/folders/test/T/AppTranslocation/\(UUID().uuidString)/d/Hotkey.app")
        #expect(UpdatePaths.isTranslocated(temporary))
        #expect(!UpdatePaths.canInstall(at: temporary))
        #expect(!UpdatePaths.isTranslocated(URL(fileURLWithPath: "/Applications/Hotkey.app")))
        #expect(!UpdatePaths.isTranslocated(URL(fileURLWithPath: "/Users/test/AppTranslocation/Hotkey.app")))
    }

    @Test func onlyMatchingCertificateAvoidsAddingDownloadQuarantine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let version = try ReleaseVersion("1.0.0")
        let signed = UpdateBundle(version: version, minimumOS: version, team: nil, certificate: "same-certificate")
        let adhoc = UpdateBundle(version: version, minimumOS: version, team: nil, certificate: nil)
        let attribute = "com.apple.quarantine"

        try signed.applyDownloadReview(to: url, current: signed)
        let cleanAttributes = try UpdateCommand.run("/usr/bin/xattr", [url.path])
        #expect(!String(decoding: cleanAttributes, as: UTF8.self).contains(attribute))

        try signed.applyDownloadReview(to: url, current: adhoc)
        let quarantine = try UpdateCommand.run("/usr/bin/xattr", ["-p", attribute, url.path])
        #expect(!quarantine.isEmpty)
        try signed.applyDownloadReview(to: url, current: signed)
        #expect(try UpdateCommand.run("/usr/bin/xattr", ["-p", attribute, url.path]) == quarantine)
    }

    @Test func updateOutcomeIsReadOnceAndRejectsUnknownStatus() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hotkey-update-outcome-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("last-result.json")
        let outcome = UpdateOutcome(status: .relaunchFailed, version: try ReleaseVersion("1.2.3"))
        try JSONEncoder().encode(outcome).write(to: file)
        let received = try #require(UpdateOutcome.take(from: file))
        #expect(received.status == .relaunchFailed)
        #expect(received.message.contains("1.2.3"))
        #expect(UpdateOutcome.take(from: file) == nil)
        try Data(#"{"status":"unknown"}"#.utf8).write(to: file)
        #expect(UpdateOutcome.take(from: file) == nil)
    }

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

struct OfficialPluginReleaseTests {
    private let tag = "v8.0.0"

    private func asset(_ name: String, repository: String = "kirktools/hotkey", tag releaseTag: String? = nil) -> ReleaseAsset {
        ReleaseAsset(id: 1, name: name, size: 12,
                     browser_download_url: URL(string: "https://github.com/\(repository)/releases/download/\(releaseTag ?? tag)/\(name)")!,
                     digest: nil)
    }

    @Test func standalonePluginAndLegacyCatalogsChooseHighestVersion() throws {
        let suffix = "-macos-\(AppRelease.architecture).zip"
        let legacy = AppRelease(tag_name: tag, draft: false, prerelease: false,
                                assets: [asset("Plugin-Translation-1.3.0" + suffix), asset("SHA256SUMS")])
        func standalone(_ version: String, prerelease: Bool = false) -> AppRelease {
            let pluginTag = "plugin-translation-v" + version
            return AppRelease(tag_name: pluginTag, draft: false, prerelease: prerelease,
                              assets: [asset("Plugin-Translation-" + version + suffix, tag: pluginTag),
                                       asset("SHA256SUMS", tag: pluginTag)])
        }
        let bundled = try legacy.officialPluginOffers()
        let older = try standalone("1.2.0").standalonePluginOffers()
        let newer = try standalone("1.10.0").standalonePluginOffers()
        #expect(OfficialPluginOffer.newest(legacy: bundled, standalone: older).first?.archive.tag == tag)
        #expect(OfficialPluginOffer.newest(legacy: bundled, standalone: newer + older).first?.archive.tag == "plugin-translation-v1.10.0")
        #expect(try standalone("1.11.0", prerelease: true).standalonePluginOffers().isEmpty)
        #expect(try standalone("01.11.0").standalonePluginOffers().isEmpty)
        #expect(try legacy.standalonePluginOffers().isEmpty)
        #expect(throws: UpdateError.self) { try standalone("1.10.0").package(current: ReleaseVersion("1.0.0")) }
    }

    @Test func catalogPrefersVersionedPluginAndSupportsOlderNames() throws {
        let suffix = "-macos-\(AppRelease.architecture).zip"
        let legacy = asset("Translation-1.2.0" + suffix)
        let modern = asset("Plugin-Translation-1.3.0" + suffix)
        let alias = asset("Plugin-Translation" + suffix)
        let unrelated = asset("Plugin-Unrelated-99.0.0" + suffix)
        let sha = asset("SHA256SUMS")
        for (assets, expected) in [([legacy, alias, unrelated, sha], legacy), ([modern, legacy, alias, sha], modern)] {
            let release = AppRelease(tag_name: tag, draft: false, prerelease: false, assets: assets)
            let offers = try release.officialPluginOffers()
            #expect(offers.count == 1)
            #expect(offers.first?.archive.archive.name == expected.name)
            #expect(offers.first?.plugin.id == "dev.hotkey.translation")
        }
        let missing = AppRelease(tag_name: tag, draft: false, prerelease: false, assets: [alias, unrelated, sha])
        #expect(try missing.officialPluginOffers().isEmpty)
    }

    @Test func catalogRejectsWrongRepositoryAndPrerelease() throws {
        let name = "Plugin-Translation-1.3.0-macos-\(AppRelease.architecture).zip"
        let wrongSource = AppRelease(tag_name: tag, draft: false, prerelease: false,
                                     assets: [asset(name, repository: "other/hotkey"), asset("SHA256SUMS")])
        #expect(throws: UpdateError.self) { try wrongSource.officialPluginOffers() }
        let preview = AppRelease(tag_name: tag, draft: false, prerelease: true,
                                 assets: [asset(name), asset("SHA256SUMS")])
        #expect(throws: UpdateError.self) { try preview.officialPluginOffers() }
    }
}
