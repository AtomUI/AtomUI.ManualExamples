# AtomIdea 文档项目预览整体架构

## 1. 文档定位

本文定义 AtomIdea DocsKit 如何把本仓库中的 Avalonia Browser 条目变成用户手册里的可预览、可查看源码、可按需运行的文档内容。

设计覆盖：

- Git 源码仓库管理和精确 commit。
- WebOS 案例项目、版本、构建环境和日志。
- 固定 Docker Builder 中的 Full/Entry 离线构建。
- 二进制、源码、预览和 manifest 的一致性发布。
- Nginx/CDN 内容寻址静态托管。
- Markdown 标签解析和文档引用诊断。
- Angular Hydration、源码面板和预览 fallback。
- AtomUINET SPA 单 .NET Runtime、公共库复用和多 slot 生命周期。
- 延迟加载、流量预算、错误降级和安全边界。

本文是平台接口和维护上下文，不要求源码仓库维护者了解 AtomIdeaCMS 内部实现代码。

## 2. 核心目标

- 文档作者只用稳定三元组引用条目，不接触仓库路径和 artifact URL。
- 管理员可以同步整个仓库、构建全部条目或只构建指定 EntryKey。
- 每个发布条目同时具有可运行二进制、源码、预览和完整追溯身份。
- 用户打开文章时只加载轻量正文、resolve、预览和接近视口的源码。
- 用户明确点击运行后才加载 .NET Runtime、公共 RuntimeLibrary 和 ProjectPackage。
- 同一 AtomUINET SPA 生命周期内，兼容条目共享一个 .NET Runtime。
- 一篇文章可以同时运行多个条目；销毁一个 slot 不影响其他 slot。
- 仓库有 100 个条目但文章只引用 2 个时，只解析和加载这 2 个。
- 运行时或程序集不兼容时降级为预览和源码，不创建第二个 Runtime。

## 3. 非目标

- 不提供在线编辑、在线编译、NuGet restore、Roslyn 或 Hot Reload。
- 不运行读者提交的源码，也不允许 Markdown 注入任意程序集或 URL。
- 不把 standalone Browser publish 直接嵌入 iframe 作为正式运行方案。
- 不让 WebOS Host 进程直接执行 Git、Docker 或 dotnet publish。
- 不为每个条目启动独立 Runtime。
- 不把 `latest`、当前手册版本或物理目录作为公开定位依据。
- 不把 Nginx 发布目录当作可变业务数据库。

## 4. 总体架构

```text
AtomUIManualExamples Git repository
  -> catalog.json + metadata.json + independent projects
  -> WebOS CodeCaseLibrary source synchronization
  -> exact Git commit workspace
  -> CodeCaseVersion + immutable RuntimeProfile revision
  -> AtomIdea.DocsKit.CodeCases.Worker
  -> fixed Docker Builder image digest
  -> Full or Entry build
  -> package/source/preview/standalone validation
  -> immutable ReleaseGeneration
  -> content-addressed Nginx PublicRoot
  -> DocsKit Public resolve/runtime-launch APIs
  -> Markdown inert placeholder
  -> Angular Hydrator + preview/source component
  -> SPA RuntimeManager
  -> shared RuntimeCore + RuntimeLibrary + per-entry ProjectPackage
```

控制面和数据面分离：

| 层 | 职责 |
|----|------|
| Git 仓库 | 源码、catalog、metadata、项目依赖和 lock |
| WebOS Admin | Library、Version、RuntimeProfile、Sync、Build、Release、日志和权限 |
| Worker/Docker | 受控同步、编译、裁剪、打包、预览、校验和发布 |
| Nginx/CDN | 只读托管内容寻址 artifact 和预压缩文件 |
| Public API | 三元组 resolve、引用诊断和点击运行时的受控 descriptor |
| AtomUINET | Markdown Hydration、源码展示、预览、延迟运行和多 slot 生命周期 |

## 5. 公开定位和不可变身份

文档只提交：

```text
ProductKey + Version + EntryKey
AtomUI / 6.1.2 / Button_Basic
```

三元组用于逻辑定位。一次实际发布和运行还具有：

```text
SourceCommit
SourceHash
BuildPlanHash
RuntimeProfileIdentityHash
PublicGeneration
ProjectPackageHash
ProjectSourceHash
ProjectPreviewHash
```

这些不可变值由后端解析和返回，不能写入 Markdown。这样文档保持可读，运行时又能防止旧页面把新旧 generation、runtime 和 package 混合加载。

## 6. 源码仓库契约

根 `catalog.json` 是唯一发现入口，每个 entry 指向：

```text
EntryKey
directory
metadata.json
executable .csproj
```

每个条目必须独立 restore/publish，并具有自己的 `Program.cs`、`App.axaml`、NuGet 依赖和 lock 文件。共享源码只能引用 catalog allowlist 中的 class library。

详细原因和字段协议见 [源码仓库架构](./architecture.md)。平台不能递归扫描目录弥补 catalog 错误，也不能接受旧文件名或隐式兼容格式。

## 7. WebOS 管理模型

### 7.1 CodeCaseLibrary

一个产品只有一个 Library，并直接绑定一个 Git 仓库：

```text
ProductKey AtomUI
  -> one CodeCaseLibrary
  -> one Git repository
  -> many CodeCaseVersion
  -> catalog contains many entries
```

Library 保存仓库平台、HTTPS 地址、默认分支、仓库根路径、catalog 路径、受控凭据和启用状态。凭据不回传 Public API，也不写入仓库。

### 7.2 CodeCaseVersion

Version 是用户手册使用的逻辑版本，例如 `6.1.2`。它绑定 Branch、Tag 或完整 Commit ref，以及一个不可变 RuntimeProfile revision。

状态：

```text
Draft -> Published -> Unpublished
```

Published 必须有完整、有效的 ActiveGeneration。已经 Published 的 Version 不能原地替换 RuntimeProfile identity；迁移必须使用新 profile 执行 Full rebuild。

### 7.3 RuntimeProfile

RuntimeProfile 是构建和浏览器运行兼容性的唯一事实来源。identity 至少覆盖：

- Docker Builder image tag 和 digest。
- .NET SDK、TargetFramework、RuntimeIdentifier。
- WASM workload、runtime pack graph 和 globalization。
- Avalonia、AtomUI、基础 NuGet 图和 Alibaba Sans 版本。
- trimming、Runtime contract、Runtime bridge 和 package generator。
- RuntimeLibrary 定义、依赖、程序集 identity 和内容 hash。

identity 字段不可原地修改，升级时创建新 revision。WebOS 可以统一配置当前网站使用 .NET 8、.NET 10 或后续版本，但同一公开站点必须锁定一个兼容 identity。

## 8. 源码同步

同步由 Worker 执行：

```text
WebOS create sync
  -> acquire task lease
  -> validate repository allowlist
  -> clone/fetch mirror cache
  -> resolve branch/tag/commit to full SHA
  -> detached checkout in isolated workspace
  -> read catalog.json
  -> validate entries/sharedProjects/project graph
  -> persist successful snapshot and operation result
  -> clean task workspace
```

同步阶段只做 Git、catalog、metadata、路径和静态项目图校验，不 restore 或编译。同步失败不能覆盖最近成功的 entry snapshot 或任何 Published generation。

必须拒绝：

- ProductKey 与 Library 不一致。
- 重复或非法 EntryKey。
- 目录逃逸、仓库外符号链接和大小写不一致。
- 缺少 metadata、`.csproj`、Program、App 或 lock。
- 跨条目 ProjectReference。
- 未登记共享项目。
- 非 UTF-8 source、多个 primary 或凭据泄漏。
- 中文字体包或公开 CJK 字体资源。

## 9. Docker 构建边界

正式构建只能在 RuntimeProfile 锁定的 Docker image digest 中进行。WebOS 表单、catalog、metadata 和 Build API 都不能覆盖 SDK、workload、RID、裁剪或命令模板。

```text
source workspace -> /workspace:ro
build output     -> /build:rw
artifact staging -> /artifacts:rw
NuGet cache      -> /nuget-cache:rw
/tmp             -> tmpfs
```

容器使用非 root、只读根文件系统、`cap-drop ALL`、`no-new-privileges` 和 CPU/内存/PID/超时限制。容器不能挂载 Docker socket、Git 凭据、WebOS 配置或最终 Nginx PublicRoot。

Worker 只生成固定命令类型：locked restore、controlled publish、package generation、standalone smoke test、preview capture、Brotli compression 和 manifest generation。仓库不能提交任意 shell 命令。

## 10. Full 和 Entry 构建

### Full

Full 构建读取同一 commit 的完整 catalog，按稳定顺序构建全部 entry。以下场景必须 Full：

- Version 首次发布。
- RuntimeProfile identity 迁移。
- RuntimeCore 或公共 RuntimeLibrary 图发生变化。
- 当前版本没有可作为增量基线的完整 generation。

### Entry

Entry 构建只接受一个 EntryKey，只 restore/publish catalog 指向的 `.csproj` 和共享依赖闭包，不加载总 solution，也不构建其他条目。

Entry 发布基于当前 ActiveGeneration copy-on-write：

```text
Generation 12
  Button_Basic -> package A / source A
  Slider_Basic -> package B / source B

Generation 13
  Button_Basic -> package C / source C
  Slider_Basic -> reuse B
```

共享项目变化时，所有引用该共享项目的 entry 都必须重新构建，不能伪装成单一 EntryKey 无影响更新。

## 11. 构建身份和源码一致性

Worker 在 restore 前捕获项目与共享项目的完整输入闭包并计算 SourceHash。Docker 从同一只读 workspace 编译，结束后再次确认输入未变化。

每个发布 entry 必须绑定：

```text
ProductKey
Version
EntryKey
SourceCommit
SourceHash
BuildPlanHash
RuntimeProfileIdentityHash
BuilderImageDigest
ProjectPackageHash
ProjectSourceHash
ProjectPreviewHash
StandaloneProjectHash
```

任一必需 artifact 缺失、hash 不一致、assembly manifest 冲突、smoke test 失败或超过 hard size budget 时，Build 不得发布。

## 12. Artifact 分层

```text
RuntimeCore
  + RuntimeLibrary[]
  + ProjectPackage[]
```

| Kind | 内容和用途 |
|------|------------|
| `RuntimeCore` | .NET WASM、Avalonia Browser 基础、loader、Runtime bridge、多 slot 和主题同步 |
| `RuntimeLibrary` | 具有稳定程序集 identity/hash 的 AtomUI、Avalonia 和公共资源 |
| `ProjectPackage` | 单条目程序集、私有依赖、编译资源、entryControlType 和公共库 exact hashes |
| `ProjectSource` | `source.json`、`source.zip`、SourceCommit 和 SourceHash |
| `ProjectPreview` | light/dark fallback 图、尺寸和 preview toolchain identity |
| `StandaloneProject` | 独立启动、smoke test、诊断和预览捕获 |
| `ReleaseManifest` | 一个 generation 中全部 entry 和 artifact hash 的不可变索引 |

ProjectPackage 不包含 RuntimeCore、重复 RuntimeLibrary、源码或 standalone shell。源码展示不会迫使浏览器下载可运行 package。

## 13. 原子发布和回滚

```text
Build output
  -> BuildId staging
  -> hash/MIME/source/assembly/size/smoke validation
  -> precompress static files
  -> move to content-addressed public paths
  -> create Staging generation
  -> database transaction switch ActiveGeneration
  -> increment PublicGeneration
```

物理 artifact 先进入不可变内容寻址目录，数据库后切换公开指针。事务失败时旧 ActiveGeneration 保持；未引用文件由 cleanup worker 清理。

回滚只切换到同 Version、同 RuntimeProfile identity 且 artifact 完整的历史 generation，不重新构建或复制文件。每次发布和回滚都增加 PublicGeneration，使已打开页面的旧 launch descriptor 自动失效。

## 14. Nginx/CDN 托管

```text
PublicRoot/
├── runtime/{runtime-profile-identity-hash}/
├── libraries/{artifact-hash}/
├── packages/{artifact-hash}/
├── sources/{artifact-hash}/
│   ├── source.json
│   ├── source.json.br
│   └── source.zip
├── previews/{artifact-hash}/
├── standalone/{artifact-hash}/
└── releases/{release-manifest-hash}/manifest.json
```

Nginx 只读挂载 PublicRoot，支持 `application/wasm`、`brotli_static`、gzip fallback、immutable cache 和站点需要的 CORS/CSP/COEP/COOP。

Preview 和 Source 可以通过 resolve 返回长期内容寻址 URL。RuntimeCore、RuntimeLibrary 和 ProjectPackage 只能在用户点击运行后通过短期 runtime-launch descriptor 下发。

## 15. Markdown 标签

唯一正式标签：

```html
<avalonia-project-preview
  product="AtomUI"
  version="6.1.2"
  key="Button_Basic"
  height="320"
  source="true"
/>
```

规则：

- `product`、`version` 和 `key` 必填，不依赖当前手册上下文。
- 不支持 `latest`、`current`、项目路径或 artifact URL。
- `height` 受 Public 配置限制，默认使用 metadata preview height。
- `source` 默认 true，只控制源码区域，不控制是否可运行。
- 未知属性、重复属性、非法值、非自闭合标签和任意子 HTML 都是解析错误。

后端手册同步解析标签、保存 `CodeCaseDocumentReference` 和发布诊断，但保留规范化标签，不把它提前改写成可执行 HTML。

## 16. Angular Markdown 和 Hydration

公开 Markdown renderer 把标签转换为 inert placeholder：

```html
<span
  data-docskit-avalonia-project-preview
  data-product="AtomUI"
  data-version="6.1.2"
  data-key="Button_Basic"
  data-height="320"
  data-source="true">
</span>
```

renderer 不拼接 script、iframe 或 artifact URL。正文进入 DOM 后，Hydrator：

1. 在当前 ArticleHost 内查找未处理 placeholder。
2. 为每次 occurrence 创建稳定 slotId。
3. 按页面去重三元组。
4. 一次批量调用 Public resolve。
5. 使用 Angular `createComponent` 创建 preview component。
6. 注入 descriptor、articleHostId 和 slot identity。
7. 路由离开时释放文章组件和 slots。

Hydrator 必须幂等，主题切换、局部刷新或 Signal 更新不能重复创建组件。

## 17. Public resolve 和 runtime launch

### Resolve

```text
POST /api/public/docskit/code-cases/resolve
```

输入为页面去重后的 `references[] { product, version, key }`。响应包含统一 RuntimeProfile identity、逐条 availability、显示信息、PublicGeneration、package hash、required libraries、preview/source descriptor 和诊断。

Resolve 不返回 RuntimeCore、RuntimeLibrary 或 ProjectPackage URL，因此文章初次加载无法误触发重资源下载。

### Runtime launch

```text
POST /api/public/docskit/code-cases/runtime-launches
```

点击运行时提交：

```text
ProductKey
Version
EntryKey
ExpectedPublicGeneration
ExpectedRuntimeProfileIdentityHash
ExpectedPackageHash
```

服务端重新解析 Published version 和 ActiveGeneration。校验成功后返回有过期时间的 RuntimeCore、按依赖顺序排列的 RuntimeLibrary 和 ProjectPackage URL/hash/entryControlType。任一 expected 值过期则返回 stale，前端重新 resolve。

## 18. Preview 和源码面板

初始状态展示 ProjectPreview，而不是空白 WASM 容器。运行成功后真实 Avalonia slot 在同一区域替换 fallback；运行失败时仍保留预览和源码。

桌面宽屏使用 Preview 44% / Source 56% 的单一完整区域；平板竖屏和手机使用“预览 / 源码”Tabs。两侧不嵌套成卡片，固定内容高度，源码区域内部滚动。

`source.json` 为每个文件提供 path、displayName、language、order、primary、contentHash 和转义后的文本内容。源码面板默认打开唯一 primary 文件，并提供复制当前文件、下载 `source.zip` 和打开 exact-commit 仓库目录。

查看源码不启动 Runtime。`source.json` 接近视口时加载，`source.zip` 只在用户下载时请求。

## 19. SPA RuntimeManager

RuntimeManager 是 AtomUINET 根级单例：

```text
ensureRuntime(profileIdentity)
ensureLibraries(requirements)
ensurePackage(projectLocator, packageHash)
mount(articleHostId, slotId, entryControlType)
unmount(articleHostId, slotId)
releaseArticle(articleHostId)
```

加载顺序：

```text
文章初次渲染
  -> resolve lightweight metadata
  -> preview/source visible
  -> Runtime requests = 0

用户运行第一个条目
  -> runtime launch
  -> RuntimeCore once
  -> required RuntimeLibrary closure
  -> selected ProjectPackage
  -> mount slot

用户运行第二个条目
  -> reuse RuntimeCore
  -> reuse loaded libraries
  -> load only missing libraries and package
  -> mount second slot without removing first
```

RuntimeManager 按 identity/hash 合并进行中的 Promise，避免并发重复请求。第一个成功 Runtime 锁定 SPA identity；后续 identity 不一致时拒绝 launch，不创建第二个 Runtime。

## 20. 多 slot 和页面生命周期

- 每个标签 occurrence 对应独立 slotId。
- 同一三元组重复出现时共享网络缓存，但创建独立控件实例。
- 启动第二个 slot 不注销第一个 slot。
- `unmount` 只销毁当前控件，不卸载 Runtime 或 managed assemblies。
- 离开文章时释放该 ArticleHost 的所有 slots。
- Runtime 和已加载 libraries 保留到 SPA 生命周期结束或整页刷新。
- 一篇文章或不同文章可以先后复用同一 Runtime。

.NET Runtime 不能安全卸载已经加载的 managed assembly，因此 package 和 assembly identity 冲突必须在构建、发布、resolve 或 launch 阶段提前拒绝。

## 21. 延迟加载和流量策略

文章首次渲染允许：

- 文档正文和轻量批量 resolve。
- 进入视口的 preview 图片。
- `source=true` 且接近视口的 source.json。

点击运行前禁止：

- RuntimeCore。
- RuntimeLibrary。
- ProjectPackage。
- StandaloneProject。
- `.wasm` 和 `_framework/**` 重资源。

仓库存在 100 个 entry 但当前文章引用 2 个时，其余 98 个不能产生 resolve entry、source、preview、package 或 runtime 请求。

内容寻址和 Brotli 静态压缩减少重复流量，但不能替代延迟加载。即使首次 Runtime 为 4-10 MiB，也必须把它推迟到明确运行操作之后。

## 22. 当前体积事实和预算

已经完成的 Standalone Button 实验：

| 场景 | 实际 Brotli 响应体 |
|------|-------------------:|
| 完整 `UseDesktopControls()` | `7,013,011 B` / `6.688128 MiB` |
| 实验性 Button-only 注册 | `4,993,671 B` / `4.762336 MiB` |
| 下降 | `28.79%` |

这些数据是包含独立 Runtime 的 Standalone 冷加载，不是最终共享 Runtime 首项目数据。`3-4 MiB` 目标尚未实测达成，不能写成验收结果。

当前简单 Button 项目程序集 Brotli 约 `6.7 KiB`。共享 Runtime 和相同 libraries 已加载后，第二个复杂度相近条目预计新增 `8-16 KiB Brotli`，但这仍是估算，必须通过 `SecondProjectIncremental` 真实浏览器场景验证。

RuntimeProfile 应分别记录：FirstProjectCold、SecondProjectIncremental、单 ProjectPackage、Source 和文件数量的 warning/hard budgets。

## 23. 兼容性和降级

批量 resolve 对页面所有引用计算统一计划：

- RuntimeProfileIdentityHash 必须一致。
- required RuntimeLibrary exact hash 闭包必须可合并。
- ProjectPackage assembly manifest 不能出现同 identity 不同 hash。

不兼容时：

- 对受影响条目返回 FallbackOnly 和诊断。
- 继续显示 ProjectPreview 和 ProjectSource。
- 不显示可用运行按钮。
- RuntimeManager 不创建第二个 Runtime。

无法使用当前统一 RuntimeProfile 重建的历史版本可以保留文章、源码和预览，但必须下线运行能力。

## 24. 错误处理

| 失败 | 行为 |
|------|------|
| Resolve 不可用 | 当前组件显示不可用诊断，不影响文章其他内容 |
| Preview 失败 | 显示稳定错误状态，源码仍可使用 |
| Source 加载失败 | 只影响源码 pane，不触发 Runtime |
| Runtime 初始化失败 | 当前运行区域失败，预览和源码保留 |
| Package 加载失败 | 只影响当前 slot，其他 slots 继续运行 |
| Launch descriptor 过期 | 重新 resolve，校验新 generation 后再决定重试 |
| Runtime identity 冲突 | 降级 fallback，不创建第二 Runtime |
| Runtime 不可恢复 | 所有运行 slot 标记失败，通过整页刷新重置 |

## 25. Operation Logs

源码同步、构建、发布和 Worker 状态全部复用 Foundation Operation Logs：

```text
CodeCaseSourceSync
CodeCaseBuild
CodeCasePublish
CodeCaseWorkerHealthCheck
CodeCaseWorkerNodeChanged
```

Worker 把 stdout/stderr 做行切分、ANSI 清理、凭据/路径脱敏、长度限制和等级分类后写入 Operation。WebOS 通过 persisted sequence 和 SignalR 显示实时日志，断线后使用 `afterSequence` 补齐。

日志不能出现 access token、Authorization、NuGet key、宿主机 workspace、Docker socket 或带凭据命令行。

## 26. 安全边界

- product/version/key 只用于数据库查询，不能拼接文件系统路径。
- Git 只允许配置的 GitHub/Gitee HTTPS host。
- Builder 使用固定 image digest 和受控命令，不执行 catalog shell。
- Source/Preview URL 由后端根据 Published artifact 生成。
- Runtime URL 使用短期签名或等价受控 descriptor。
- Public DTO 不返回 token、宿主机路径、Docker 命令、日志或 NuGet source。
- source 高亮必须转义文本，不能信任源码 HTML。
- Nginx PublicRoot 对 Builder 只读隔离，对 Nginx 只读挂载。
- 不发布中文字体包；Alibaba Sans 只作为明确版本化的英文字体资源。

## 27. 管理和公开 API 边界

| Surface | Prefix | 职责 |
|---------|--------|------|
| WebOS Admin | `/api/webos/docskit/code-cases` | Library、Version、Sync、Entry、Build、Release、RuntimeProfile、Worker、Artifact 和 Reference 管理 |
| Public | `/api/public/docskit/code-cases` | 批量 resolve、preview/source descriptor 和 runtime launch |

Public 不提供管理列表、仓库配置、构建、Worker、容器或日志信息。Admin API 也不直接返回凭据明文或允许提交任意构建命令。

## 28. 维护者工作流

### 新增条目

1. 创建独立 Browser WASM 项目和稳定 EntryKey。
2. 添加 Program、App、核心视图、依赖和 lock。
3. 创建 metadata，登记 entryControlType、preview 和 source 文件。
4. 更新 catalog 和 `.slnx`。
5. 运行仓库验证、独立 locked restore 和 Release publish。
6. 提交 Git 后，在 WebOS 同步仓库。
7. 对目标 Version 执行 Full 或 Entry Build。
8. 验证 source/package/preview/standalone 和 Operation Logs。
9. 发布 generation 后在手册中使用显式标签。

### 修改条目

- 只修改当前 entry 且 RuntimeProfile/共享图不变：可以 Entry Build。
- 修改 allowlist shared project：重建全部引用 entry。
- 修改 RuntimeProfile、RuntimeCore 或 RuntimeLibrary 图：必须 Full Build。
- 修改 metadata sources：重新构建 ProjectSource 和 preview/package 一致性校验。
- 删除 entry：先检查文档引用和历史 generation，再通过新 Full generation 移除。

## 29. 验收矩阵

### 仓库

- catalog 可直接定位所有 entry，没有 orphan metadata。
- 每个 entry 可独立 locked restore/publish。
- 无跨条目 ProjectReference 和共享 BrowserHost。
- source 列表、字体和路径规则通过仓库校验。

### 构建发布

- 固定 Docker image digest，源码只读。
- Full 首次发布完整，Entry 只替换目标 artifact。
- 二进制、源码、预览、manifest hash 可追溯。
- 发布失败不切换 ActiveGeneration，回滚增加 PublicGeneration。
- Nginx 返回预压缩内容寻址文件且不允许覆盖。

### 文档页面

- 同一页面只执行一次去重批量 resolve。
- 首屏没有 RuntimeCore、RuntimeLibrary、ProjectPackage、`.wasm` 或 `_framework/**` 请求。
- Source tab 只加载 source.json 和高亮资源。
- 第一个条目运行后只初始化一次 Runtime。
- 第二个条目只加载缺少的 library/package，第一个继续交互。
- 未引用 entry 没有网络请求。
- 不兼容 identity 只降级 fallback。
- PC/平板/手机和 light/dark 下无重叠、溢出或不可读状态。

## 30. 架构不变量总结

1. 源码独立，运行时共享。
2. catalog 显式定位，目录不能成为公开身份。
3. 构建离线完成，浏览器只加载已发布结果。
4. Preview/Source 与 Runtime 解耦，查看内容不触发 WASM。
5. 第一次运行延迟加载 Runtime，后续条目增量加载 package。
6. 一个 SPA 一个 Runtime identity，多 slot 共存。
7. 内容寻址、不可变 generation 和 expected hashes 防止新旧产物混用。
8. 任一不兼容或失败都优先降级，不以重复 Runtime 或在线编译规避架构约束。
