# AtomUI Manual Examples 源码仓库架构

## 1. 文档定位

本文定义 AtomUI 用户手册案例源码仓库的正式结构、标识符、独立项目、共享源码、依赖、源码公开、离线构建和 WebOS 接入边界。

仓库负责维护可审查、可独立编译的 Avalonia Browser 源码。WebOS DocsKit 负责克隆或同步仓库、解析目录清单、在固定 Docker Builder 中构建、发布二进制与源码，并供用户手册通过稳定标识符引用。

当前基线：

- 产品：AtomUI。
- AtomUI：`6.1.2`。
- 目标框架：`net10.0-browser`。
- 运行方式：离线预编译，文档站按需加载发布产物。

版本基线只描述当前仓库状态。正式构建所使用的 .NET SDK、Avalonia、AtomUI、WASM workload、裁剪参数和 Docker image 由 WebOS RuntimeProfile 固定，源码仓库不能绕过或覆盖该身份。

## 2. 架构目标

- 一个产品只维护一个案例 Git 源码仓库。
- 一个条目对应一个稳定 `EntryKey` 和一个独立 Avalonia Browser 可执行项目。
- 每个条目可以独立 restore、build、publish 和启动，不需要加载总解决方案。
- WebOS 可以全量构建全部条目，也可以按 `EntryKey` 只构建一个条目。
- 条目可以引用登记过的共享 class library，但不能引用其他条目的可执行项目。
- 二进制、预览图、源码面板和源码归档必须来自同一 commit 和同一构建输入。
- 用户手册通过 `ProductKey + Version + EntryKey` 显式定位发布内容。
- 文档站首次进入页面时不加载 .NET Runtime；用户明确运行后才延迟加载。
- 同一 SPA 生命周期内，兼容的条目共享一个 .NET Runtime 和公共程序集。

## 3. 为什么采用这种项目结构

### 3.1 为什么一个条目一个独立可执行项目

每个条目都有自己的 `.csproj`、`Program.cs`、`App.axaml`、NuGet 依赖和 lock 文件。这样做不是为了增加项目数量，而是为了把构建、依赖和发布风险限制在单个 EntryKey 内。

如果多个条目共用一个可执行项目或统一 BrowserHost，会产生以下问题：

- 任意条目的依赖变化都可能改变整个宿主的 restore 图和裁剪结果。
- 单条目构建仍然需要编译全部条目，无法实现真正的 Entry 增量构建。
- 一个条目的 XAML、资源、静态初始化或程序集冲突可能破坏其他条目。
- 无法准确计算单条目的 SourceHash、PackageHash、体积和发布责任边界。
- 文档只引用两个条目时，构建和运行仍可能被迫携带全部条目。

独立可执行项目让 WebOS 能够从 EntryKey 直接定位一个 `.csproj`，只 restore/publish 当前项目及其共享依赖闭包。它也为 standalone smoke test 和预览截图提供完整启动入口，避免文档内嵌运行成为唯一验证方式。

接受的代价是仓库会包含较多 `.csproj`、`Program.cs`、`App.axaml` 和 lock 文件。这个重复应通过模板、生成脚本和仓库 lint 管理，不能用共享可执行宿主换取表面上的文件减少。

### 3.2 为什么 catalog.json 是唯一条目索引

Worker 不递归扫描目录或猜测项目，而是只读取根 `catalog.json`。原因是物理目录不是稳定业务身份，递归发现也无法可靠判断：

- 哪个 `.csproj` 是主可执行项目。
- 哪些 class library 可以共享。
- 哪些目录只是工具、模板、归档或实验内容。
- 未登记目录应该参与构建还是应该报告为 orphan。

catalog 把 `EntryKey -> directory + metadata + project` 变成显式、可版本化和可校验的映射。Full 构建可以按 catalog 稳定排序，Entry 构建可以 O(1) 定位目标，源码同步可以在不执行 restore 的情况下完成结构验证。

### 3.3 为什么目录使用 entries/，身份使用 EntryKey

`entries/` 只是源码的物理分类根，可以按 controls、data-entry、navigation 等主题继续分层。公开引用永远使用 EntryKey，不使用目录名。

这样可以在不破坏用户手册引用的前提下调整目录、项目名或分类。`Button_Basic` 可以从一个物理目录移动到另一个目录，只需要更新 catalog；文档中的 `product + version + key` 不变。

### 3.4 为什么 metadata.json 与项目文件分离

`.csproj` 负责 MSBuild、依赖和编译输入，`metadata.json` 负责文档展示和发布描述。两者分离可以避免为了文档 UI 往 MSBuild 文件中塞入非构建属性，也避免 WebOS 必须解析任意自定义 MSBuild 表达式。

metadata 明确描述：

- 稳定 EntryKey 和显示标题。
- 内嵌运行的 `entryControlType`。
- 预览尺寸和暗色模式能力。
- 源码面板公开哪些文件、默认打开哪个文件以及显示顺序。
- 完整源码归档是否包含项目与共享项目。

这种分离让源码展示可以独立演进，同时仍通过 SourceHash 保证展示源码与编译二进制来自同一输入。

### 3.5 为什么每个项目维护自己的 NuGet 依赖和 lock

每个项目声明实际使用的包并提交自己的 `packages.lock.json`，可以独立执行 `dotnet restore --locked-mode`，并准确回答“这个条目为什么需要某个程序集”。

仓库根禁止使用会影响全部项目的 `Directory.Packages.props`，是为了避免一个项目升级包版本时隐式改变其他所有条目的依赖图、裁剪结果和 RuntimeLibrary 兼容性。确需统一管理的封闭项目组可以使用局部 Central Package Management，但作用域不能越过该子树。

正式构建版本仍由 RuntimeProfile 校验。项目 lock 是源码依赖事实，RuntimeProfile 是全站 .NET/Avalonia/AtomUI/Docker 兼容身份；两者必须同时满足，不能互相替代。

### 3.6 为什么只允许 allowlist 共享 class library

完全禁止共享会导致主题辅助、公共测试数据和纯展示逻辑重复；允许任意 ProjectReference 又会让条目重新耦合。因此仓库只允许引用 `catalog.json.sharedProjects` 中登记的 class library。

allowlist 共享项目必须纳入引用条目的 SourceHash、BuildPlanHash 和源码归档。共享项目变化时，所有引用条目都会失效并重新构建。共享项目不能包含 Browser 启动入口，也不能反向引用条目。

共享源码项目与浏览器 RuntimeLibrary 是两个不同层次：前者是源码复用关系，后者是由 RuntimeProfile 管理、按程序集 identity/hash 在 SPA 中共享加载的发布产物。不能因为源码被多个条目引用，就自动把它当成浏览器公共库。

### 3.7 为什么禁止共享 BrowserHost

仓库级 BrowserHost 会把所有条目绑定到一个可执行程序集和统一注册表，直接破坏独立编译、单条目发布和依赖隔离。文档站需要共享的是 .NET Runtime 和经过兼容校验的 RuntimeLibrary，而不是源码仓库里的统一宿主项目。

每个条目的 `Program.cs` 只用于 standalone 运行、smoke test 和预览捕获。AtomUINET 内嵌运行通过平台 Runtime bridge 按 `entryControlType` 创建控件，因此既能保持项目独立，又能在浏览器中共享一个 Runtime。

### 3.8 为什么总解决方案只服务 IDE

`.slnx` 方便开发者打开仓库、浏览项目和执行人工全仓检查，但不是 Worker 的发现或构建入口。Worker 如果依赖总解决方案，新增一个无关项目就可能改变单条目构建结果，并使 Entry 构建退化成全仓 restore。

因此 catalog 是机器协议，solution 是开发工具。二者都登记项目，但职责不能交换。

### 3.9 为什么源码文件必须显式登记

源码面板只公开 `metadata.json.sources` 中列出的 UTF-8 文本文件。显式列表可以：

- 保证默认文件、顺序和语言高亮稳定。
- 避免把生成文件、凭据、二进制或无关实现暴露到公开站点。
- 让文档作者控制教学所需的最小源码集合。
- 在构建阶段验证文件存在、内容 hash 和 primary 唯一性。

完整 `source.zip` 仍保存可公开的构建输入闭包，用于下载和追溯；源码面板和完整归档承担不同职责。

### 3.10 为什么使用离线预编译和内容寻址发布

用户手册只需要展示官方已审核条目，不需要在线编辑。离线预编译可以把 restore、编译、裁剪、smoke test、预览捕获和安全扫描全部移到发布前完成，避免浏览器承担编译器、NuGet 和任意源码执行风险。

发布产物按内容 hash 存放后可以长期 immutable cache。Full/Entry 构建只产生新 hash，不覆盖旧文件；数据库通过 ActiveGeneration 原子切换公开版本。这同时支持 CDN/Nginx 高缓存命中、可靠回滚和二进制/源码一致性。

### 3.11 为什么运行时版本由 WebOS RuntimeProfile 统一

源码项目需要独立编译，但 AtomUINET SPA 不能为每个条目加载一套 .NET Runtime。RuntimeProfile 统一固定 Docker image、SDK、WASM workload、Avalonia、AtomUI、裁剪、公共程序集和 Runtime bridge identity。

所有需要在同一网站运行的版本都必须使用兼容 identity 重新构建。这样用户第一次点击运行时只加载一次 RuntimeCore，后续条目只加载缺少的 RuntimeLibrary 和 ProjectPackage。无法兼容统一 identity 的历史版本只保留预览和源码，不能在同一 SPA 偷偷启动第二个 Runtime。

## 4. 非目标

- 不提供在线编辑、浏览器编译、Roslyn、Hot Reload 或任意用户代码运行。
- 不在仓库中维护统一可执行 BrowserHost、跨条目注册表或共享启动入口。
- 不让条目自行决定正式 Docker image、SDK、RuntimeIdentifier、WASM workload 或全局裁剪策略。
- 不允许文档直接引用仓库地址、commit、项目路径、generation 或 artifact URL。
- 不通过总解决方案扫描或递归目录猜测条目。
- 不引入中文字体 NuGet、CJK WebFont 或静态中文字体文件。

## 5. 系统边界

```text
Git repository
  -> catalog.json
  -> independent entry projects
  -> allowlisted shared class libraries
  -> WebOS source synchronization
  -> fixed Docker Builder
  -> Full or Entry build
  -> source / package / preview validation
  -> immutable Nginx artifacts
  -> DocsKit Public resolve API
  -> manual preview component
  -> lazy shared .NET Runtime
```

仓库只提供源码事实。构建状态、发布代次、Nginx 地址、RuntimeProfile、运行时兼容性和文档引用关系属于 WebOS DocsKit，不写回 Git 仓库。

## 6. 稳定标识符

### 6.1 ProductKey

`ProductKey` 标识产品，当前固定为 `AtomUI`。它必须符合：

```text
^[A-Za-z_][A-Za-z0-9_]*$
```

### 6.2 EntryKey

`EntryKey` 是条目在产品范围内的稳定标识，例如：

```text
Button_Basic
Input_NumberBasic
DataGrid_Sorting
```

规则：

- 使用与 ProductKey 相同的标识符格式。
- 在仓库全部版本中保持稳定。
- 目录名、项目名或显示标题发生变化时，EntryKey 不变。
- 同一仓库内不得重复。
- 文档、构建、发布、源码和引用诊断都使用 EntryKey，不使用物理目录定位。

### 6.3 Version

`Version` 是 WebOS 管理的产品逻辑版本，例如 `6.1.2`。它绑定一个 Git ref，并在构建时解析为完整 commit SHA。

### 6.4 完整公开定位

```text
ProductKey + Version + EntryKey
AtomUI / 6.1.2 / Button_Basic
```

Markdown 必须显式提供三个值，不允许使用 `latest`、`current` 或依赖当前手册上下文。

## 7. 仓库目录结构

```text
AtomUIManualExamples/
├── docs/
│   ├── overview.md
│   ├── architecture.md
│   └── project-preview-architecture.md
├── catalog.json
├── global.json
├── AtomUI.ManualExamples.slnx
├── entries/
│   ├── controls/
│   │   └── button/
│   │       └── basic/
│   │           ├── metadata.json
│   │           ├── AtomUI.ManualExamples.Controls.Button.Basic.csproj
│   │           ├── packages.lock.json
│   │           ├── Program.cs
│   │           ├── App.axaml
│   │           ├── App.axaml.cs
│   │           ├── MainView.axaml
│   │           ├── MainView.axaml.cs
│   │           ├── README.md
│   │           └── wwwroot/
│   └── data-entry/                          # 后续按主题扩展
├── shared/                                  # 可选，仅放 allowlist class library
│   └── ThemeSupport/
│       └── AtomUI.ManualExamples.ThemeSupport.csproj
├── scripts/
├── templates/                               # 可选，重复结构增多后再引入
└── README.md
```

上图同时表示当前结构和允许的扩展位置。当前仓库只有 `entries/controls/button/basic`，`shared/`、`templates/` 和其他主题目录不是必需目录；没有实际内容时不创建空目录。

约束：

- `catalog.json` 是条目发现和定位的唯一事实来源。
- `AtomUI.ManualExamples.slnx` 只服务 IDE、导航和仓库级人工检查。
- WebOS 构建指定 EntryKey 时只读取 catalog 指向的项目，不加载总解决方案。
- 仓库根不放置会隐式统一所有项目依赖版本的 `Directory.Packages.props`。
- 需要局部 Central Package Management 时，只能作用于封闭子树，不能影响其他独立项目。

## 8. catalog.json

根目录 `catalog.json` 直接索引全部条目和允许共享的源码项目。

```json
{
  "schemaVersion": 1,
  "productKey": "AtomUI",
  "entriesRoot": "entries",
  "entries": [
    {
      "key": "Button_Basic",
      "directory": "entries/controls/button/basic",
      "metadataFile": "metadata.json",
      "projectFile": "AtomUI.ManualExamples.Controls.Button.Basic.csproj"
    }
  ],
  "sharedProjects": []
}
```

字段规则：

| 字段 | 必填 | 规则 |
|------|------|------|
| `schemaVersion` | 是 | 正整数；Worker 只接受明确支持的版本 |
| `productKey` | 是 | 必须与 WebOS 案例项目配置完全一致 |
| `entriesRoot` | 是 | 仓库相对路径，规范化后不能逃出仓库 |
| `entries` | 是 | 全仓库权威条目索引，key 不得重复 |
| `sharedProjects` | 是 | 可被条目引用的共享 class library allowlist，可为空数组 |

条目索引规则：

- `directory` 必须位于 `entriesRoot` 内。
- `metadataFile` 首期固定为 `metadata.json`。
- `projectFile` 只能定位一个主可执行 `.csproj`。
- 正常同步和构建不递归扫描目录。
- 仓库 lint 可以报告未登记的 orphan，但不能自动加入 catalog。

## 9. metadata.json

每个条目使用 `metadata.json` 描述展示信息、运行入口、预览尺寸和源码面板文件。

```json
{
  "schemaVersion": 1,
  "key": "Button_Basic",
  "title": "Button Types",
  "description": "The five basic AtomUI button types.",
  "entryControlType": "AtomUI.ManualExamples.Controls.Button.Basic.MainView",
  "preview": {
    "width": 900,
    "height": 254,
    "supportsDarkMode": true
  },
  "sources": [
    {
      "path": "MainView.axaml",
      "displayName": "MainView.axaml",
      "language": "xml",
      "primary": true,
      "order": 10
    },
    {
      "path": "MainView.axaml.cs",
      "displayName": "MainView.axaml.cs",
      "language": "csharp",
      "primary": false,
      "order": 20
    },
    {
      "path": "App.axaml.cs",
      "displayName": "App.axaml.cs",
      "language": "csharp",
      "primary": false,
      "order": 30
    },
    {
      "path": "AtomUI.ManualExamples.Controls.Button.Basic.csproj",
      "displayName": "Project file",
      "language": "xml",
      "primary": false,
      "order": 40
    }
  ],
  "sourceArchive": {
    "includeProject": true,
    "includeSharedProjects": true
  }
}
```

规则：

- `key` 必须与 catalog entry 完全一致。
- `entryControlType` 必须是发布 package 中可实例化的 Avalonia control type。
- `preview` 是默认建议尺寸，文档标签可以在允许范围内覆盖高度。
- `sources` 只控制文档旁边展示的源码文件，不代表完整编译输入。
- `sources` 必须且只能有一个 `primary=true`。
- source path 必须是 entry directory 内的 UTF-8 文本文件。
- `sourceArchive` 控制完整源码归档是否包含项目文件和引用的共享项目。

## 10. 独立项目契约

每个条目必须具备：

- 独立 `.csproj`。
- 独立 `Program.cs`。
- 独立 `App.axaml` 和 `App.axaml.cs`。
- 独立 Avalonia Browser 启动入口。
- 自己的 PackageReference。
- 自己的 `packages.lock.json`。
- 可独立运行的核心视图。
- 供 standalone smoke test 使用的最小 `wwwroot`。

每个项目必须可以单独执行：

```bash
dotnet restore <project.csproj> --locked-mode
dotnet publish <project.csproj> -c Release --no-restore
```

禁止：

- 引用其他条目的 `.csproj`。
- 依赖仓库级共享 BrowserHost 或统一 `Program.Main`。
- 读取仓库外文件或开发机绝对路径。
- 把凭据、私有 NuGet token 或环境秘密写入项目。
- 在项目中引入 Roslyn、在线编译器或 Hot Reload。
- 假设 Windows/macOS 路径大小写；正式构建以 Linux 容器为准。

`Program.cs` 用于 StandaloneProject 启动和构建 smoke test。文档内嵌运行由共享 Runtime bridge 按 `entryControlType` 创建控件，不要求执行条目自己的 `Program.Main`。两种入口必须展示相同核心内容。

## 11. NuGet 和版本边界

- 每个项目维护自己的 NuGet 依赖和 lock 文件。
- Worker 始终使用 locked restore；lock 不一致时构建失败。
- 条目可以只引用实际需要的 AtomUI 组件，但不能声明与 RuntimeProfile 不兼容的 AtomUI/Avalonia 主版本。
- 私有 NuGet source 和凭据由 Worker 受控注入，不能提交仓库。
- `global.json` 只服务本地开发提示，不能覆盖正式 RuntimeProfile。
- Entry 增量发布前必须校验 package assembly manifest 与当前发布代次兼容。

## 12. 共享源码项目

条目可以引用共享 class library，以复用主题辅助、测试数据或纯展示逻辑。共享项目必须：

- 位于 `shared/` 或 catalog 明确登记的目录。
- 出现在 `sharedProjects` allowlist。
- 是 class library，不包含 Browser 启动入口。
- 不引用任何条目项目。
- 不形成循环引用。
- 发生变化时使全部引用条目的 SourceHash 和 BuildPlanHash 失效。
- 被纳入引用条目的源码归档和构建输入闭包。

需要新增共享项目时，在 `catalog.json.sharedProjects` 中显式登记：

```json
{
  "key": "ThemeSupport",
  "projectFile": "shared/ThemeSupport/AtomUI.ManualExamples.ThemeSupport.csproj"
}
```

共享源码项目不等于浏览器 RuntimeLibrary。共享源码默认编译进引用条目的私有 ProjectPackage；只有具有稳定程序集身份、被 RuntimeProfile 明确登记并通过兼容验证的公共依赖，才能由文档站作为 RuntimeLibrary 共享加载。

## 13. 源码展示与归档

每个发布条目同时生成：

```text
source.json
source.zip
```

`source.json` 包含 `metadata.json.sources` 指定的源码面板文件、相对路径、语言、顺序和内容 hash。

`source.zip` 包含与构建匹配的可公开源码闭包，包括：

- `.csproj` 和 `packages.lock.json`。
- `Program.cs`、`App.axaml` 和 code-behind。
- XAML、C#、项目资源和局部 props/targets。
- 当前条目引用的 allowlist 共享项目源码。

必须排除：

- `.git`、`bin`、`obj`、IDE 缓存和本地 publish 输出。
- 凭据、密钥、Authorization、NuGet token 和私有 feed 配置。
- 宿主机绝对路径。
- 未登记外部文件和其他条目的源码。

源码、二进制和预览必须绑定同一 `SourceCommit`、`SourceHash`、`BuildPlanHash` 和 RuntimeProfile identity。任一必要 artifact 缺失或 hash 不一致时不得发布。

## 14. 离线 Docker 构建

正式构建全部在 WebOS 配置的固定 Docker Builder image digest 中进行。源码仓库不保存或覆盖生产构建镜像。

构建范围：

- `Full`：构建 catalog 中全部条目，用于首个发布、RuntimeProfile 迁移和公共 Runtime 变化。
- `Entry`：只构建一个 EntryKey，用于已有完整发布代次上的增量更新。

Entry 构建过程只定位目标 `.csproj` 和它的共享依赖闭包，不 restore、compile 或 publish 其他条目。

容器挂载边界：

```text
source workspace -> /workspace:ro
build output     -> /build:rw
artifact staging -> /artifacts:rw
NuGet cache      -> /nuget-cache:rw
/tmp             -> tmpfs
```

Builder 不得挂载 Docker socket、Git credentials、WebOS 配置或最终 Nginx public root。构建日志由 Worker 同步到 Foundation Operation Logs。

## 15. Artifact 和共享 Runtime

单个条目构建后至少产生：

| Artifact | 用途 |
|----------|------|
| `ProjectPackage` | 条目程序集、私有依赖、资源和入口 metadata |
| `ProjectSource` | `source.json` 与 `source.zip` |
| `ProjectPreview` | light/dark 预览图与尺寸信息 |
| `StandaloneProject` | 独立启动、smoke test 和预览捕获 |

公共 Runtime 由 WebOS RuntimeProfile 生成和管理：

| Artifact | 用途 |
|----------|------|
| `RuntimeCore` | .NET WASM、Avalonia Browser 基础、loader 和 Runtime bridge |
| `RuntimeLibrary` | AtomUI、Avalonia 和其他具有稳定程序集身份的公共库 |

仓库内每个条目仍然是独立可执行项目，但文档站不会为每个条目重复启动 .NET Runtime。AtomUINET SPA 在兼容 RuntimeProfile identity 下只创建一个 runtime promise，不同预览 slot 只异步加载各自 ProjectPackage。

关闭某个预览 slot 只销毁该控件实例，不 shutdown 全站 Runtime；同一文章的多个条目可以同时存在。

## 16. 用户手册引用

Markdown 使用：

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

- `product`、`version`、`key` 必须显式提供。
- `source=true` 时显示 `source.json` 中的多个源码文件。
- 查看源码不启动 .NET Runtime。
- 用户明确点击运行后才加载 RuntimeCore、RuntimeLibrary 和 ProjectPackage。
- Markdown 不允许提供项目路径、Git ref、artifact URL 或 RuntimeProfile。

## 17. 字体和资源

- 条目需要统一英文视觉时引用 `AtomUI.Fonts.AlibabaSans`。
- Alibaba Sans 作为英文字体使用，并纳入项目或公共 RuntimeLibrary 的版本和 hash。
- 不引入任何中文字体 NuGet、CJK WebFont、静态中文字体文件或中文系统字体名。
- 中文内容使用浏览器系统字体 fallback，不随条目发布字体包。
- 图片、JSON、字体和其他资源必须位于 entry 或 allowlist shared project 内，并进入构建 hash。
- 默认禁止运行时访问第三方远程资源；确有需要时必须由 RuntimeProfile 和 CSP 显式允许。

## 18. 路径和安全

Worker 对 catalog、metadata、source 和 ProjectReference 中的路径执行规范化和边界校验。以下情况直接失败：

- 绝对路径。
- `..` 或符号链接逃出仓库、entriesRoot、entry directory 或 shared allowlist。
- catalog 与文件系统大小写不一致。
- 多个 EntryKey 指向同一规范化目录或项目。
- source 文件不是 UTF-8 文本或超出公开体积预算。
- 项目引用未登记共享项目或其他条目。
- 公开源码中发现凭据、token、私有 feed 或宿主机路径。

## 19. 开发工作流

新增条目：

1. 从仓库模板创建独立 Browser WASM 项目。
2. 分配稳定 EntryKey。
3. 添加 `metadata.json`，登记预览和源码面板文件。
4. 为项目添加直接 NuGet 依赖并生成 `packages.lock.json`。
5. 在根 `catalog.json` 中登记目录、metadata 和 project file。
6. 把项目加入 `.slnx`，仅用于 IDE 导航。
7. 单独执行 locked restore 和 Release publish。
8. 执行仓库 lint，检查路径、引用、字体、源码和 catalog 一致性。

修改共享项目时，必须验证全部引用条目；修改单个条目时，不应触发其他无依赖条目的本地编译。

## 20. 仓库验收标准

- 仅通过 `catalog.json` 可以找到全部条目。
- 从 EntryKey 可以直接定位目录、`metadata.json` 和 `.csproj`。
- 每个条目具有独立 `.csproj`、`Program.cs`、`App.axaml`、启动入口、依赖和 lock 文件。
- 每个条目可以单独 locked restore 和 publish。
- Entry 构建不加载总解决方案，也不构建其他无关条目。
- 条目之间不存在 ProjectReference。
- 共享引用只指向 catalog allowlist 中的 class library。
- 源码展示文件与源码归档来自同一构建输入。
- 仓库和发布产物不存在中文字体包或中文字体文件。
- Alibaba Sans 英文字体可以在实际浏览器渲染中正确使用。
- `bin`、`obj`、凭据和宿主机路径不会进入公开 artifact。

## 21. 架构事实来源

- 本仓库的 `docs/overview.md` 是独立维护入口和阅读顺序。
- 本仓库的 `docs/architecture.md` 负责源码仓库内部约束及其设计理由。
- 本仓库的 `docs/project-preview-architecture.md` 负责从 Git、WebOS、Docker、Nginx 到 Markdown、Angular 和共享 Runtime 的完整平台契约。
- WebOS DocsKit 的 CodeCases 模块文档负责领域模型、同步、Docker Builder、发布、Nginx、Markdown 解析和共享 Runtime 实现。
- 两边协议发生变化时，必须在同一次变更中同步更新 `catalog.json`/`metadata.json` schema、Worker 校验和两边架构文档。
