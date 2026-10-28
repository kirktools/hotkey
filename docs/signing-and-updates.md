# 免费签名与更新

## 采用的方案

参考 [Mayoi 的开发入口](https://github.com/sorrycc/Mayoi/blob/main/scripts/dev.sh)及[发布流程](https://github.com/sorrycc/Mayoi/blob/main/.github/workflows/release.yml)，将开发实例、打包和发布职责分开。Mayoi 的正式 macOS 构建使用 Developer ID 和 Apple 公证；Hotkey 当前采用免费的 ad-hoc 签名，不创建或导入开发者证书。

| | 开发版 | 日常使用版 |
| --- | --- | --- |
| 显示名称 | Hotkey Dev | Hotkey |
| Bundle ID | `dev.hotkey.app.dev` | `dev.hotkey.app` |
| 构建产物 | `dist/dev/Hotkey Dev.app` | `dist/Hotkey.app` |
| 默认数据目录 | `~/Library/Application Support/Hotkey-dev/` | `~/Library/Application Support/Hotkey/` |
| 签名 | ad-hoc | ad-hoc |

原来的 `Hotkey/` 配置保持在原位置，仍供日常使用版读取；不会自动迁移或覆盖。开发版可按需导入导出的配置，但不要将测试插件和快捷键覆盖进日常配置。

两个实例有独立的数据、插件目录和单实例判断。但全局快捷键属于整个桌面会话，使用相同组合仍会冲突；测试时可以手动暂停日常版快捷键，开发版不会自行终止日常版。

## 本地开发与日常更新

```sh
make dev              # 退出本工作区旧开发版，构建并打开新开发版
make build CONFIG=release    # 只构建日常使用版，不启动或覆盖已安装应用
make package          # 构建 Release，再生成本地 ZIP 和清单
```

`scripts/sign.sh` 固定从 Info.plist 取得 Bundle ID，采用 `codesign --sign - --timestamp=none`，签名后立即执行 `codesign --verify --strict`。宿主和独立插件应用分别签名，不使用 `--deep` 递归签名，也不为加载外部插件关闭 library validation。

ad-hoc 签名可以检查签名后内容是否发生变化，不能证明作者身份，也不等于 Apple 公证。固定 Bundle ID、数据目录和安装位置有助于减少更新差异，但每次重编的代码哈希仍可能变化；尤其未来截图插件涉及的隐私授权，不能承诺在 ad-hoc 更新后一定保留。遇到权限问题应检查实际签名和系统行为，不自动重置权限。

日常更新第一阶段使用手动替换：退出 Hotkey（由宿主清理插件进程），保留旧应用作为回退，将新 `Hotkey.app` 放到相同安装位置，再打开。配置和插件保存在 Application Support，不放在主应用包里，因此替换主应用不会主动删除它们。降级前应先导出配置；不同版本的配置格式兼容需要单独保证。

## 本地更新包

`dist/packages/` 包含：

- `Hotkey-<版本>-macos-<架构>.zip`：只包含主应用，支持用作手动更新包。
- `NativeMessage-<版本>-macos-<架构>.zip`：独立示例插件包。
- `manifest.json`：应用版本、构建号、Bundle ID、签名方式、文件大小与 SHA-256。
- `SHA256SUMS`：可执行 `shasum -a 256 -c SHA256SUMS` 检查文件完整性。

目前只打包本机架构，文件名明确标注；未声称生成 Universal 应用。版本来自 `Resources/Info.plist`，打包命令不自动改版本，也不修改 Git。CI 运行测试、生成 ZIP 并保存 Actions 构建产物，普通推送不创建 GitHub Release；版本标签触发独立发布工作流。

SHA-256 用于检测损坏和核对文件，不是发布者签名。如果更新包和校验文件同时被替换，单靠它不能验证来源。

## 免费方案的系统边界

下载到其他 Mac 后，未公证、无 Developer ID 的应用仍可能被 Gatekeeper 阻止。具体版本允许的情况下，由用户核实来源后，通过系统提供的单应用确认流程处理；Hotkey 不自动清除 quarantine，不关闭 Gatekeeper、SIP 或其他系统保护。受管理设备可能不允许例外。参见 [Apple 的安全打开应用说明](https://support.apple.com/102445)。

[Developer ID 与 Apple 公证](https://developer.apple.com/developer-id/)属于 Apple 开发者分发体系，当前方案不依赖它。免费 Apple 账号也不应被当成免费的 Developer ID 分发替代品。

## 后续应用内自动更新

暂未接入网络更新检查或安装器。真正实现时，优先评估 [Sparkle](https://sparkle-project.org/documentation/) 等成熟原生组件，并使用独立的 Ed25519 更新包签名：公钥随应用分发，私钥由发布者保管。此签名不要求购买 Apple 证书，但不能替代 Gatekeeper 信任或公证。

首次生成密钥、保存位置、备份与恢复需要在接入自动更新时明确决定。当前不生成自动更新密钥、不访问钥匙串；标签发布工作流只发布手动安装包。未来更新流程还需保证：校验先于执行、退出所有受管理插件后替换宿主、更新失败可回退、更新清单最后发布。

## 固定开发签名身份

`make dev` 支持 `DEV_SIGNING_IDENTITY` 环境变量，或从被 Git 忽略的 `.local/dev-signing-identity` 读取已有代码签名证书的名称或 SHA-1 标识。文件只存一行身份标识，不存私钥，不作为 Shell 脚本执行。宿主和开发示例插件会使用相同身份。

没有配置时明确输出 ad-hoc 提示；一旦指定身份，签名失败立即停止，不静默回退。当前应用不请求敏感权限，因此默认仍可用 ad-hoc 开发。未来引入需要授权的功能前，应先配置固定开发证书并实测授权连续性。脚本不会自动生成证书、操作钥匙串或重置隐私授权；本次未配置固定证书。

发布入口为 `make release BUMP=patch|minor|major`。版本变更、Git 提交及标签推送只发生在该显式命令中，`make package` 始终只生成本地产物。Actions 使用内置 `GITHUB_TOKEN` 发布，不需要本地 gh 登录或付费 Apple 账号。正式包继续使用 ad-hoc 签名。
