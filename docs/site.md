# 静态官网维护

官网使用原生 HTML/CSS，不使用框架、统计、广告或第三方运行时资源。中文为主，附英文介绍与英文 README。参考同工作区 Screenshot 项目的白名单构建、固定下载别名和 Release → Pages 调用方式；这里使用 Hotkey 的 DMG 安装包、ZIP 更新包和 arm64 架构。

## 本地命令

```sh
make site
make site-check
make site-preview
# 默认端口被其他项目占用时：
PORT=4174 make site-preview
```

仅构建输出到被忽略的 `.build/site/`，预览只绑定 `127.0.0.1`。`scripts/site.py` 只复制常量白名单中的 HTML、CSS、合成封面、视频及品牌图标，再生成 `.nojekyll`、robots.txt 和 sitemap.xml；不上传整个仓库。新增素材须同时更新白名单及检查。拒绝源文件路径逃逸和输出目录符号链接。

`SITE_RELEASE_TAG=vX.Y.Z make site-check` 会校验标签与 `Resources/Info.plist` 版本一致。未指定时明确标注本地预览，文档链接指向 master；部署时必须指定正式标签，文档链接也随标签固定。

## 演示素材

`site/assets/hotkey-motion.mp4` 和 `hotkey-motion-poster.jpg` 是公开的脚本动效素材，使用合成界面和示例文字演示快捷键绑定、应用切换和划词翻译。页面视频使用原生控制，不自动播放。背景音乐没有旁白，演示内容也在视频下方用文字说明。替换素材后运行 `make site-check`，再用本地预览检查封面和播放。

## 下载与校验

官网主按钮指向：

`https://github.com/kirktools/hotkey/releases/latest/download/Hotkey-macos-arm64.dmg`

发布工作流优先选固定名 DMG。如果当前正式版只有固定名 ZIP，官网继续链接 ZIP。本地可用 `SITE_DOWNLOAD_EXTENSION=dmg make site-check` 检查 DMG 模式。
`make package` 为 DMG、ZIP 和翻译插件生成版本化文件与固定名副本。两种名称均列入 manifest.json 和 SHA256SUMS，不把校验和当作发布者签名。当前构建只生成本机架构；官网不宣传 Intel 或 Universal 下载。将来增加架构时同时调整页面入口与部署检查。

早期 v0.1.1 没有固定名下载和官网源码；v0.1.2 已包含这些内容。官网独立更新不修改旧 Release 附件。早期版本仍可从 Releases 手动更新。

## GitHub Pages 配置与发布

免费默认地址为 `https://kirktools.github.io/hotkey/`，不购买域名。仓库 Pages 来源设置为 **GitHub Actions**。`github-pages` 环境使用自定义部署规则：允许类型为 tag 的 `v*`，以及类型为 branch 的 `master`（用于手动重试的工作流入口），不要求额外人工审批。

- 普通 push：仅应用 CI，不部署官网。
- 相关 PR：`Check website` 只执行静态构建检查，无 Pages 写权限。
- 正式 Release：应用发布成功后，通过 `workflow_call` 直接调用 `pages.yml`，不依赖 GITHUB_TOKEN 创建 Release 再触发事件。
- Pages 构建先检查标签是最新已发布、非 draft、非 prerelease 的正式版本，并有固定下载附件；然后 checkout 对应标签，执行 `make site-check`。
- 手动 `website` 模式从 master 的固定提交构建官网，版本标识与文档链接仍对应最新正式版，不发布应用；仅用于样式、图标及已发布功能的文案修正，不提前宣传未发布功能。
- 仅上传 `.build/site/`。构建 job 只有 contents:read；部署 job 只有 pages:write、id-token:write。
- 所有第三方 Actions 固定到通过 GitHub API 核对的官方标签 commit SHA；本仓库复用工作流使用对应发布版本中的实现。

不在部署流程中自动填 About Website。首次实际部署成功并确认 URL 可以打开后，再设置 Website。robots 与 sitemap 仅帮助发现网页，不保证搜索引擎收录时间或排名。

## 手动更新与独立重试

官网失败不要求再次运行 `make release`。打开仓库 Actions → Deploy release website → Run workflow，分支选择 master：

- `mode=release`：重试最新正式版的官网，源码来自该标签。
- `mode=website`：上线 master 中的新官网改动，不运行应用 Release。
- `tag` 留空会查询最新正式版，也可填写最新正式标签；旧版本会被拒绝。

新增入口须先提交推送到 master 才会出现在 GitHub 上。命令行等价操作：

```sh
gh workflow run pages.yml --ref master -f tag=vX.Y.Z
# 仅更新官网（无需创建应用版本）
gh workflow run pages.yml --ref master -f mode=website
```

两种模式都不改版本、不重发应用；拒绝缺少固定下载名的版本。部署摘要记录源码提交和应用版本。官网更新失败可以按相同模式重试。普通 push 仍不部署。

## 本次验证与上线状态

已本地检查白名单、资源、锚点、封面、视频控制和版本替换；浏览器实际验证 1440px 桌面与 390px 手机布局无横向溢出，键盘 Tab 可访问跳转链接，视频可播放与暂停且解码尺寸为 1280×720。已核对 GitHub About、Topics、Pages 来源与环境规则，并验证版本名／固定名包的字节及校验和一致。

v0.1.2 发布工作流已成功，官网可访问且固定名附件存在；未在浏览器下载并安装该附件。Safari 等其他浏览器未实测。本地服务默认 4173，本次检查使用 4174，避免影响 Screenshot 的预览服务。

官网初版已随 v0.1.2 上线，About Website 已在确认可访问后填写。后续站点修正提交推送后可使用 website 模式独立部署，也可随新正式版本部署。新增手动模式尚未在线运行验证。

## 品牌图标与分享预览

`site/assets/icon.svg` 与 32px PNG 用于浏览器标签，180px PNG 用于移动端收藏，1200×630 PNG 用于 Open Graph／Twitter 分享卡片。图标和图片均在本机用公开品牌文字绘制，无第三方素材或外部字体依赖；已纳入构建白名单和尺寸检查。

需要重新生成 PNG 时，在 macOS 上执行：

```sh
xcrun swiftc scripts/generate-site-art.swift -o .build/tools/generate-site-art
.build/tools/generate-site-art site/assets
make site-check
```

Linux Pages 构建只复制已提交的图片，不依赖 AppKit。资源、元信息修复可用 website 模式部署；release 模式重跑旧标签不会包含后续改动。未验证各社交平台实际抓取与缓存刷新。
