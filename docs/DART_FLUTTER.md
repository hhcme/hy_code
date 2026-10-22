# Dart / Flutter 开发工具

更新：2026-10-22，build 31。已接通 SDK Analysis Server、Pub、紧凑悬浮，以及 Flutter 运行/调试、测试/构建和基础 Inspector 的首批入口；完整能力均纳入[九类清单](FLUTTER_PLAN.md)，尚未全部实现。沿用 Rust 正式文本与原生编辑，不恢复历史编辑器实现。相关决策见 [ADR 0005](adr/0005-dart-tooling.md)与 [ADR 0006](adr/0006-flutter-runtime.md)。

## 入口与当前范围

打开 Dart 文件后按需启动分析器。先在“设置 → Dart / Flutter SDK”选择已安装的 Flutter 或 Dart SDK 根目录；留空时只查 PATH 和常见安装目录，不自动安装、更新或执行项目内的 SDK。找不到 SDK 时仍可基础编辑和着色，分析面板显示原因；设置变更后可重启分析器。

| 能力 | 当前行为 |
| --- | --- |
| 语法、类型与 lint 诊断 | 使用 SDK 分析器和项目配置；未保存增量也参与分析。原生临时下划线、问题列表及状态栏数量；点击问题定位 |
| 悬浮 | 新符号停留约 140 ms 后请求，⌘悬浮立即请求，命中缓存直接展示；紧凑的着色签名、声明来源/包路径和说明，安全的行内 Markdown，无箭头或默认固定高度空白。右下角省略菜单提供定义/引用及展开长说明入口 |
| 定义与引用 | 确认有定义的符号悬浮时显示下划线和手形光标，中键、⌘B 或 ⌘点击跳定义，⇧⌘B 查引用；多个结果进入问题面板。原生右键菜单提供相同入口 |
| SDK / 包源码 | `file:` 定义结果可打开；工作区之外的源码标签只读，不改变当前活动包或写 SDK/cache |
| 补全 | Ctrl-Space 显式请求，最多 100 项原生候选；选择后经修订检查和原生可撤销编辑应用。不提供输入即弹出的补全、snippet 或自动导入 |
| 格式化 | ⌥⌘L；仅修改当前打开文档，范围/修订/Unicode/编辑上限全部校验后以一次原生撤销操作应用；失败保留原文 |
| 文件结构 | 结构面板显式刷新当前 Dart 文件，显示层级符号并定位；最多 2,000 行、16 层，切换文件不复用错误范围 |
| 包与 SDK 信息 | 分析面板读取最近父级 pubspec、package_config 与 Pub lock，展示包根目录、版本、直接/开发/间接来源；语言版本与包版本分开 |
| Pub 操作 | 显式获取、检查过期、升级、添加/移除依赖，可添加为 dev dependency。Flutter 项目使用所选 Flutter SDK；纯 Dart 包使用 Dart SDK。可查看输出并停止 |

这些入口分别实现，不代表与 IDEA 全功能对等。完整调用/继承层级、跨文件重构、重命名、quick fix、自动导入、交互补全及 pub.dev 搜索后续实现。当前导航历史保留文件级返回，尚无同文件精确位置历史。Flutter 运行链路首批范围如下；完整 DevTools、测试调试/覆盖率显示、attach、多 SDK/命名配置、Git 和终端仍待接入。

## Flutter 运行链路（首批）

| 能力 | 当前行为 |
| --- | --- |
| 设备与配置 | 顶部刷新/选择 SDK 返回的设备；配置菜单打开独立编辑弹层，确定后保存入口、设备、debug/profile/release、flavor、defines、附加参数和保存热重载开关；取消不写回。切换包立即禁用旧元数据，无自动模拟器启动 |
| 运行/停止 | 点击运行或调试，先保存所有打开文档，再用 SDK DAP 启动当前配置；停止请求 terminateDebuggee 并回收自有任务组。打开项目不启动运行服务 |
| 调试 | Dart 行号栏点击普通断点，调试页可开关、编辑条件/日志；初始异常使用 SDK 默认过滤。支持暂停/继续/单步、首个停止线程调用栈、作用域/变量及显式表达式求值（可执行代码） |
| 热更新 | 手动 hotReload/hotRestart；保存后热重载默认关闭、可选启用，运行中连续保存合并，控制任务忙碌期间保留待重载。仅 debug 模式提供热更新 |
| 构建/测试/Doctor | 顶部配置菜单提供 build 与 Doctor；测试结果页显式运行全部或指定路径，显示 machine reporter 的结果；coverage 开关只生成 SDK 覆盖率文件，尚无行标记。build 使用所配置入口/模式/flavor/defines，run/build/test 均禁用隐式 Pub |
| Inspector | 调试会话注册扩展后显式刷新 Widget summary 树，点击节点选择并导航创建位置；尚无完整属性/RenderObject/布局/DevTools 页面 |

调试面板默认仍隐藏，显式运行或工具按钮才展开。Flutter 菜单提供 Ctrl-R 运行、Ctrl-D 调试、Ctrl-. 停止、⌘\\ 热重载、⇧⌘\\ 热重启，另有继续/单步入口。SDK 负责项目构建、设备部署和工具缓存；HyCode 不将这些显式命令当成无副作用读取。本轮测试没有点击这些产品入口。

build 27 按用户提供的 WebStorm 截图重新组织运行工具界面：窗口顶部按设备、入口配置、运行/调试、热更新和停止排列；较窄时热更新保留在配置菜单。底部使用会话胶囊、紧凑图标工具条和“线程和变量 / 控制台 / Flutter Inspector / 测试结果”，不再将配置表单塞进调试内容。配置与断点各有独立弹层；构建目标、Doctor 和测试保留明确菜单入口。只有一份工作区配置，不伪造命名配置列表。

暂停事件展开调试面板并选择线程/变量，显式运行与构建选择控制台，测试选择测试结果；切换标签、打开配置或断点弹层不启动工具。调用栈与变量在内容宽至少 480 pt、高至少 120 pt 时原生左右分栏；窄面板高至少 220 pt 时上下分栏，其余尺寸使用一个滚动区，避免底行缩小时把变量/求值裁掉。分隔拖动不写工作台观察状态。控制台独立观察输出，采用可选文本与自动折行；统一纯色、细分隔、按钮反馈和透明滚动槽，不恢复渐变。

运行配置使用草稿，确定时验证配置、工作区身份、原值和任务空闲状态；多行参数在输入期间保留换行，确定才转换为参数数组。断点弹层明确标注即时生效，继续沿用原断点所有者。这些是代码实现与静态复核，未操作 WebStorm/HyCode，不能据此称为像素或帧率验收。

断点有单独的磁盘基线和未保存投影；修改源码只移动投影，不立即发往磁盘调试源，保存成功后同步，丢弃恢复最近成功保存基线。SDK 初始响应可为未确认，后续 breakpoint 事件确认/移动后才显示实心；空心还可表示待保存或未解析。项目关闭/切换等待运行与工具任务回收；重启 Dart 分析器不会附带停止 Flutter 会话。请求/错误回写与 Inspector 树按会话/暂停/选择/isolate 代次隔离。

## 项目与依赖

当前活动包取打开文件到工作区根之间最近的 `pubspec.yaml`，关闭活动标签自动回退时也更新；异步识别期间清空旧包并禁用命令，避免操作上一包。外部只读依赖标签沿用原活动包。只支持普通包的最近父级发现，完整 Pub workspace、多 SDK/FVM 版本路由和无 pubspec 的 loose 文件项目模型未完成。

包位置取 `.dart_tool/package_config.json`；版本、依赖角色及来源读取 `pubspec.lock` 中 Pub 生成的简单标量，不实现通用 YAML，不替代 Pub 求解。没有 package_config 或不支持的 lock 写法时显示未解析/未知，保留清单内容。复杂版本约束、path/git/SDK/override 可直接编辑清单，再显式获取依赖；添加表单只收包名或单个无空格版本约束。

Pub 可按 SDK 的正常行为访问包服务器、缓存和更新工作区清单/lock/config；只有按钮操作触发，不因打开目录或开始分析而运行 Pub。执行前等待已打开清单的旧保存结束、保存脏内容，并在任务期间将清单缓冲设为只读；保存冲突会阻止命令。结束后重载干净清单；关闭流程中延迟重载并核对文档身份，避免跨项目回写。其他源码缓冲不由 Pub 修改。SDK 本身可能维护缓存/锁或下载组件，HyCode 不将这些行为称为无副作用读取。[Pub 官方行为](https://dart.dev/tools/pub/cmd/pub-get)和[依赖来源](https://dart.dev/tools/pub/dependencies)。

## 所有权、协议与资源

- 每工作区一个 DartWorkspaceController，持有一个 DartLanguageServer、按序 didOpen/didChange/didClose 和有界请求。Rust 仍独占正式文本/修订，分析器的 overlay 只用于语言查询，不直接写正式缓冲。
- LanguageServerConnection actor 负责 Content-Length/JSON-RPC、超时、取消和服务请求；同步读在 utility worker，写在独立 writer actor，阻塞 SDK 不会占住协议 actor。格式解码和诊断解码也不在 UI 线程。诊断单 worker 按 URI 合并，避免为每条事件新建并行工作队列。
- 所有请求响应核对工作区代次、文档身份和修订；hover 另有完整符号范围/语义代次票据。格式化/补全只应用同文件编辑，拒绝重叠或越界范围；不接受服务端 `workspace/applyEdit`。
- 悬浮只有一个工作任务槽，hover 与定义请求并行，先返回的结果先显示；符号内逐字符移动不重置停留或重发。每个文档最多缓存 16 个符号（含空结果），定义最多缓存 32 项，截断结果不冒充完整导航缓存。编辑、打开/关闭文档、服务重启和 Pub 收尾推进语义代次；Pub 重载清单后清空所有悬浮缓存。项目内磁盘变动由[后台分析监听](PROJECT_ANALYSIS.md)推进语义代次；项目外 SDK/包缓存的外部改动未纳入该监听。
- 命中测试要求鼠标位于实际字形/标识符，不将行尾空白映射到最近文字。移出符号清除临时链接下划线，并给进入卡片留下 140 ms 宽限与空白桥接区；滚动、编辑、失焦、窗口缩放、关闭和外观变更清理卡片。下划线清理后恢复重叠诊断，不改原文字色或撤销历史。卡片按锚点所在屏幕限位，不请求键盘焦点；只解析有界行内 Markdown，移除链接动作，不执行 HTML。
- build 31 将 Dart 的 import/export/part URI 作为完整悬浮目标，保留 `dart:`、`package:` 和相对路径中的分隔符；支持通常的多行及条件导入、同一行前置注释与多指令；跳过注释中的假指令及普通多行字符串。沿用增量协议行索引，只向前查看至多 16 行，首次前向扫描窗口至多 8,192 UTF-16 单位；截断窗口的前置词法状态未知且未命中时，以额外共用 8,192 单位预算重试行局部候选，不复制或扫描全文；这不是完整 AST 词法器，超出边界保留普通符号查询，不保证整条 URI 命中。普通字符串不按整条包引用处理。该词法命中不解析磁盘或判断库是否存在，真正的 library/Declared 信息与定义来自 SDK；只有确认本地定义时才显示整条 URI 的临时链接下划线/手形。鼠标在 `/`、`.`、`:` 等路径字符之间移动复用同一停留和缓存；中键、⌘点击与 ⌘B 共用定义入口，失效 URI 保留分析器诊断，不伪造跳转。
- LSP 位置使用 UTF-16、CR/LF 行规则，与 UI 可显示的 Unicode 分行索引分开；增量维护，测试覆盖 emoji、中文、CRLF 和 Unicode 分隔符；原生编辑若拆开 CRLF 边界，会扩展协议范围并保留未改单位，不发送协议无法表示的位置。组合输入期间暂停新的诊断下划线和自动保存，不用诊断改变文字颜色或撤销历史。
- **Dart 3.11.5 推送诊断不带文档版本**。有版本时严格匹配；无版本时清掉编辑前显示、等本地修改发出再展示，并按 URI 合并，但不能证明每条诊断属于当前修订，瞬时旧诊断仍可能出现。它只用于显示，不用于自动写入或快速修复。不能把后台用例称为无版本诊断的严格修订证明。[上游实现](https://github.com/dart-lang/sdk/blob/3.11.5/pkg/analysis_server/lib/src/lsp/lsp_analysis_server.dart)。
- 语义入口限初次载入不超过 1 MiB 的解码后 UTF-8 Dart 文件；基础编辑仍保留原 8 MiB 上限。协议帧至多 8 MiB、128 个在途请求、事件缓冲 512；单 URI 最多 1,000 条诊断、500 URI/全局 5,000 条。Pub stdout/stderr 各保留最多 1 MiB，UI 最多约 256 KiB 并按 80 ms 合并刷新；分块 UTF-8 解码保留中文/emoji。
- SDK 与 Pub 使用 `/usr/bin/nice -n 10`。posix_spawn 在 exec 前原子建立独立进程组、重置信号和 FD 继承。停止只针对本任务组；Pub SIGINT 后 3 秒 TERM、再 2 秒 KILL，分析器 TERM 后最多 2 秒 KILL。保留已退出 leader 可等待状态直到清组，防延迟信号命中复用 PID；关闭项目/窗口/退出先等待后台回收。主动脱离进程组的第三方程序不在这一保证内。
- SDK/cache 文件不进入应用包。分析器缓存位于 HyCode 的 Caches 子目录；暂无磁盘缓存配额/清理策略和索引 CPU/内存硬限制。nice 只是降低调度优先级，不能代表已达到交互帧率预算。SDK 分析插件遵循该工具链的行为，尚无独立插件沙箱。

## 来源与验证边界

实际协议验证使用本机外部 SDK 的 Dart **3.11.5**；Flutter 元数据为 **3.41.10-ohos-0.0.2-beta**，仅记录该外部安装，不代表验证了此 fork 全部能力或其他官方版本。Dart/Flutter SDK 均未复制、链接或随包分发；上游 BSD-3-Clause 与来源见[依赖台账](DEPENDENCIES.md)。本功能无新增第三方 Swift 包或 Rust crate。

只运行可确认静默的后台检查。`HyCodeDartProbe` 接受显式 SDK 根目录，创建临时 Dart 文件、自有缓存，启动纯 stdio Analysis Server：验证错误、未保存修复、hover、定义（含 SDK 源码）、引用、补全、层级符号、格式化及磁盘未变；不跑 Pub、不下载包、不读取用户项目，不启动应用/设备。build 25 另断言真实 SDK 构造函数的围栏、声明与说明可以分节解析，同一符号内两次 hover 一致且服务范围匹配完整标识符。样本在分析器就绪后单次/重复 hover 约 1.45 / 0.36 ms，仅是该临时文件协议往返，不代表真实项目索引、窗口延迟或帧率。

```sh
bash scripts/build_core.sh
nice -n 10 swift run --jobs 2 HyCodeDartProbe /path/to/flutter-or-dart-sdk
nice -n 10 bash scripts/check_native.sh
nice -n 10 bash scripts/build_macos.sh release
```

协议/位置/编辑批次、SDK/包元数据、分块输出和阻塞/后代进程取消有无 GUI 测试；build 25 新增 11 项纯模型回归，覆盖有界解析、Unicode 整词命中、快速移动/取消、负结果/LRU、语义失效、修饰键加速、截断导航结果、跨屏定位及进入卡片的桥接区，另通过 Swift ASan。SwiftUI/AppKit 只编译，不作为测试宿主。真实悬浮/展开说明、候选菜单/键盘、中键/⌘点击、跨标签导航、下划线/IME/撤销、清单保护/冲突与关闭的端到端行为、真实 Flutter 项目及 Pub 网络流程均**未验证**。没有启动或操作任何 GUI、剪贴板、模拟器或用户应用，没有签名发布。证据与开发包信息见[工作台记录](WORKBENCH.md)。

build 26 新增 10 项运行配置/设备/状态/断点基线与解析事件/test reporter/Inspector 模型及 stdio fixture 用例；全仓 122 Swift / 15 Rust 后台测试通过。新增探针 `HyCodeDebugProbe /path/to/sdk` 仅尝试生成的 Dart 控制台调试，当前本机 fork 拒绝 VM Service 启动参数，**未通过真实断点/调用栈验证**；其失败与 fixture 通过分别记录。语言 LSP 探针继续通过。真实 Flutter run/debug/热更新、设备、构建、测试命令、Widget 树、快捷键与性能均未执行，不据编译或协议替身称为通过。

build 27 全仓 125 Swift / 15 Rust 静默检查通过，新增 3 项配置草稿隔离/取消/冲突与校验测试；原生 UI 仅编译和静态复核，未重跑真实 SDK 或 sanitizer。完整记录见[本轮证据](evidence/2026-10-22-build27-webstorm-tools.json)。

build 31 在自建临时 package_config/库文件中验证 Dart 3.11.5 的 `dart:async`、`package:` 与相对 import：本地完整 URI 命中、library/Declared 分节、路径标点位置 hover 一致、定义返回；不存在的 URI 没有定义，且诊断范围覆盖导入路径。没有执行 Pub、下载依赖或访问用户项目；协议通过不代表窗口悬浮、下划线或鼠标跳转已验收。完整记录见[本轮证据](evidence/2026-10-22-build31-import-menu.json)。

## 源码入口

| 路径 | 职责 |
| --- | --- |
| [Language/](../packages/HyCodeWorkspace/Sources/Language/) | JSON-RPC、增量 framing、位置与文本编辑、SDK/包读取、进程组/任务 |
| [DartWorkspaceController.swift](../app/macos/Sources/Language/DartWorkspaceController.swift) | 工作区服务、版本/会话隔离、诊断队列与 Pub 生命周期 |
| [EditorLanguageFeatures.swift](../app/macos/Sources/Language/EditorLanguageFeatures.swift) | 编辑增量、临时下划线、悬浮、导航、补全/格式化事务 |
| [DartHoverController.swift](../app/macos/Sources/Language/DartHoverController.swift) / [DartHoverCard.swift](../app/macos/Sources/Language/DartHoverCard.swift) | 单工作任务悬浮、确认链接、临时下划线与原生无焦点卡片/菜单 |
| [DartHoverContent.swift](../packages/HyCodeWorkspace/Sources/Language/DartHoverContent.swift) / [DartHoverState.swift](../packages/HyCodeWorkspace/Sources/Language/DartHoverState.swift) / [DartHoverPlacement.swift](../packages/HyCodeWorkspace/Sources/Language/DartHoverPlacement.swift) | 有界内容/整词解析、语义缓存与调度、屏幕/桥接几何；对应 [DartHoverTests](../packages/HyCodeWorkspace/Tests/DartHoverTests.swift) |
| [DartDirectiveTarget.swift](../packages/HyCodeWorkspace/Sources/Language/DartDirectiveTarget.swift) / [DartDirectiveTests.swift](../packages/HyCodeWorkspace/Tests/DartDirectiveTests.swift) / [ImportProbe.swift](../tools/DartProbe/ImportProbe.swift) | 有界 Dart 指令 URI 命中、纯模型与真实 SDK 的包/相对/SDK 引用验证 |
| [DartToolPanels.swift](../app/macos/Sources/Language/DartToolPanels.swift) | 依赖、问题、结构与输出面板 |
| [FlutterWorkspaceController.swift](../app/macos/Sources/Language/FlutterWorkspaceController.swift) / [FlutterDebugPanel.swift](../app/macos/Sources/Language/FlutterDebugPanel.swift) | 独立运行/工具任务、会话与调试/测试/Inspector 内容 |
| [FlutterRunToolbar.swift](../app/macos/Sources/Language/FlutterRunToolbar.swift) / [FlutterRunConfigurationEditor.swift](../app/macos/Sources/Language/FlutterRunConfigurationEditor.swift) | 设备、运行配置与独立配置/断点弹层 |
| [FlutterDebuggerContent.swift](../app/macos/Sources/Language/FlutterDebuggerContent.swift) / [FlutterToolPresentation.swift](../packages/HyCodeWorkspace/Sources/Language/FlutterToolPresentation.swift) | 自适应调用栈/变量分区、配置草稿与冲突校验 |
| [FlutterDebugSession.swift](../packages/HyCodeWorkspace/Sources/Language/FlutterDebugSession.swift) / [FlutterBreakpointState.swift](../packages/HyCodeWorkspace/Sources/Language/FlutterBreakpointState.swift) | DAP 握手/生命周期、断点确认与磁盘/未保存投影 |
| [FlutterRuntimeTests.swift](../packages/HyCodeWorkspace/Tests/FlutterRuntimeTests.swift) / [dap_adapter.py](../tools/fixtures/dap_adapter.py) / [DebugProbe](../tools/DebugProbe/main.swift) | 纯模型、无 SDK 的 stdio fixture 与显式 SDK 生成控制台探针 |
| [EditorWorkspace.swift](../app/macos/Sources/Editor/EditorWorkspace.swift) | 文档协调、清单工具租约及退出保护 |
| [DartProbe](../tools/DartProbe/main.swift) | 临时样本的官方分析器协议验证 |

协议依据：[Dart 3.11.5 LSP 支持](https://github.com/dart-lang/sdk/blob/3.11.5/pkg/analysis_server/tool/lsp_spec/README.md)、[LSP 3.17](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)。

## build 29 项目后台诊断

打开含 Dart/pubspec 的项目时即启动分析器，`onlyAnalyzeProjectsWithOpenFiles: false`，由 SDK 处理根目录及关联增量，不要求先打开文件。Dart 的项目诊断与 Web 共同进入左下角计数和按文件分组的问题面板，支持筛选、行列定位，并显示 SDK 分析状态。真实临时样本已验证未发送 didOpen 前收到未打开文件的错误；未保存依赖变更触发未打开导入方诊断，关闭后回到磁盘内容，原文件未被分析器写入。范围与资源限制见[项目后台诊断](PROJECT_ANALYSIS.md)。`$/analyzerStatus` 仅表示 SDK 当前分析活动，不证明所有插件结果已最终到齐。
