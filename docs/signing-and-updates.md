# 免费签名与更新

## 采用的方案

参考 [Mayoi 的开发入口](https://github.com/sorrycc/Mayoi/blob/main/scripts/dev.sh)及[发布流程](https://github.com/sorrycc/Mayoi/blob/main/.github/workflows/release.yml)，将开发实例、打包和发布职责分开。Mayoi 的正式 macOS 构建使用 Developer ID 和 Apple 公证；Hotkey 当前采用免费的 ad-hoc 签名，不创建或导入开发者证书。

| | 开发版 | 日常使用版 |
| --- | --- | --- |
| 显示名称 | Hotkey Dev | Hotkey |
| Bundle ID | `dev.hotkey.app.dev` | `dev.hotkey.app` |
| 构建产物 | `dist/dev/Hotkey Dev.app` | `dist/release.noindex/Hotkey.app` |

正式版构建目录使用 `.noindex` 后缀，让 Spotlight 跳过打包用的应用副本。
| 默认数据目录 | `~/Library/Application Support/Hotkey-dev/` | `~/Library/Application Support/Hotkey/` |
| 签名 | ad-hoc | ad-hoc |

原来的 `Hotkey/` 配置保持在原位置，仍供日常使用版读取；不会自动迁移或覆盖。开发版可按需导入导出的配置，但不要将测试插件和快捷键覆盖进日常配置。

两个实例有独立的数据、插件目录和单实例判断。但全局快捷键属于整个桌面会话，使用相同组合仍会冲突；测试时可以手动暂停日常版快捷键，开发版不会自行终止日常版。

## 本地开发与日常更新

```sh
make dev              # 退出本工作区旧开发版，构建并打开新开发版
make build CONFIG=release    # 只构建日常使用版，不启动或覆盖已安装应用
make package          # 构建 Release，再生成本地 DMG、ZIP 和清单
```

`scripts/sign.sh` 固定从 Info.plist 取得 Bundle ID，采用 `codesign --sign - --timestamp=none`，签名后立即执行 `codesign --verify --strict`。宿主和独立插件应用分别签名，不使用 `--deep` 递归签名，也不为加载外部插件关闭 library validation。

ad-hoc 签名可以检查签名后内容是否发生变化，不能证明作者身份，也不等于 Apple 公证。固定 Bundle ID、数据目录和安装位置有助于减少更新差异，但每次重编的代码哈希仍可能变化；尤其未来截图插件涉及的隐私授权，不能承诺在 ad-hoc 更新后一定保留。遇到权限问题应检查实际签名和系统行为，不自动重置权限。

正式版安装到当前用户有写入权限的 `/Applications/Hotkey.app` 或 `~/Applications/Hotkey.app` 后，点击菜单栏「检查更新…」。有新版时，点击「更新并重启」。Hotkey 校验下载包并启动安装助手，先释放快捷键、停止插件再退出。助手把新版复制到安装位置所在磁盘，在验证后交换应用目录，保留旧版 ZIP。更新结果和备份在 `~/Library/Caches/dev.hotkey.app/Updates/`。开发版继续使用 `make dev`。旧版若没有更新菜单，可从 Releases 手动安装一次。

配置和插件保存在 Application Support。手动降级前建议导出配置，不同版本的配置格式可能不兼容。

## 本地更新包

`dist/packages/` 包含：

- `Hotkey-<版本>-macos-<架构>.dmg`：手动安装镜像，打开后把 Hotkey 拖进 Applications。
- `Hotkey-<版本>-macos-<架构>.zip`：主程序包，应用内更新继续使用此格式。
- `Plugin-Translation-<插件版本>-macos-<架构>.zip`：独立翻译插件包。其他官方插件附件也使用 `Plugin-` 前缀。
- DMG 和 ZIP 均生成省略版本号的固定名副本，内容与版本化文件相同。发布流程只上传本次清单列出的归档和校验文件。
- `manifest.json`：应用版本、构建号、Bundle ID、签名方式、文件大小与 SHA-256。
- `SHA256SUMS`：可执行 `shasum -a 256 -c SHA256SUMS` 检查文件完整性。

目前只打包本机架构，文件名明确标注；未声称生成 Universal 应用。版本来自 `Resources/Info.plist`，打包命令不自动改版本，也不修改 Git。CI 运行测试、生成 ZIP 并保存 Actions 构建产物，普通推送不创建 GitHub Release；版本标签触发独立发布工作流。

SHA-256 用于检测损坏和核对文件，不是发布者签名。如果更新包和校验文件同时被替换，单靠它不能验证来源。

`NativeMessage.hotkeyplugin` 是开发用的原生窗口示例。它随本地构建生成，正式 Release 不再包含它。

## 免费方案的系统边界

下载到其他 Mac 后，未公证、无 Developer ID 的应用仍可能被 Gatekeeper 阻止。具体版本允许的情况下，由用户核实来源后，通过系统提供的单应用确认流程处理；Hotkey 不自动清除 quarantine，不关闭 Gatekeeper、SIP 或其他系统保护。受管理设备可能不允许例外。参见 [Apple 的安全打开应用说明](https://support.apple.com/102445)。

[Developer ID 与 Apple 公证](https://developer.apple.com/developer-id/)属于 Apple 开发者分发体系，当前方案不依赖它。免费 Apple 账号也不应被当成免费的 Developer ID 分发替代品。

## 更新来源与插件

主应用只检查官方 GitHub 仓库最新正式 Release，选取匹配版本和当前架构的版本化 ZIP。下载后校验大小、SHA-256（GitHub 提供资产摘要时也必须匹配）、ZIP 结构、应用标识、版本、系统要求、架构及代码签名。当前免费方案信任官方仓库和 GitHub HTTPS，哈希和 ad-hoc 签名不能证明发布者身份。安装需手动触发，未公证更新保留系统打开确认。以后如需后台自动安装，优先接入有独立发布者签名的更新方案（例如 Sparkle 与 Ed25519）。

正式版可在「设置 → 插件 → 官方插件」直接安装或更新划词翻译。列表从 Hotkey 最新正式 Release 读取，只选已知插件、当前架构和版本化附件，不会自动安装。下载校验 SHA-256、归档、插件标识、版本、应用入口、架构和签名，较旧版本不会覆盖已经安装的新版。旧 Release 的翻译附件仍可识别。开发版从本地构建的包安装，独立保留授权和配置。

其他外部插件从各自项目下载、解压，在「设置 → 插件」的对应条目选择「更新…」并选新版包。插件标识要一致，已有证书签名的插件要求延续同一证书；已有 ad-hoc 或未签名插件要明确核实来源后替换。更新会保留该条目的启用状态和仍存在的命令绑定，启用状态的插件会重新握手，握手失败恢复旧包。当前不从第三方地址后台下载插件；未来要做插件仓库，可由安装时确认的独立发布者公钥校验每个插件的版本和归档。

## 固定开发签名身份

`make dev` 支持 `DEV_SIGNING_IDENTITY` 环境变量，或从被 Git 忽略的 `.local/dev-signing-identity` 读取已有代码签名证书的名称或 SHA-1 标识。文件只存一行身份标识，不存私钥，不作为 Shell 脚本执行。宿主和开发示例插件会使用相同身份。

没有配置时明确输出 ad-hoc 提示；一旦指定身份，签名失败立即停止，不静默回退。当前应用不请求敏感权限，因此默认仍可用 ad-hoc 开发。未来引入需要授权的功能前，应先配置固定开发证书并实测授权连续性。脚本不会自动生成证书、操作钥匙串或重置隐私授权；本次未配置固定证书。

发布入口为 `make release BUMP=patch|minor|major`。版本变更、Git 提交及标签推送只发生在该显式命令中，`make package` 始终只生成本地产物。Actions 使用内置 `GITHUB_TOKEN` 发布，不需要本地 gh 登录或付费 Apple 账号。正式包继续使用 ad-hoc 签名。
