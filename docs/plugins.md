# 插件开发

## 接入模型

内置插件实现 `PluginSDK.CommandPlugin`，在宿主的装配入口注册。外部插件通过 `ExternalPlugin` 适配器实现同一接口；跨进程边界传递版本化消息，不传 Swift 对象或 SwiftUI 视图。

第一版内置插件为 `AppSwitchPlugin`。外部参考实现为 `Sources/ExamplePlugin`，使用 SDK 的 `PluginServer`；运行机器无需安装 Swift 或 Node。

## 包结构

```text
NativeMessage.hotkeyplugin/
  manifest.json
  ExamplePlugin.app/
    Contents/
      Info.plist
      MacOS/ExamplePlugin
```

入口也可以是包内其他相对路径的可执行文件。需要 AppKit、原生窗口或资源时建议包含 `.app`。这是插件的内部载荷，安装时整个包复制到宿主的本机插件目录，无需把载荷另装到“应用程序”目录。

清单示例见 `Examples/manifest.json`。必填字段：

| 字段 | 含义 |
| --- | --- |
| `id` | 稳定标识，使用小写字母、数字、点或短横线，例如 `example.native-message` |
| `name`、`version` | 面向用户的名称及版本 |
| `protocolVersion` | 当前为 `1`，不兼容时拒绝加载 |
| `executable` | 包内相对入口，禁止绝对路径与路径逃逸；资源中的相对链接必须指向包内 |
| `commands` | 稳定的命令 ID 与中文标题列表 |

安装包须包含所需全部资源和依赖。第一版不解析依赖、不下载文件、不编译用户提供的源码。开发者可以使用 Swift Package 发布源码，再构建成用户安装的插件包。

## 消息协议 v1

使用 stdin/stdout，每行一个 UTF-8 JSON；单条消息最多 256 KiB，stdout 禁止写诊断信息。stderr 会被宿主排空但不持久化。

请求示例：

```json
{"id":"request-1","method":"invoke","protocolVersion":1,"command":"show-message","configuration":{}}
```

响应示例：

```json
{"id":"request-1","protocolVersion":1,"success":true}
```

失败响应需提供 `success: false` 和简短 `error`，响应 `id` 必须与请求相同。

| 方法 | 约定 |
| --- | --- |
| `initialize` | 握手并确认协议版本，3 秒超时 |
| `invoke` | 执行声明过的命令；30 秒内回复。长期交互操作应在窗口打开、请求接受后回复 |
| `shutdown` | 取消进行中任务、关闭窗口、回复并退出 |

`configuration` 是命令实例的字符串键值配置。内置应用插件使用它存应用标识和路径。外部插件配置暂可通过配置文件提供；通用字段编辑器后续增加。

SDK 的 `PluginServer` 接收命令回调与退出回调，并在 stdin EOF 时调用退出回调。因此宿主意外退出时，正常使用 SDK 的插件也会结束。不要自行后台化或留下脱离插件生命周期的子进程。宿主仅管理其直接启动的进程，不提供任意进程树的强制清理。

宿主停用插件后立即撤销触发入口，再请求退出；宽限期结束后发送 SIGTERM，仍不退出则 SIGKILL。插件应在退出回调中取消内部任务。进程隔离用于减少崩溃影响，不是权限沙箱；能力声明也不构成系统授权。

## 安装与更新

添加插件时展示名称、版本、来源路径及可执行代码提示。相同 ID 的新包替换旧包，先停止旧进程，再检查新包握手；失败时回退旧包。相同命令 ID 的快捷键保留，移除的命令不继续触发。

停用会保留配置；移除会删除插件安装文件、保留命令绑定配置。重新安装同 ID 插件可恢复。导入配置只引用已安装的本机插件，不从配置中的任意外部路径启动程序。

未来截图项目可以独立产出符合此格式的插件。截图、选区和编辑界面由插件实现；权限归属需结合实际签名和打包方式验证。宿主不提前包含截图实现或请求截图权限。

## 后续扩展边界

菜单项可作为插件提供的声明数据，由宿主生成原生菜单，并指向已有命令 ID；无需重复实现快捷键和菜单动作。此版本尚未增加菜单协议字段，协议升级时通过明确版本处理。简单设置同样可采用声明字段，复杂设置由插件打开独立原生窗口。
