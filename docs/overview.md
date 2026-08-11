# AtomUI 用户手册案例文档

## 文档目标

本目录是 `AtomUIManualExamples` 源码仓库的长期维护入口。维护者只阅读本目录和仓库根 README，就应能够：

- 理解为什么每个条目必须是独立 Avalonia Browser 项目。
- 新增、修改、移动或删除一个条目。
- 正确维护 `catalog.json`、`metadata.json`、源码面板和共享项目。
- 单独 restore、publish 和验证指定 EntryKey。
- 理解 WebOS 如何同步、在 Docker 中构建并发布当前仓库。
- 理解用户手册如何解析标签、展示源码并延迟加载共享 .NET Runtime。
- 判断哪些修改需要 Full 构建，哪些修改可以 Entry 增量构建。
- 避免破坏运行时兼容、源码一致性、字体、安全和缓存边界。

## 阅读顺序

| 文档 | 解决的问题 |
|------|------------|
| [源码仓库架构](./architecture.md) | 仓库为什么这样分层；catalog、metadata、独立项目、共享源码、依赖和源码公开规则 |
| [文档项目预览整体架构](./project-preview-architecture.md) | Git 到 WebOS、Docker、Nginx、Markdown、Angular Hydration、源码面板和共享 Runtime 的完整链路 |

修改仓库结构、清单 schema、项目依赖或源码公开方式前，必须先阅读源码仓库架构。修改会影响构建产物、Markdown 标签、公开加载或 Runtime 兼容时，两份文档都必须阅读。

## 仓库职责

本仓库负责：

- AtomUI 官方用户手册条目的可审查源码。
- 根 `catalog.json` 和每个条目的 `metadata.json`。
- 独立 `.csproj`、`Program.cs`、`App.axaml`、项目依赖和 lock 文件。
- 允许共享的 class library 源码。
- 源码面板文件列表、预览建议尺寸和内嵌控件类型。
- 本地结构校验和独立项目构建入口。

本仓库不负责：

- Git 凭据和服务器工作目录。
- WebOS 数据库状态、版本、构建队列和发布代次。
- Docker Builder image、RuntimeProfile 和全站公开 Runtime identity。
- Nginx/CDN 物理地址和签名 URL。
- Markdown 解析器、Angular 组件或浏览器 RuntimeManager 实现。

这些平台能力由 AtomIdea DocsKit CodeCases 提供，但它们消费的仓库协议在本目录中完整说明。

## 当前基线

| 项目 | 当前值 |
|------|--------|
| ProductKey | `AtomUI` |
| AtomUI | `6.1.2` |
| TargetFramework | `net10.0-browser` |
| RuntimeIdentifier | `browser-wasm` |
| 根清单 | `catalog.json` schema 1 |
| 条目元数据 | `metadata.json` schema 1 |
| 字体 | Alibaba Sans 英文字体；不发布中文字体包 |
| 构建方式 | 离线 Docker 预编译；支持 Full 和 Entry |

## 最重要的不变量

1. 一个 ProductKey 只对应一个 Git 源码仓库。
2. 一个 EntryKey 只对应一个独立可执行 `.csproj`。
3. 每个条目都有自己的 Program、App、依赖和 lock。
4. 条目不能引用另一个条目的可执行项目。
5. 共享引用只能指向 catalog allowlist 中的 class library。
6. 正常同步和构建只通过 catalog 定位，不递归猜测目录。
7. `metadata.json.sources` 必须且只能有一个 primary 文件。
8. 二进制、源码、预览和 manifest 必须绑定同一构建身份。
9. 用户点击运行前不能请求 .NET Runtime、公共库或项目 package。
10. 同一 SPA 只允许一个兼容 RuntimeProfile identity，不创建第二个 Runtime。

## 常用维护命令

验证整个仓库：

```bash
./scripts/verify-repository.sh
```

独立构建当前 Button 条目：

```bash
dotnet restore entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj --locked-mode
dotnet publish entries/controls/button/basic/AtomUI.ManualExamples.Controls.Button.Basic.csproj -c Release --no-restore
```

维护者不能用“总解决方案可以编译”替代单条目验证。EntryKey 的正式构建路径必须始终可以独立执行。

## 协议变更规则

修改 `catalog.json` 或 `metadata.json` schema 时，必须同步评估：

- 仓库验证脚本。
- WebOS Source Sync catalog parser。
- Docker Worker 构建计划和 SourceHash 输入。
- ProjectSource 生成器。
- Public resolve DTO。
- Markdown preview component。
- 回归 fixture 和端到端测试。

不允许只修改 Git 文件格式，再让 WebOS 通过猜测兼容。schemaVersion 不受支持时应明确拒绝同步。
