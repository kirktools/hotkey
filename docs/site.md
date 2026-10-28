# 静态官网维护

官网使用原生 HTML/CSS，不使用框架、统计、广告或第三方运行时资源。中文为主，附英文介绍与英文 README。参考同工作区 Screenshot 项目的白名单构建、固定下载别名和 Release → Pages 调用方式；这里保留 Hotkey 的 ZIP、arm64 架构与手动更新规则。

## 本地命令

```sh
make site
make site-check
make site-preview
# 默认端口被其他项目占用时：
PORT=4174 make site-preview
```

仅构建输出到被忽略的 `.build/site/`，预览只绑定 `127.0.0.1`。`scripts/site.py` 只复制常量白名单中的 HTML、CSS、合成封面及视频，再生成 `.nojekyll`、robots.txt 和 sitemap.xml；不上传整个仓库。新增素材须同时更新白名单及检查。拒绝源文件路径逃逸和输出目录符号链接。

`SITE_RELEASE_TAG=vX.Y.Z make site-check` 会校验标签与 `Resources/Info.plist` 版本一致。未指定时明确标注本地预览，文档链接指向 master；部署时必须指定正式标签，文档链接也随标签固定。

## 演示素材

`site/assets/demo-poster.svg` 和 `demo.webm` 只包含虚构的「示例浏览器」及合成绑定。视频由浏览器 Canvas 脚本绘制并编码，非真实桌面录屏，页面明确标注。可用浏览器打开 `scripts/generate-site-demo.html`，点击按钮重新生成并下载视频；替换公开素材后运行 `make site-check`，无需引入编码工具依赖。原生 video controls 提供播放、暂停，禁止 autoplay；无声视频的内容也以页面文字完整说明。未使用真实聊天、账号、本机路径或截图项目的截图素材。

## 下载与校验

官网主按钮指向：

`https://github.com/kirktools/hotkey/releases/latest/download/Hotkey-macos-arm64.zip`

`make package` 保留 `Hotkey-<版本>-macos-arm64.zip`，另复制为固定文件名，字节完全一致。示例插件也提供版本名与固定名。两种名称均列入 manifest.json 和 SHA256SUMS，不把校验和当作发布者签名。当前构建只生成本机架构；官网不宣传 Intel 或 Universal 下载。将来增加架构时同时调整页面入口与部署检查。

当前已发布的 v0.1.1 没有固定名下载和官网源码。需发布包含本次改动的新版本，不能用旧标签直接上线新页面，也不修改旧 Release 附件。应用内自动更新仍未接入。

## GitHub Pages 配置与发布

免费默认地址为 `https://kirktools.github.io/hotkey/`，不购买域名。仓库 Pages 来源设置为 **GitHub Actions**。`github-pages` 环境使用自定义部署规则：允许类型为 tag 的 `v*`，以及类型为 branch 的 `master`（用于手动重试的工作流入口），不要求额外人工审批。

- 普通 push：仅应用 CI，不部署官网。
- 相关 PR：`Check website` 只执行静态构建检查，无 Pages 写权限。
- 正式 Release：应用发布成功后，通过 `workflow_call` 直接调用 `pages.yml`，不依赖 GITHUB_TOKEN 创建 Release 再触发事件。
- Pages 构建先检查标签是最新已发布、非 draft、非 prerelease 的正式版本，并有固定下载附件；然后 checkout 对应标签，执行 `make site-check`。
- 仅上传 `.build/site/`。构建 job 只有 contents:read；部署 job 只有 pages:write、id-token:write。
- 所有第三方 Actions 固定到通过 GitHub API 核对的官方标签 commit SHA；本仓库复用工作流使用对应发布版本中的实现。

不在部署流程中自动填 About Website。首次实际部署成功并确认 URL 可以打开后，再设置 Website。robots 与 sitemap 仅帮助发现网页，不保证搜索引擎收录时间或排名。

## 独立重试

官网失败不要求再次运行 `make release`。工作流合入后，可以在 Actions → Deploy release website → Run workflow，选择 master，并填写已经发布且包含官网源码的最新正式标签；也可执行：

```sh
gh workflow run pages.yml --ref master -f tag=vX.Y.Z
```

此命令只重试该版本官网，不改版本、不重发应用。拒绝部署旧版本或缺少固定下载名的版本，避免展示与当前正式版本不一致的页面。

## 本次验证与上线状态

已本地检查白名单、资源、锚点、封面、视频控制和版本替换；浏览器实际验证 1440px 桌面与 390px 手机布局无横向溢出，键盘 Tab 可访问跳转链接，视频可播放与暂停且解码尺寸为 1280×720。已核对 GitHub About、Topics、Pages 来源与环境规则，并验证版本名／固定名包的字节及校验和一致。

尚未执行线上 Pages 部署、标签工作流或真实浏览器下载最新别名；当前正式版尚不含该附件。Safari 等其他浏览器未实测。本地服务默认 4173，本次检查使用 4174，避免影响 Screenshot 的预览服务。

上线还需维护者提交推送本次改动，再正常发布一个新版本。官网将跟随该 Release 从标签源码部署。部署通过后确认页面及主下载链接，再填写 About Website。
