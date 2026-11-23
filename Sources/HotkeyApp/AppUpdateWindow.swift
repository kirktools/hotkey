import AppKit
import HotkeyCore
import SwiftUI

@MainActor final class AppUpdateModel: ObservableObject {
    private let downloader = UpdateDownload()
    private weak var app: AppModel?
    private var task: Task<Void, Never>?
    @Published private(set) var offer: ReleasePackage?
    @Published private(set) var status = "查看 GitHub 上的最新正式版。"
    @Published private(set) var working = false

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    var canInstall: Bool {
        Bundle.main.bundleIdentifier == "dev.hotkey.app" && UpdatePaths.canInstall(at: Bundle.main.bundleURL)
    }
    var releasePage: URL { offer?.page ?? URL(string: "https://github.com/kirktools/hotkey/releases")! }
    var installHint: String {
        if Bundle.main.bundleIdentifier != "dev.hotkey.app" { return "开发版继续使用 make dev 更新。" }
        if !canInstall { return "要在应用内安装，请从可写的「应用程序」目录运行 Hotkey.app。" }
        return "更新会备份旧版，退出插件，再替换并重新打开 Hotkey。未公证的版本可能需要在 macOS 中确认打开。"
    }

    init(app: AppModel) { self.app = app }

    func check() {
        guard !working else { return }
        offer = nil
        working = true
        status = "正在检查正式版本…"
        task = Task {
            defer { working = false; task = nil }
            do {
                offer = try await downloader.check(current: ReleaseVersion(currentVersion))
                let previous = try? String(contentsOf: UpdatePaths.receipt, encoding: .utf8)
                status = offer.map { "发现新版本 \($0.version)。" } ?? "当前已是最新正式版。"
                if let previous, !previous.isEmpty { status += "\n" + previous }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func install() {
        guard !working, canInstall, let offer else { return }
        working = true
        status = "正在下载并校验更新…"
        task = Task {
            defer { working = false; task = nil }
            do {
                let prepared = try await downloader.prepare(offer, currentApp: Bundle.main.bundleURL)
                var handedOff = false
                defer { if !handedOff { prepared.clean() } }
                guard let app, app.beginApplicationUpdate() else {
                    throw UpdateError("请先完成当前快捷键操作或插件管理，再重试安装。")
                }
                do {
                    _ = try await prepared.startHelper(current: Bundle.main.bundleURL)
                    handedOff = true
                    status = "正在退出 Hotkey 并安装…"
                    NSApp.terminate(nil)
                } catch {
                    app.endApplicationUpdate()
                    throw error
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }
}

struct AppUpdateView: View {
    @ObservedObject var model: AppUpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("更新 Hotkey").font(.title2.weight(.semibold))
            Text("当前版本 \(model.currentVersion)").foregroundStyle(.secondary)
            Text(model.status).textSelection(.enabled)
            Text(model.installHint).font(.callout).foregroundStyle(.secondary)
            HStack {
                if model.working { ProgressView().controlSize(.small).accessibilityLabel("更新正在进行") }
                Spacer()
                Link("查看发布页", destination: model.releasePage)
                Button("检查更新", action: model.check).disabled(model.working)
                if model.canInstall, model.offer != nil {
                    Button("更新并重启", action: model.install).buttonStyle(.borderedProminent).disabled(model.working)
                }
            }
        }
        .padding(22)
        .frame(width: 470)
    }
}
