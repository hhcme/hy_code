# 项目后台诊断

更新：2026-10-23，build 36（原 build 29 后台调度基线）。打开项目后自动检查项目源文件，错误、警告与建议汇总在左下角；点击计数打开“问题”，可按类别筛选、按文件分组并跳转到具体行列。分析不要求先在编辑器中打开文件。

## 当前范围

- Dart/Flutter 复用当前工作区的外部 Dart Analysis Server，初始化 `onlyAnalyzeProjectsWithOpenFiles: false`；未保存变更与关联文件由 SDK 的项目依赖图增量处理。SDK 缺失或启动失败显示实际状态，不能将零条结果解释为通过。
- JS/TS/JSX/TSX 复用工作区现有 TypeScript 服务，首次注册项目源文件并分批请求诊断。后续变更通过服务的 `fileReferences` 查找反向引用，包含间接导入和 re-export；不在 Swift 中猜测 import 文本。
- 全局脚本、全局声明、`.d.ts`、配置/JSON 变化、文件删除和依赖关系查询失败采用保守的项目范围检查；新增文件或目录结构变化重新发现源文件。普通模块编辑只检查自身与反向关联文件，不强制重查独立模块。
- HTML、CSS/SCSS/LESS、JSON/JSONC、YAML/YML 使用对应服务的后台文档注册与增量诊断。Vue 仍需先在 Web 分析面板显式信任工作区插件；未信任的 Vue 文件显示为未纳入范围，不自动执行插件。
- JSON/JSONC 的编辑内容也同步给 TypeScript，用于 `resolveJsonModule` 的导入方检查；JSON 在扫描前被打开时也保留原生未保存覆盖。因此打开 JSON/JSONC 编辑可能启动 TypeScript 服务。Swift 不为此持有第二份正式文本或撤销栈。

JSON/YAML 规则依赖在保存或外部文件变化后通知对应服务重新验证；全量重查包括已删除/曾读取失败的 Schema。监听保留非标准扩展名规则的文件事件，这类事件只刷新已观察的依赖，不因此注册未知语言或全扫 TS。`pubspec.yaml` 同时进入 YAML 后台文档刷新，不被 Dart 首次发现分支吞掉。详细规则与限制见[配置工具](CONFIGURATION_TOOLS.md)。

这是语法/类型及服务提供的建议，不等同于项目编译、测试或全套 WebStorm 检查。专用 ESLint/Prettier、更多框架规则、Rust/C/C++ 语义仍按原台账继续实现；基础高亮不能替代这些分析器。

## 调度与所有权

`ProjectAnalysisController` 只在 MainActor 管理状态与代次。目录扫描、元数据/正文读取、文件监听、诊断解码和项目问题排序在 utility 任务/队列或独立语言进程中执行。每个项目只有一个分析调度器；原生变更发出后合并 500 ms 再检查，文件事件也进入该调度器。UI 不等待扫描或分析完成。

TypeScript 与其他语言服务以独立进程执行，SDK 自己管理缓存和内部并发。不能把多个进程描述成 TypeScript 编译器本身已改为多线程，也没有实机帧率或“完全不影响渲染”的性能证明。每个 Node 进程 old-space 上限 512 MiB，后台读入每批 8 个文件、诊断每批 32 个文件并主动让出执行；TS 注册另外按最坏 JSON 转义预算拆包，使每次请求低于 8 MiB 消息限制；反向遍历超过 256 个查询转为项目检查。

TS 后台文件直接注册给同一个 tsserver，不进入 TLS 的交互缓冲列表，避免每次按键请求整个后台列表。磁盘更新显式携带最新 `fileContent`；后台注册与原生文档覆盖使用同一有序队列，原生脏缓冲始终优先。关闭原生文档后回交磁盘分析，耗时诊断不占用文档同步队列。无原生文档时不创建 Rust 正式编辑会话。

一条递归 FSEvents 流在 utility DispatchQueue 接收文件事件，不逐文件打开监听描述符、不使用主 run loop 轮询。监听失败仍执行首次检查，显示降级状态并保留编辑触发/手动重新检查。该监听只更新语言分析视图，**不自动重载或覆盖原生编辑缓冲**；磁盘与脏缓冲冲突仍由保存指纹处理。

切换/关闭项目会取消调度、停止本项目监听和服务，保留工作区访问生命周期直到清理结束；每个 await 后的可见状态提交校验项目代次。旧项目结果不进入新项目的问题列表。

## 资源与不完整结果

Web 发现预算为最多 50,000 个目录项、5,000 个源文件、64 MiB 源文件元数据总大小，单文件最多 1 MiB。不遍历符号链接或一般隐藏目录，明确允许 `.github` 与 `.vscode` 配置目录；排除 `node_modules`、`.git`、`.dart_tool`、`build`、`dist`、`coverage`、`Pods`、`vendor`、`target` 等依赖/产物；完整列表由 `ProjectSourceCatalog.excluded` 定义。扫描只读取元数据，后续按批读取受限的 UTF-8/BOM UTF-16 文本，通过逐级 `openat/O_NOFOLLOW` 防止路径替换后跟随链接。单个不可读/不支持编码的文件跳过，其他文件继续分析，可重新扫描重试。

Dart 的实际检查范围和排除规则由 SDK、工作区根目录及项目 `analysis_options.yaml` 等配置决定，不套用 Web 的 5,000 文件发现预算；Dart 项目分析器可能按其 SDK 配置加载项目插件。应用不为自动分析运行 Pub、package scripts 或构建命令。

每个语言所有者最多保留 500 个有问题 URI、每 URI 1,000 条、合计 5,000 条诊断；项目问题快照再按 5,000 条限制排序/筛选。错误为 LSP severity 1，警告为 2，信息/提示归为“建议”。重复项去重，清空诊断时移除 URI；计数不因当前筛选而改变。快照每 100 ms 合并更新，完整列表不在渲染期间重排。

超限、跳过文件、未信任 Vue、文件监听失败均在问题面板标注，左下角显示范围提示。结果代表已收到的诊断，不能据零计数宣称全项目干净。Dart 3.11.5 的无版本诊断与 TypeScript 的无版本项目诊断仍可能短暂陈旧，只用于显示，不成为自动写入依据；后续旧版本响应规则见各语言工具文档。

## 源码入口

| 路径 | 职责 |
| --- | --- |
| [ProjectSourceCatalog](../packages/HyCodeWorkspace/Sources/Language/ProjectSourceCatalog.swift) | 受限源文件发现和安全读取 |
| [WorkspaceSourceWatcher](../packages/HyCodeWorkspace/Sources/Language/WorkspaceSourceWatcher.swift) | 递归后台文件事件 |
| [WebProjectDiagnostics](../packages/HyCodeWorkspace/Sources/Language/WebProjectDiagnostics.swift) | 注册、磁盘/原生交接与依赖增量检查 |
| [LSPDocumentQueue](../packages/HyCodeWorkspace/Sources/Language/LSPDocumentQueue.swift) | 文档同步顺序和取消 |
| [ProjectAnalysisController](../app/macos/Sources/Language/ProjectAnalysisController.swift) | 工作区生命周期和合并调度 |
| [WorkspaceProblems](../packages/HyCodeWorkspace/Sources/Language/WorkspaceProblems.swift) | 纯数据问题快照 |
| [WorkspaceProblemsController](../app/macos/Sources/Language/WorkspaceProblemsController.swift) / [Panel](../app/macos/Sources/Language/WorkspaceProblemsPanel.swift) | 后台快照提交、计数和可跳转分组列表 |
| [ProjectAnalysisTests](../packages/HyCodeWorkspace/Tests/ProjectAnalysisTests.swift) | 扫描、编码、链接/FIFO 替换、预算、问题汇总、队列取消和 FSEvents 临时目录回归 |
| [Web 探针](../tools/WebProbe/ProjectDiagnosticsProbe.swift) / [Dart 探针](../tools/DartProbe/main.swift) | 固定真实服务与自有临时样本协议验证 |

## 验证边界

build 29 的 151 项 Swift、15 项 Rust 全量静默检查、14 项 Swift 地址检查、真实 SDK/包内 Web 服务临时样本和开发包元数据见[后台证据](evidence/2026-10-22-build29-project-analysis.json)。8 项新增模型/监听/队列回归包含扫描预算、链接/FIFO 替换安全；另 6 项为进程生命周期。Swift ASan 不等同于 Rust 静态库 sanitizer。

后台验证与开发包结果独立记录，不启动 HyCode 或其他 GUI，不读取用户项目或剪贴板，不执行项目脚本/安装依赖。不使用协议耗时或文件事件延迟推断窗口交互延迟。真实项目规模、窗口计数与点击定位、快速输入/滚动时帧率和旧系统运行仍未验收。

协议依据：[TypeScript tsserver 协议](https://github.com/microsoft/TypeScript/blob/main/src/server/protocol.ts)、[TLS 配置](https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md)、[Dart LSP 说明](https://github.com/dart-lang/sdk/blob/3.11.5/pkg/analysis_server/tool/lsp_spec/README.md)。本地固定版本与许可沿用 [Web 工具](WEB_TOOLS.md) 和[依赖台账](DEPENDENCIES.md)。
