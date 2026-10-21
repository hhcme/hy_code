> 历史快照：2026-10-21 更名前的文件浏览器文档。正式名称现为 HyCode，旧实现已按用户要求删除，本文的代码路径、命令、能力与旧产品约束只说明当时状态。当前开发以 [HyCode README](../../../../README.md) 为入口。

# 代码编辑与语言服务

> **2026-10-21 编辑器方向更新**：最新定位改为轻量、原生、完全开源的代码编辑器，借鉴 IDEA 界面组织。先读 [新方向与优先级](EDITOR_DIRECTION.md)；本文旧文件浏览器主线、强制复制入库、付费解锁及商店优先规则遇冲突时仅作历史记录。候选能力和骨架实现状态仍需分别看待。

更新日期：2026-10-21。本页承接独立万能文件浏览编辑器的代码能力方向，记录可复用组件与实施边界。候选不是已安装依赖，也不代表已经验证或支持所有端。

## 1. 能力分层

| 层 | 产品能力 | 实现方向 | 平台范围 |
| --- | --- | --- | --- |
| 原生文本编辑 | 光标/选择、IME、撤销重做、行号、缩进、查找替换、保存与草稿 | 平台编辑控件 + 共享文档/保存事务 | 全端目标 |
| 语法与结构 | 语法高亮、括号匹配、折叠、结构导航、关键词/文档单词提示 | 优先复用 Rust 高亮库；增量语法解析候选 Tree-sitter | 全端逐端验证 |
| 语义服务 | 成员补全、参数提示、类型说明、定义/实现/引用、诊断、重命名 | 独立语言服务，通过 LSP 接入 | 桌面优先；移动端另评估 |

Tree-sitter 是增量语法解析库，核心 C11，有 Rust 绑定；它不自动解决跨文件类型、依赖和准确引用。LSP 是编辑器与服务之间的协议，服务实现可以使用 Rust、Go、Swift、C++、TypeScript、Java 等，无需全部自研或改写为 Rust。

依据：[Tree-sitter](https://tree-sitter.github.io/tree-sitter/)、[LSP 与语言服务](https://code.visualstudio.com/api/language-extensions/language-server-extension-guide)。

当前本仓尚无文本编辑器、高亮或 LSP 实现；HyHub 的 TextKit 2 + syntect 是迁移参考，不能写成本仓已完成。

## 2. 编程语言服务候选

“官方”按维护方区分：LLVM、Eclipse、Microsoft/Astral 的第三方语言服务不等于语言标准组织或语言官方。许可列只记录主项目初筛；内置发行包时另核对所选版本、依赖、通知与再分发条件。

| 语言 | 候选与来源 | 维护方 | 运行/项目条件 | 主项目许可或状态 |
| --- | --- | --- | --- | --- |
| Rust | [rust-analyzer](https://github.com/rust-lang/rust-analyzer) | Rust 项目 | 独立程序，Rust/Cargo、标准库源码 | MIT / Apache-2.0 |
| Swift | [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) | Swift 官方 | Swift/Xcode 工具链及项目构建信息 | Apache-2.0 |
| C/C++/Objective-C | [clangd](https://clangd.llvm.org/) | LLVM 项目 | SDK、头文件、编译参数/编译数据库 | Apache-2.0 + LLVM 例外 |
| Go | [gopls](https://go.dev/gopls/) | Go 官方团队 | Go 工具链、模块及依赖信息 | BSD-3-Clause |
| Dart/Flutter | [Analysis Server](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md) | Dart 官方 | SDK 内 `dart language-server`，项目依赖 | BSD-3-Clause |
| JS/TS/JSX/TSX/React | [TypeScript Language Server](https://github.com/typescript-language-server/typescript-language-server) | 官方 tsserver + 社区 LSP 适配 | 现有路线使用 Node.js、TypeScript、项目配置 | Apache-2.0，含 MIT 部分 |
| Vue | [Vue Language Tools](https://github.com/vuejs/language-tools) | Vue 官方项目 | Node.js、TS，处理单文件组件及混合语言 | MIT |
| Python | [Pyright](https://github.com/microsoft/pyright)、[ty](https://github.com/astral-sh/ty) | Microsoft / Astral，非 Python 官方 | Pyright 使用 Node.js；ty 为 Rust 程序；依赖环境需正确解析 | 均 MIT；ty 当前 Beta |
| Java | [Eclipse JDT LS](https://github.com/eclipse-jdtls/eclipse.jdt.ls) | Eclipse | JDK 21+，Maven/Gradle 项目 | EPL-2.0 |
| Kotlin | [Kotlin LSP](https://github.com/Kotlin/kotlin-lsp) | JetBrains 官方 | JVM 及项目环境 | 当前 Alpha，部分实现闭源，发行包另审 |
| C# | [Roslyn Language Server](https://github.com/dotnet/roslyn/tree/main/src/LanguageServer/roslyn-language-server) | .NET / Microsoft 官方 | .NET 运行环境与项目 SDK | MIT；当前工具安装文档使用预发布包 |
| PHP | [Phpactor](https://github.com/phpactor/phpactor) | 社区 | PHP 环境；上游提示已有其他新方案 | MIT，后续选型复核 |
| Ruby | [Ruby LSP](https://github.com/Shopify/ruby-lsp) | Shopify | Ruby/Bundler 项目环境 | MIT |
| Lua | [LuaLS](https://github.com/LuaLS/lua-language-server) | 社区 | 对应平台的服务发行包 | MIT |
| Bash/sh | [Bash Language Server](https://github.com/bash-lsp/bash-language-server) | 社区 | Node.js；ShellCheck/shfmt 为补充工具 | MIT |

TypeScript 官方 [Go 原生实现](https://github.com/microsoft/typescript-go) 也在提供 LSP，当前进度仍列为进行中，作为后续候选，不能直接替代已经验证的基线。Pyright 与闭源 [Pylance](https://github.com/microsoft/pylance-release) 是不同产品，不按 Pyright 的 MIT 许可处理 Pylance。Kotlin 仓库的开源标记也不能代替全部发行组件许可。

以上为截至本次查阅的状态；实施时选择固定版本，重新核对接口、能力、架构和许可，不能一直使用浮动 latest 作为发布依赖。

## 3. 网页、配置与文档服务候选

| 格式 | 候选 | 重点与边界 |
| --- | --- | --- |
| HTML | [Microsoft HTML Language Service](https://github.com/microsoft/vscode-html-languageservice) | 标签/属性、悬停和链接，服务库需要适配；不自动获得框架完整语义 |
| CSS/SCSS/Less | [Microsoft CSS Language Service](https://github.com/microsoft/vscode-css-languageservice) | 属性、诊断、文档内符号等，服务库需要适配 |
| JSON/JSONC | [Microsoft JSON Language Service](https://github.com/microsoft/vscode-json-languageservice) | Schema 驱动的配置提示、类型检查 |
| YAML | [Red Hat YAML Language Server](https://github.com/redhat-developer/yaml-language-server) | Schema 补全、诊断、悬停及格式化 |
| TOML | [Taplo](https://taplo.tamasfe.dev/cli/usage/language-server.html) | Rust 实现；需启用 LSP 的构建，不能假定默认/NPM 发行物含服务 |
| Markdown | [Marksman](https://github.com/artempyanykh/marksman) | 标题、链接、跨文档引用与重命名，依赖工作区边界 |
| SQL | [sqls](https://github.com/sqls-server/sqls) | Go 服务，表/字段补全通常需要数据库元数据；不默认连接用户数据库或执行 SQL |

配置 Schema、词库和模板属于数据；语言服务、运行时、插件和可执行分析器属于代码，分发策略分开处理。

## 4. 桌面与移动端边界

- macOS/Windows/Linux 先验证本机长生命周期服务：版本发现、可信路径、启动、stdio 消息、工作区、增量同步、取消、关闭与崩溃恢复。运行权限和分发渠道仍需逐端核对。
- Mac App Store 的沙盒、签名、外部工具链访问和帮助进程需单独实测，不能照搬 HyHub 公证直发包的环境。
- iOS/iPadOS 不以任意拉起外部 LSP/Node/JVM/SDK 为前提。先提供原生编辑与可内置语法解析；更深语义能力只在验证内置引擎、平台规则与资源成本后列入支持表。
- Android/鸿蒙同样需要自己的进程、后台、运行时和包分发验证；不能因“Rust 核心能编译”就宣称桌面服务全量可用。
- 核心浏览/编辑离线运行。远程 LSP 或云分析只是未来可选议题，当前不建立服务器、不上传源码、不作为移动端默认补齐方案。
- 桌面语言服务按需启用，优先复用明确选择的本机工具链；按语言/工作区管理和空闲回收，不在启动时加载所有服务。

分发边界见[可行性文档](FEASIBILITY_AND_DISTRIBUTION.md)。

## 5. 复制入库与项目上下文

已确认的默认文件模式仍为复制入库，保存只作用于库内副本。导入一个 `.rs`、`.dart` 或 `.ts` 文件，不代表同时取得项目根、清单、依赖、SDK、构建参数、Git 状态或修改原仓库的权限。

项目级能力实施前需明确以下两种模式之一或分别提供，但本次不擅自推翻复制入库约定：

| 待决模式 | 所有权与保存 | 必须解决的问题 |
| --- | --- | --- |
| 项目目录复制/快照入库 | 编辑完整库内目录；导出明确目标 | 相对路径、隐藏配置、链接、依赖、空间、更新与原件差异；单文件缺上下文时明确降级 |
| 原位置工作区 | 经用户明确选择授权，直接保存原项目 | 跨端授权持续性、失效恢复、文件监听、冲突、Git 边界；属于新增模式，待确认 |

不得把原路径写入来源元数据后直接作为可写工作区。即便完整导入，库外依赖和工具链仍可能缺失，不承诺完整语义。普通文件复制不自动包含 `.git`，Git 导入范围另定。

## 6. 交互和数据一致性

- 代码智能开关与索引状态清晰：未启用、缺工具链、准备/索引中、可用、部分可用、失败；基础输入与保存始终可用。
- 补全列表包含可理解的类型/摘要，键盘和触控可选择；中文组合输入期间不抢输入或错误提交候选。自动导入和多处编辑必须经过统一编辑事务。
- 跳转定义/实现进入标签并记录文件、光标、选择和滚动回退位置；查找引用先展示列表，再打开选定结果；预览与工作台宿主复用同一会话。
- 请求绑定文档版本，旧响应不覆盖新输入；LSP 位置编码（UTF-8/UTF-16 等）、行尾、emoji 和中文位置转换必须测试。
- 重命名/格式化/修复提供适用范围与差异预览；先实现单文档事务，多文件编辑在版本检查、失败恢复与脏缓冲处理明确后开放，不逐文件盲目覆盖。
- 目录扫描、构建信息读取、宏/构建脚本或插件可能触发工具执行。项目信任和调用范围单独设计，不把“查看文件”当成自动执行项目命令的授权。

## 7. 建议顺序与验收

先做原生编辑与安全保存，再做高亮/结构，接着在 macOS 单一服务上验证 LSP 生命周期及交互，再扩展 Rust、Swift、C/C++、Go、Dart、JS/TS、Vue 等常用语言。该名单是候选顺序，不是已承诺的首版语言集合。

验收覆盖：带依赖的真实小项目、未保存缓冲补全、定义及引用准确性、导航返回、中文/emoji 位置、取消与过期结果、服务崩溃、缺 SDK/离线降级、索引期间 UI 响应、编辑事务回滚。每种语言、服务版本和平台单独记录；HyHub 没有 LSP 验证可直接继承。
