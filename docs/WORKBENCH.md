# 当前文件浏览工作台

build 48 增加[本地交互终端](TERMINAL.md)：显式打开才启动 Shell，原生多标签/分屏、搜索、自有设置和项目树入口；隐藏保活，关闭/切项目/退出确认并等待回收。以下较早批次的“终端空入口”为当时状态，当前范围与窗口/性能缺口见专题。

build 42 已增加默认展开的右侧 [Codex 多会话面板](CODEX_AGENT.md)：独立工具图标、项目自定义服务、流式输出、停止与文件修改保护。后台协议、真实服务、Keychain 和窗口验收分别记录，见专题。

build 28 已增加 [Web 工作流](WEB_TOOLS.md)：代码菜单提供多语言诊断/导航、参数信息、显式补全/自动导入、格式化及修改预览；分析面板可切换 Dart/Flutter 与 Web，并显示最近 package 的声明依赖与 scripts。Node 路径在设置中配置，Vue 配置插件需显式工作区信任。包任务均为显式操作，有停止入口，运行前保护清单；真实包脚本、窗口及性能仍未验证。

新增原生入口为 `app/macos/Sources/Language/EditorLanguageController.swift`、`EditorLanguageFeatures.swift`、`WebWorkspaceController.swift`、`EditorWebActions.swift`、`LanguageEditPreview.swift` 和 `WebToolPanels.swift`；无 GUI 模型/协议在 `packages/HyCodeWorkspace/Sources/Language/`，固定服务在 `tools/web-language-services/`，后台 fixture 在 `tools/WebProbe/`。

更新：2026-10-28。当前按用户要求实现 IDEA / WebStorm 风格工作台、文件浏览和基础文本编辑，新增行号和基础多语言着色，Dart SDK 语义及 Pub 首批工具已接入，见 [Dart/Flutter 工具](DART_FLUTTER.md)。已有真实工程、Rust 文本/目录内核、构建与后台测试；真实窗口效果、交互和性能尚未验收。

## 当前范围

build 40 增加[跨格式大文件分段编辑](LARGE_FILES.md)，包含字节定位、整文件字面查找、跨页撤销和完整保存；后台 GB 样本与窗口缺口分别记录。本地开发包已更新至 0.1.0 / build 40，未启动、安装或发布。

build 36 增加[JSON/JSONC、YAML/YML 配置工具](CONFIGURATION_TOOLS.md)：后台语法/Schema 问题、字段补全/说明、结构、格式化，YAML 锚点定义与重命名预览。常用 package、TS/JS 配置、GitHub Actions 与 pubspec 规则离线随包；本地规则安全读取与保存后依赖刷新，尚未进行真实窗口验收。全量静默检查 202 Swift（38 组）/ 19 Rust / 4 Node 通过，配置/监听 7 项 Swift ASan 与真实服务回归通过。Release 本地开发包 0.1.0 / build 36、arm64、约 159.3 MiB；未启动、安装或发布。可执行 SHA-256：`763092bc82d8fe9236e6942440ccedf8cecdecfa9c9e79828144d6d201c1a98f`。记录见[后台证据](evidence/2026-10-23-build36-configuration-tools.json)。当前本批未提交推送。

build 35 增加[简单视频只读预览](VIDEO_PREVIEW.md)：本地 MP4/MOV/M4V 单击进入标签，默认暂停、播放/暂停、进度/音量、自动适应画面；切标签卸载播放器并保留进度。源视频按固定描述符分段读取，元数据异步加载；无文本缓冲、保存或新增第三方解码器。真实窗口/声音/播放仍未验收。

完整静默检查为 196 项 Swift（37 组）与 19 项 Rust，新增 10 项视频回归另通过 Swift ASan；Rust 静态库和 Apple 框架未插桩。Release 本地开发包 0.1.0 / build 35、arm64、约 144.8 MiB；未启动、安装或发布。可执行文件 SHA-256：`532158c714fe60302d949cd38757228440c33b5ba0610aa342334022dff7ff60`。源码、日志、独立审查与验证边界见[后台证据](evidence/2026-10-23-build35-video-preview.json)。该批随后已提交推送至 `456bc18`。

build 34 增加[图片只读预览](IMAGE_PREVIEW.md)：项目树单击图片进入独立标签，提供适应窗口、100%、缩放、拖动、背景与透明度查看；ImageIO 解码位图，Rust resvg 处理受限 SVG，多帧暂显示首帧。加载/解码在后台串行执行，非活动标签释放像素，固定尺寸原生画布只绘制已解码投影。图片不建立文本/撤销/自动保存或语言修改。实现决策见 [ADR 0008](adr/0008-image-preview.md)。

build 34 完整静默检查为 186 项 Swift（34 组）、19 项 Rust；其中图片新增 13 项 Swift 和 4 项 Rust。13 项图片 Swift 测试另通过 ASan，Rust 静态库未插桩。Release 本地开发包为 0.1.0 / build 34、arm64、约 144.5 MiB，未启动、安装或发布；可执行文件 SHA-256：`3ffe52cc1b558b48f8726df5e9b1baccb3de2a59b853e17c837dd3dbf624a83b`。格式样本、许可、源码与日志哈希见[后台证据](evidence/2026-10-23-build34-image-preview.json)。该后台记录形成时 build 32–34 尚未提交推送；随后已提交至 `325be52`。

build 33 已扩展到全部已有应用界面的共用样式：项目/菜单弹层、分析/依赖、调试/问题、配置/设置、重命名与保存确认。具体覆盖及未验证项见[整体清单](VISUAL_ALIGNMENT.md)，后台结果为 173 Swift / 15 Rust，新增 4 项弹层几何测试。32 项相关几何/交互用例与最终格式/Release 构建通过；本地开发包 0.1.0 / build 33、arm64、约 140.4 MiB，未启动、安装或发布。可执行文件 SHA-256：`dc5d3afaf4d2bfe9950140404cbbd70f21c4f0e1e9703c83a59fc054f50662e0`。源码、日志、审查修复及限制见[后台记录](evidence/2026-10-23-build33-full-workbench-style.json)。本批没有提交或推送。

- 打开用户选择的本地目录，不复制入库、不修改文件。
- 紧凑原生头部、双侧工具条、中央文件标签与内容区、面包屑和状态栏。
- 中央内容之外有四个独立工具角落，每角可放多个工具、显示一个活动面板。默认只展开左上文件列表；下方单块展开时占满底行，两块展开时可调整左右比例。
- 共 12 个工具入口：文件列表、搜索、结构、Git、终端、调试、分析、问题、文件信息、已打开标签、项目概览、Codex。支持长按跨角移动、组内排序及右键菜单替代。
- 目录展开时读取一层，只在树内选择/展开；项目根和目录不生成中央列表或目录标签。文件单击临时浏览、双击固定标签；标签可切换、固定、关闭。
- 项目切换面板按打开/最近项目分组，显示徽标、名称和路径；最近历史由 HyCode 自己记录并持久化，最多 30 条。
- 启动默认恢复上次打开的项目，显式关闭项目后保留欢迎页；旧版记录迁移历史首项，恢复与用户项目操作使用同一意图保护。
- 未打开项目时，中央欢迎页显示最近项目，整行可点击继续打开；与头部项目切换共用记录和打开入口。
- 应用所属纵向滚动区及项目树横向保留固定 8 pt 槽，只绘制 4 pt 滑块，不绘制轨道背景；标签/面包屑的横向指示条持续隐藏。
- 前进、后退、上级目录、刷新、隐藏文件开关、取消读取与失败重试。
- 单击文件打开原生文本编辑，Rust 持有正式文本/修订；默认停止输入 800 ms 自动保存，可在设置关闭，并提供 ⌘S 和未保存关闭保护，详见[编辑与保存](EDITING.md)。行号与 Tree-sitter 着色见[高亮说明](SYNTAX.md)；Dart/Flutter 语义、依赖、问题与结构现已接入；Flutter 运行/调试、热更新、测试/构建及基础 Widget 树入口已接入，真实 Flutter/设备未验证。终端首批范围见本页顶部与专题，Git 仍待后续集成；项目背景诊断与分析监听见[项目分析](PROJECT_ANALYSIS.md)。文件信息、已打开标签和项目概览继续使用真实状态；其他尚未实现的工具保持空入口，不伪造服务结果。

## 交互与快捷键

| 入口 | 行为 |
| --- | --- |
| 打开项目 / ⌘O | 用户主动打开系统目录选择面板；取消不切换项目 |
| 文件列表 / ⌘1 | 显隐文件列表，初始位置左上 |
| 文件信息 / ⌘2 | 显隐信息面板，初始右上，默认隐藏 |
| 已打开标签 / ⌘3 | 显隐标签列表，初始右下，默认隐藏 |
| 项目概览 / ⌘4 | 显隐项目概览，初始右下，默认隐藏 |
| 其他工具 | 点击展开该角工具，再次点击活动工具收起；同角切换工具不影响其他角 |
| 长按工具按钮约 280 ms 后拖动 | 跨角移动或按插入线调整组内顺序；松开提交，取消不修改布局 |
| 工具按钮右键菜单 | 移到任一角落、向前或向后排列；无需长按作为替代入口 |
| 工具区域标题减号 | 关闭对应区域，与菜单和工具图标使用同一显隐状态 |
| 分隔带 | 调整两个上方侧栏宽度、底行高度、底行左右比例；支持键盘方向与无障碍增减 |
| 项目标题右侧收起按钮 | 收起子目录，保留项目根层，不清除标签 |
| 项目树展开箭头 | 按需读取子目录，不递归扫描整个项目 |
| 项目树单击 / 双击 | 目录只选择/展开；文件临时编辑 / 固定标签，首次修改立即固定 |
| ⌘↓ | 打开选中项；目录不创建标签 |
| 头部项目按钮 | 打开项目切换面板；当前打开项目和其他最近项目分组显示，点击才切换 |
| 标签双击 / 右键 | 固定临时标签，或关闭标签 |
| ⌘[ / ⌘] | 浏览历史后退 / 前进 |
| ⌘↑ / 面包屑 | 返回工作区内相应父目录；根目录不再上行 |
| ⌘R | 重新读取工作区目录，不执行项目脚本 |
| ⌘S / ⌥⌘S | 保存当前文件 / 保存全部文件 |
| 设置 / 编辑设置 | 开关自动保存、行号/高亮，设置 SDK 路径并重启分析器；偏好持久化 |
| Dart：⌘B / ⌘点击 / 中键 / ⇧⌘B | 前三者跳定义，⇧⌘B 查找引用；确认定义的悬浮符号显示下划线和手形，多个结果进入问题面板 |
| Dart：Ctrl-Space / ⌥⌘L | 显式补全 / 当前文档格式化 |
| 代码 → Dart / Flutter 依赖管理 | 分析面板中的 Pub 与包版本/来源 |
| Flutter 菜单 / 顶部运行工具条 | 显式刷新/选择设备、运行/调试、热重载/热重启与停止；底部会话、栈帧/变量、控制台、测试结果与基础 Widget 树；配置/断点使用独立弹层 |
| ⇧⌘. | 切换隐藏文件 |
| 读取期间停止按钮 | 取消后台读取；旧请求与旧会话不覆盖新状态 |

默认左上文件列表和右上 Codex 展开，其余工具面板隐藏，四角的入口按钮仍可见。尺寸、停靠顺序、显隐、目录展开与标签状态只保存在当前进程；折叠不主动销毁原生树，文件列表跨角移动复用同一个宿主。外观选择、自动保存偏好、启动项目与最多 30 条最近项目持久化，默认深色，可切换浅色或跟随系统。最近项保存标准化路径与可选访问书签；书签生成/解析离开主线程，启动默认恢复上次项目，最近路径不视为永久访问许可。当前每个工作台只有一个打开项目，不伪造多项目会话。

## 样式与分区（build 33）

用户进一步明确默认只有左上文件列表展开，工具按钮可以移动及排序，并指出分隔蓝线越过圆角、移出残留和偶发掉帧。本版保留纯色外框与四区布局，增加工具停靠并改进高亮和刷新路径。build 32 按用户已提供的 WebStorm Islands 截图作静态像素采样，并统一工作台尺寸；采样、推导与实际窗口验收分别记录，见[视觉对齐](VISUAL_ALIGNMENT.md)。

| 区域 | 当前实现 |
| --- | --- |
| 窗口头部 | 43 pt 纯色深灰；项目、前进后退、刷新、打开和外观菜单；系统按钮保留原生大小/动作，沿头部居中对齐，全屏交给系统 |
| 两侧工具条 | 各 40 pt，壳体左右各留 1 pt；30 pt 按钮按 40 pt 步进，首末按钮距工具条端部 3 pt；四角分组和拖放排序保留 |
| 工具区域 | 10 pt 圆角、5 pt 分隔带；顶部/底部标题与中央标签条统一 40 pt，标题字号 13 pt |
| 中央标签 | 仅文件创建 28 pt 活动胶囊标签；无文件时不显示标签条；边框和面板内部细线按显示缩放采用一个物理像素 |
| 项目切换 | 520 pt 宽面板；顶部新建/打开/克隆操作区；打开/最近项目分组、徽标、名称与路径双行；新建/克隆置灰，仅打开/关闭/切换可用 |
| 项目树行背景 | 悬停与选中使用相同可见整行、4 pt 圆角和上下 1 pt 间距；左右可见背景各离面板 16 pt，层级只缩进内容 |
| 欢迎页 | 无项目时显示打开操作与最近项目；宽窗口并排、窄窗口上下排列，整体可纵向滚动 |
| 控件反馈 | 按钮、项目行、标签和菜单入口区分悬停/按下/选中状态；可用入口使用手形光标，禁用态不响应悬停 |
| 滚动条 | 应用内纵向及项目树横向固定保留 8 pt 槽、4 pt 滑块；透明轨道；树滚动区右侧再留 8 pt、顶部留 5 pt、底部留 8 pt，避开面板圆角 |
| 分隔带 | 默认与外框同色；悬停/拖动时显示一个物理像素的强调线，两端各缩进 10 pt；鼠标移出并结束拖动后隐藏，键盘焦点使用中性色 |
| 状态栏 | 36 pt，12 pt 字号，项目路径、目录条目数或当前文件编码/换行及保存状态；右侧自身内存/CPU 与闲置缓存清理，见[口径](PERFORMANCE_MONITOR.md) |
| 深色配色 | 外框 `#26282C`、内容 `#191A1C`、文字 `#D1D3D9`；无渐变背景 |

最小窗口仍为 860 × 540。双侧工具区域适应当前窗口并保留中央至少 360 × 220；底行同时显示两块时各至少 220 pt。窗口临时缩小或折叠不会覆盖用户尺寸偏好，放大后恢复；拖动以当前可见尺寸为基准，不混用适配前的另一侧宽度。小高度欢迎页可整体滚动，避免操作和最近项被截掉。

几何统一按 backing scale 取整，共用分隔坐标，避免相邻区域分别取整产生重叠。当前按 1×、1.5×、2× 检查模型边界；这不等于实机显示比例和视觉已验收。

## 动效与拖拽实现

AppKit 容器是尺寸与拖动的唯一所有者；每个工具首次展开时才创建独立 NSHostingView，切换或隐藏后保留，跨角重挂同一实例。四个角的裁剪容器和中央宿主稳定存在。停靠模型是工具分组、排序及活动选择的唯一所有者；同角重排不改变选择，跨角移动已展开工具会带走其面板，移动未展开按钮不打开或替换目标面板。

工具按钮按住约 280 ms 后移动至少 4 pt 才发起原生拖放，点击保持原有切换行为；拖放 hover 只更新本地插入标记，松开时一次提交模型。来源校验为同一工作台 session 的原生按钮对象，不接受外部拖入。仅使用专用 drag pasteboard，不访问 general 剪贴板。右键菜单提供移动和排序作为替代。对应代码路径本轮未在真实窗口执行。

分隔事件只记录待应用尺寸，由 macOS 14+ 的 NSView displayLink 跟随所在屏幕刷新，每帧应用最新一次；build 11 在回调中直接应用原生几何，释放鼠标时提交最后一次。不会在每个指针事件修改 SwiftUI `@State` 或工作区观察状态；不在拖动路径执行 I/O 或扫描。中央目录表格及其筛选已移除，不再重复维护和刷新另一份目录界面。

显隐使用 200 ms ease-in-out 的位置/裁剪插值，由同一个 displayLink 驱动，替换固定 60 Hz 循环定时器。仅显隐面板保留内容尺寸，持续可见邻居按实际尺寸布局；反向切换从当前几何继续。弱 target 避免持有容器，一次性 deadline 在窗口遮挡、刷新回调暂停时也结束动画。build 11 的分隔强调由工作台唯一 CALayer 显示，四个分隔条不再各自保存高亮；退出、结束、取消和失焦主动清除，不靠重绘覆盖旧蓝线。

隐藏区域禁用命中、控件和无障碍，释放区域内原生第一响应者。减少动态效果开启时取消动画；窗口改变直接重新适配。动画中的移动分隔暂不接受拖动。后台测试与源码复核不能证明长按跟踪、悬停清除、动画和拖动流畅度已经通过实机验收；尚未采集真实帧率、延迟或 CPU 数据。

## 拖动热点与预览（build 7）

用户在 build 6 报告拖动仍会偶发卡顿，拖出的符号变黑、无底色。源码中原预览直接创建系统模板符号，没有使用按钮图像；本轮改为按钮与拖拽共用 30 pt 的完整位图，包含不透明纯色底、6 pt 圆角、明确的前景色及透明外角，`isTemplate = false`。未选择工具采用悬停灰底，已选择工具保留蓝底白图标，不将符号放大到整个按钮大小。

图标 alpha 由系统符号提供，颜色由自己的合成器确定；生成 glyph 时明确传入 backing scale。每个按钮最多缓存三个状态及一个 glyph，外观/显示缩放改变时失效；长按准备阶段预取，进入拖放会话后不逐帧生成符号或位图。

另外移除了可从源码确认的重复工作：

- 插入角落、槽位和坐标不变时不提交新的 CALayer 属性，不再将整条工具栏标记为需要绘制；也不要求静止指针的周期拖放回调。
- 停靠状态相同不重排按钮；按钮与分隔的 tracking area 只创建一次，使用 `inVisibleRect` 自动跟随尺寸。
- 尺寸已经夹到边界时不再请求布局；分隔还处于同一 backing pixel 时不把相同几何再次传入宿主。动画结束强制提交最终内容尺寸，避免去重吞掉收尾。
- 隐藏分隔线和相同高亮状态不重复提交图层事务；已隐藏工具不随每次工作区更新重新赋根视图，重新展开时更新。

这些属于热路径改动，不是偶发卡顿的实机归因。纯 CoreGraphics 测试验证 1×/2×/3× 位图尺寸、不透明底、明确前景、透明圆角，以及 glyph 自带颜色不会使预览变黑；不创建窗口或系统符号宿主，不能替代真实拖动外观验收。

新增仅在采集开启时启用的 `Workbench` signpost 区间：`CanvasLayout`、`HostContentResize`、`ToolTileRaster`、`DockPlacement`；build 8 增加 `TreeBranchReload`。它们不记录项目路径、文件名或业务数据，不自动启动 Instruments、不写性能报告文件；区间只表示相应函数的 CPU 工作，不包含完整屏幕呈现或 GPU 帧时间。本轮没有启动应用或采集这些区间，没有实测 FPS 或尾部延迟。

## 目录读取与刷新（build 8）

用户报告展开目录等待“正在读取…”。源码复核确认旧路径共用单个后台工作器、每个读取状态变化全树重载，刷新后又可能保留原生展开状态而缺失重读请求。build 8 改为两个后台工作器、共享 FIFO 排队，按每个目录修订只重载变化的可见分支。刷新恢复可见展开路径时独立补读，不依赖 NSOutlineView 对已展开项再次触发委托。删除节点沿父子索引回收实际后代，避免对每个移除项重复过滤全表。请求继续保留会话、请求代次和访问寿命检查；取消错误不自动无限重试。

目录单击只改变树选择和信息面板；展开箭头或目录双击发起读取，打开项目显式读取根目录。目录不创建/替换/固定文件标签，已打开文件仍留在中央；没有文件时中央为空白内容区。文件单击进入原生编辑，编码、增量文本和安全保存由独立文档会话管理；详见[编辑与保存](EDITING.md)。

滚动适配只作用于应用自己的 NSScrollView，不改变系统全局偏好。树直接配置，SwiftUI 滚动内容内的轻量 marker 沿公开父视图链找到最近的所属滚动区；仅在接入、轴或 scroller 配置变化时重设。滚动条视觉、滚动行为和项目弹层仍未进行真实窗口验收。

后台临时样本读取结果与复现入口见[性能记录](PERFORMANCE.md#目录读取探针build-8)。这份小样本不代表用户项目、冷磁盘或树到屏幕的延迟，也不能从中证明截图中的所有等待都由上述问题导致。

## 项目树横向范围（build 9）

用户截图显示树名称在较窄的文本区域中被中间省略。此前没有启用横向滚动，名称/根路径标签也采用省略模式。现在关闭列自动缩放，取消名称/路径标签的省略与水平压缩，按实际字体测量完整名称、根路径，加上图标、间距、缩进和文本边距来确定内容宽度。内容列至少填满视口，较长时由原生水平滚动显示；不扩大整个侧栏来代替内容滚动。

每个节点缓存一次测得的文字宽度和展开子树最大宽度；分支改变只失效本分支及祖先聚合，用户展开/收起后同步更新。全量刷新和“收起全部”清除展开聚合，项目切换通过 session 身份重建树。拖动侧栏时只应用缓存宽度与当前视口，不重新遍历或测量文字。首次展开新增节点仍在 MainActor 测量文字，大目录的首次测量延迟尚无数据；缓存不代表该阶段已达到性能预算。列缩短时约束原生滚动偏移，避免滚到空白尾部。

树的水平滚动槽与竖直槽都固定预留 8 pt，只有内容溢出时绘制 4 pt 滑块；轨道透明。横向/纵向 scroller 以对应方向的 frame 初始化。原生列行为依据 [Apple 的列自动缩放说明](https://developer.apple.com/documentation/appkit/nstableview/columnautoresizingstyle-swift.property)，没有调用私有 API。实际长名、深层目录、双轴滚动、缩放和滚动槽显示仍待窗口验收；后台编译与源码复核不能视为像素验收。

## 应用标识（build 10）

按用户要求建立与 HyHub 同系列的 HyCode 图标，采用直观的 `</>` 代码符号。PNG 为唯一源图，由本项目脚本后台导出 ICNS；应用包、欢迎页和未打开项目的头部使用同源资源。图稿来源、提示词和资源路径见[品牌说明](BRANDING.md)。没有迁入 HyHub 原图或私有代码，未操作任何应用、Dock 或 Finder 图标缓存。

## 比例拖动与残留线收口（build 11）

用户继续报告掉帧与拖动线残留。原四条分隔各自维护 hover/anchor，依赖 enter/exit 清除，缺少失焦统一收尾；鼠标松开后重新计算 hover 还会点亮当前分隔。现在统一为工作台一个交互状态和一个图层，指示几何只根据当前 presented 分隔计算，两端仍缩进 10 pt。结束时清空拖动、悬停和键盘指示，隐藏图层并清空 frame/color；只允许真正的 mouseMoved 再次激活悬停，迟到的 enter 不会重亮。行为边界参考 [Apple tracking area 说明](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TrackingAreaObjects/TrackingAreaObjects.html)。

窗口失去 key、应用失活、最小化、关闭、detach、显隐布局变化都有清理路径；分隔按下后成为第一响应者以接收 Esc。显示回调检查主按钮是否已松开，漏收 mouseUp 时也结束交互并停止拖动刷新。所有回调与图层都由 MainActor 管理，没有全局键鼠监听或系统设置修改。

显示回调直接应用本帧最新原生几何，不再先标记 needsLayout 等下轮；没有强制递归 layoutSubtreeIfNeeded。相同尺寸不重传，隐藏宿主保留内容尺寸，避免重复零尺寸重排。拖动期间同停靠/同项目的新内容只保留最新一份 root，结束后一次重绑；停靠或项目改变先丢弃旧待绑内容并结束拖动。独立子视图仍可能因自身观察而更新，这不是全面暂停 SwiftUI 更新。SwiftUI 内容禁用隐式几何动画，原生显隐动画继续由工作台负责。

新增 `ResizeDisplayTick` / `HostRootUpdate` 可选 signpost，默认不主动采集，不记录路径。9 项无 GUI 测试覆盖松手无 exit、失焦、迟到 enter、跨分隔、突发事件合并、最终提交、无效请求、隐藏分隔、圆角和最新几何。它们只验证纯状态与矩形，不能证明 AppKit 实际事件投递、图层显示、NSHostingView 调整帧的耗时或真实 FPS 已通过。

## 控件反馈与最近项目首页（build 12）

原项目弹层的悬停色与深色外框同为 `#26282C`，触发 hover 后也看不出变化；选中按钮此前没有独立按下色。现在共享控件表面区分普通和选中的悬停、按下状态，并为键盘焦点绘制细轮廓。禁用入口保持弱化，不显示悬停或可点击光标。原生菜单锚点负责命中与键盘激活，反馈绘制在 SwiftUI 标签下方；build 33 弹出内容改用共用工作台菜单，不再进入 NSMenu 跟踪。

工具按钮扩展为六种有界缓存状态，保留蓝底白图标的选中语义；按下立即反馈，不等待长按阈值。项目树可见行新增本地悬停底色，标签激活区使用共用按钮反馈。光标使用所属原生视图的 cursor rect，不维护全局 NSCursor push/pop 栈。反馈只改变颜色和局部绘制，不添加缩放、几何动画、目录读取或拖动期间的全局观察状态。

未打开项目时，中央欢迎页展示已有最近项目；与顶部弹层共用项目行、`RecentProjects` 历史和 `store.switchProject`。展示不解析访问书签、不扫描目录；用户点击才走现有打开逻辑。无历史时只显示打开操作，有历史时中央宽度达到 720 pt 使用并排布局，否则上下排列；整个欢迎页共享一个纵向滚动区及固定透明滚动槽。打开项目后若无文件标签，中央仍为空白，不恢复目录列表。

这些是代码实现和后台检查范围；真实悬停、按下、光标、焦点与弹层命中仍待窗口验收，没有启动应用验证视觉或采集帧率。

## 当前项目身份（build 13）

此前无项目时左上角沿用应用名“HyCode”，容易被理解成项目名称。现在空状态明确显示“打开项目”；打开后，头部名称、徽标与“打开的项目”分组从同一当前目录身份派生，路径先标准化；悬停帮助和无障碍标签包含完整路径。“最近的项目”继续排除当前项，历史记录不自动成为当前项目。当前仍是单窗口、单项目，未新增多项目会话、新建或克隆操作，也未导入参考应用的历史数据。

用户确认截图中尚未打开项目，需要调整下拉面板的分组与内容。顶部按参考排列“新建项目…”、“打开…”、“克隆仓库…”；新建和克隆尚未实现，明确置灰，不触发文件写入或进程。build 33 面板宽 512 pt，项目行统一 52 pt、分组标题和操作行 28 pt；列表按实际条目高度收缩，上限 440 pt 后纵向滚动，消除旧固定容器的多余留白。build 33 改用无箭头的非 key 子面板，方向键/Tab/Home/End/Enter 选择和打开，Escape/窗口失焦/外部点击关闭；不是与参考截图完全一致的像素验收。

## 项目树整行高亮（build 14）

用户指出选中与悬停边缘不齐，提供 VSCode 整行变色参考。源码确认选中背景曾额外水平缩进 2 pt，悬停却直接填充行 bounds；根路径触发横向长列时，右侧边界在视口外，更容易只看到左侧错位。现在两种背景均填充同一完整行 bounds，不按 cell 或目录层级计算，plain 表格明确使用 regular 选中绘制路径。图标、展开箭头和文字继续保留原层级缩进；完整名称列宽、横向滚动与固定 8 pt 透明槽不变。

原树 hover 沿用普通按钮背景，深色下比失焦选中背景更亮。现在树使用独立浅悬停色（深色 `#24262B`、浅色 `#F2F3F6`），保留活动/失焦选中色区别。不增加视图、扫描、定时器或全局观察状态，也不将颜色与矩形修改称为实际窗口验收。真实不同层级、横向滚动、悬停退出、焦点变化和像素边缘仍待验证。

## 项目树内边距与滚动槽（build 15）

用户要求横向滚动槽在列表内部占位、左右对齐、行高亮轻微圆角，以及滚动条避开面板圆角。现在树滚动区固定左侧 12 pt、右侧 4 pt、底部 8 pt 留白；右侧 4 pt 加原有 8 pt 纵向槽，与左侧 12 pt 对称。横向槽仍固定 8 pt，位于同色列表底带内，滑块中心离面板底边 12 pt；竖直滑块中心离右边 8 pt。树的 NSScrollView、NSClipView 和外部留白统一使用 panel 纯色，关闭默认边框；滚动条轨道仍透明，不出现独立异色底角。

悬停和选中共用 4 pt 圆角、上下各 1 pt 的绘制方法，只使用行的可见横向范围，纵向保持完整行几何，不按目录深度缩短。所属 clip 的横向偏移或宽度变化时，仅将已存在的高亮行标记重绘，避免原生滚动复制旧像素后残留旧圆角；不测量文字、重载树或修改工作区状态。观察器限定所属 clip，在 detach/释放时移除，没有全局事件监听。

本轮仅后台编译、静态检查及现有测试；未创建额外 AppKit 测试宿主。实际滚动槽占位、面板圆角安全距离、不同层级与横向滚动/缩放后的背景边缘仍待真实窗口验收。

## 透明滚动槽与展开准备（build 16）

用户仍看到滚动条底板和右下角方块。此前只覆盖 `drawKnobSlot`，仍进入 NSScroller 的系统整段绘制；现在在固定 legacy 模式下直接调用自己的滑块绘制，不调用系统底板绘制。树 NSScrollView 本体也不再绘制系统交叉角，`drawsBackground = false`；内容区由 NSClipView 绘制 panel，空槽透出外部 panel。保留 8 pt 固定占位、4 pt 滑块、内侧留白与圆角，未改动原生命中和拖动算法。实际原生绘制仍待窗口核验，不将源码覆盖等同于像素已通过。

Rust 目录读取本来已在后台，但新节点的全部文件名测量原先在 MainActor 的宽度聚合路径同步执行，常见系统图标也在每个 cell 创建时重复请求。现在 `ProjectTreeText` 使用一个独立 actor，在后台以同尺寸 system 字体准备名称宽度；每 64 项及返回前检查取消。WorkbenchStore 在同一请求/会话校验后先写宽度，再公布 snapshot 和目录修订；刷新/关闭一并释放。普通节点复用这些宽度，主线程只保留根名称/路径及短状态行测量与必要的聚合。项目树图标按固定符号复用，恢复展开时跳过已经展开的项。不递归预读、不加索引、不开启新服务。

新增 4 项无 GUI CoreText 测试覆盖 Unicode 与路径身份、空/空白名称、取消及独立批次；它们不验证 AppKit 排版等价或真实首帧。读取和文字准备的临时样本分阶段记录见[性能页](PERFORMANCE.md#目录展开准备build-16)，不据此判定用户截图中全部停顿的原因或宣布卡顿已消失。

## 根名称、路径提示与右键菜单（build 17）

根节点只显示项目名，移除名称后面的磁盘路径及其宽度计算；完整目录/文件名称仍可横向滚动。真实条目的整行和 cell 都提供完整文件路径提示，名称、信息面板和复制路径共用 file URL 生成方法，根相对路径复制为 `.`。拼接时显式传入已知目录类型，避免 Foundation 为推断类型同步查询磁盘元数据；不规范化或解析符号链接。

目录/文件右键自 build 33 使用共用工作台菜单，提供文件打开或目录展开/折叠、在访达中显示、完整/相对路径及名称复制、文件信息、刷新当前目录或文件所在目录。目标来自右键点中的行，菜单捕获条目值与会话身份；旧项目菜单动作失效。菜单命令闭包弱引用协调器；每条菜单链共用一个临时事件监听器，实时读取子菜单行的屏幕坐标，滚动时收起后续子级。当前树菜单没有增加新建、剪切、粘贴、重命名或删除文件，不用空操作伪装可用功能；编辑区菜单自 build 30 改为工作台纯色圆角面板，见[编辑反馈](EDITING.md)。

右下方块位于双滚动槽交叉区域，不是业务按钮。上一版只覆盖父视图绘制仍不足以消除截图残留；本版清除无表头树的默认 table corner，并在公开 scroller frame 计算出的交叉区域使用同色、不可操作且无无障碍入口的角块覆盖层。只按实际交叉几何调整，不查询或修改 AppKit 私有子视图；初始零尺寸或空交集不赋无效 frame。槽和圆角留白继续固定保留。

本轮新增 2 项纯 Foundation 路径测试，验证根路径与空相对路径、中文/空格/字面百分号及文件/目录类型提示。菜单命中、提示、角块覆盖、剪贴板及访达属于真实交互，未执行；后台编译和源码复核不能代替这些窗口验收。

## 独立滚动槽与启动恢复（build 18）

用户新截图仍有右下方框，build 17 的覆盖办法未达到预期。现在移除覆盖层，项目树使用独立滚动容器：内部 NSScrollView 不安装任何系统滚动条，两个 WorkbenchScroller 作为其兄弟控件各占固定 8 pt 槽，交汇处仅由容器绘制统一 panel。没有系统双滚动条交叉角、额外角块或私有子视图查询。内容滚轮、触控板、键盘和树定位仍使用原生 NSScrollView/NSClipView；原生反射回调同步独立滑块，滑块拖动及分页/行进操作只修改 clip 偏移。列宽、圆角高亮与外部内边距保持既有规则，偏移同步不重载树或更新工作区观察状态。

`ProjectTreeScrollAxis` 的 3 项纯模型测试验证滑块值与偏移映射、内容收缩后无滚动范围、无效/越界输入钳制。它们不代替真实原生拖动、滚轮、键盘、无障碍与像素验收，方框是否实际消失仍需窗口确认。

同一 RecentProjects 记录保存 startupPath。打开更新；显式“关闭项目”清空启动项，历史仍保留；普通退出不清空，因此下次启动恢复。旧数据缺少字段时使用原历史首项，编码明确保留 null，以区别用户关闭与旧版迁移。启动路径必须匹配已有历史，不自动改开其他项目。新增 4 项纯 Foundation 测试覆盖书签保留与恢复、旧记录迁移、显式关闭与迟到书签、未知启动项。

场景首次出现只调用一次恢复；主动打开、关闭或切换会消费启动机会。后台书签解析使用 withoutUI/withoutMounting，结果通过原项目意图校验后进入既有 openProject/WorkspaceAccess/目录读取路径。目录失效或访问失败在树内显示错误与重试，不自动弹选择窗口。启动不恢复标签、目录展开或工具布局，仍只打开项目根并懒加载；没有新增扫描、服务或第二个工作区所有者。真实重启和书签权限恢复本轮未执行。

## Flutter 工具界面对齐（build 27）

按已有 WebStorm 截图统一入口：窗口顶部显示设备与入口配置，紧邻运行/调试、热更新和停止；窄窗口将次要操作收进配置菜单。底部使用单一会话胶囊、紧凑图标工具条与线程/变量、控制台、Inspector、测试结果内容。运行配置改为可取消的草稿弹层；断点有独立即时编辑弹层，构建/Doctor 位于配置菜单。状态缩成底部单行，不再重复占一整块状态/启动表单。

调用栈和变量使用原生分隔；内容宽至少 480 pt、高至少 120 pt 时左右排列，窄面板高至少 220 pt 时上下排列；其余尺寸合为单层滚动内容，仍可到达求值入口。滚动槽、纯色、控件反馈沿用工作台规则。输出只在控制台子视图读取；分隔跟踪不把逐帧尺寸写入工作台观察状态。打开弹层/切换内容不执行工具任务，真实暂停事件选中线程/变量并展开面板，测试动作选中结果，普通运行/构建选中控制台。

配置确认会核对工作区上下文、原值和忙碌状态，避免旧弹层覆盖新配置；多行输入保留原始换行，到确定时才生成参数数组。没有新增 SDK 命令、外部依赖或后台服务；没有重新操作 WebStorm。窗口像素、焦点、滚动、快捷键和拖动流畅度继续未验证，不能由静默编译推定与参考效果完全一致。

## 参考来源与观察范围

视觉参考用户提供截图及本机 WebStorm 2026.2.3 / WS-262.10968.77 的 Islands 布局。build 3 只读核对其主题资源，build 4 曾按用户明确授权操作 WebStorm 的项目窗口和底部工具窗口，观察关闭后内容补位、重新展开恢复尺寸，并恢复原展开布局。该观察已结束；当前 build 23 只做后台验证。

没有复制 JetBrains 主题文件、图标、字体或实现代码，没有引入 WebStorm 运行依赖。用户项目路径、源码、日志和原始截图不迁入公开仓库。观察 WebStorm 不等于授权启动 HyCode，也不能代替 HyCode 视觉、焦点或动画验收。

## 实现与责任

| 入口 | 职责 |
| --- | --- |
| [Package.swift](../Package.swift)、[HyCodeApp.swift](../app/macos/Sources/HyCodeApp.swift) | Swift 目标、系统菜单、快捷键及应用场景 |
| [WorkbenchView.swift](../app/macos/Sources/Workbench/WorkbenchView.swift) | 双侧工具条、五区内容、标签、面包屑与状态栏 |
| [WorkbenchDocking.swift](../packages/HyCodeWorkspace/Sources/WorkbenchDocking.swift)、[WorkbenchDockingTests.swift](../packages/HyCodeWorkspace/Tests/WorkbenchDockingTests.swift) | 工具分组、排序、活动选择及后台状态验证 |
| [WorkbenchToolRail.swift](../app/macos/Sources/Workbench/WorkbenchToolRail.swift)、[WorkbenchToolPresentation.swift](../app/macos/Sources/Workbench/WorkbenchToolPresentation.swift) | 原生长按、拖放、插入标记、工具图标及菜单排序 |
| [WorkbenchCanvas.swift](../app/macos/Sources/Workbench/WorkbenchCanvas.swift) | 原生容器、稳定宿主、尺寸所有权及显隐动画 |
| [WorkbenchResizeHandle.swift](../app/macos/Sources/Workbench/WorkbenchResizeHandle.swift) | 原生鼠标、光标、键盘和无障碍分隔事件适配；不拥有高亮图层 |
| [WorkbenchResizeInteraction.swift](../packages/HyCodeWorkspace/Sources/WorkbenchResizeInteraction.swift)、[WorkbenchResizeInteractionTests.swift](../packages/HyCodeWorkspace/Tests/WorkbenchResizeInteractionTests.swift) | 唯一分隔交互状态、最新事件合并、收尾与圆角内指示几何；无 GUI 事件序列测试 |
| [WorkbenchPaneSizes.swift](../packages/HyCodeWorkspace/Sources/WorkbenchPaneSizes.swift)、[WorkbenchLayoutTests.swift](../packages/HyCodeWorkspace/Tests/WorkbenchLayoutTests.swift) | 无 GUI 的四区约束、取整、尺寸恢复与动画中间态验证 |
| [WorkbenchToolArtwork.swift](../app/macos/Sources/Workbench/WorkbenchToolArtwork.swift)、[WorkbenchToolTile.swift](../packages/HyCodeWorkspace/Sources/WorkbenchToolTile.swift)、[WorkbenchToolTileTests.swift](../packages/HyCodeWorkspace/Tests/WorkbenchToolTileTests.swift) | 按钮与预览共用位图、缩放/状态缓存、无 GUI 像素验证 |
| [WorkbenchPerformance.swift](../app/macos/Sources/Workbench/WorkbenchPerformance.swift) | 可选性能区间，不记录项目数据或自动采集 |
| [WorkbenchMenuButton.swift](../app/macos/Sources/Workbench/WorkbenchMenuButton.swift) | 自有紧凑标签、原生 NSButton 命中与共用弹层生命周期，避免额外菜单箭头和默认着色 |
| [WorkbenchTheme.swift](../app/macos/Sources/Workbench/WorkbenchTheme.swift)、[WorkbenchTab.swift](../app/macos/Sources/Workbench/WorkbenchTab.swift) | 配色、尺寸、按钮及标签样式 |
| [WorkbenchPointerRegion.swift](../app/macos/Sources/Workbench/WorkbenchPointerRegion.swift) | 不截获点击的原生光标区域，按可用状态注册手形 cursor rect |
| [WorkbenchHeader.swift](../app/macos/Sources/Workbench/WorkbenchHeader.swift)、[WorkbenchWindowChrome.swift](../app/macos/Sources/Workbench/WorkbenchWindowChrome.swift) | 纯色头部及所属窗口外观/拖动适配，不激活窗口 |
| [WorkbenchStore.swift](../app/macos/Sources/Workbench/WorkbenchStore.swift) | MainActor 工作区、授权 URL、请求取消和代次隔离 |
| [NativeProjectTree.swift](../app/macos/Sources/ProjectTree/NativeProjectTree.swift) | 项目树协调器、稳定节点、懒加载与回收、选中和右键目标 |
| [ProjectTreeOutline.swift](../app/macos/Sources/ProjectTree/ProjectTreeOutline.swift) | 原生树视口、完整列宽与 clip 观察生命周期 |
| [ProjectTreeRowView.swift](../app/macos/Sources/ProjectTree/ProjectTreeRowView.swift) | 整行悬停/选中绘制、名称与图标 cell；与目录读取分离 |
| [ProjectTreeScrollContainer.swift](../app/macos/Sources/ProjectTree/ProjectTreeScrollContainer.swift)、[ProjectTreeScrollAxis.swift](../packages/HyCodeWorkspace/Sources/ProjectTreeScrollAxis.swift)、[ProjectTreeScrollAxisTests.swift](../packages/HyCodeWorkspace/Tests/ProjectTreeScrollAxisTests.swift) | 原生内容滚动、独立双槽与滑块/偏移映射的后台测试 |
| [WorkbenchContextMenu.swift](../app/macos/Sources/Workbench/WorkbenchContextMenu.swift)、[WorkspaceEntryPathTests.swift](../packages/HyCodeWorkspace/Tests/WorkspaceEntryPathTests.swift) | 共用右键菜单链与命令生命周期；完整/相对路径与编码的后台验证 |
| [FileInformationView.swift](../app/macos/Sources/Workbench/FileInformationView.swift) | 只读文件元数据；无目录表格 |
| [编辑专题](EDITING.md) | 原生文本视图、Rust 文本/修订、自动保存、关闭保护及完整源码地图 |
| [WorkbenchProjectSwitcher.swift](../app/macos/Sources/Workbench/WorkbenchProjectSwitcher.swift)、[RecentProjects.swift](../packages/HyCodeWorkspace/Sources/RecentProjects.swift)、[RecentProjectTests.swift](../packages/HyCodeWorkspace/Tests/RecentProjectTests.swift) | 分组切换面板、本地最近记录、去重/上限/书签模型验证 |
| [WorkbenchWelcomeView.swift](../app/macos/Sources/Workbench/WorkbenchWelcomeView.swift)、[WorkbenchProjectRow.swift](../app/macos/Sources/Workbench/WorkbenchProjectRow.swift) | 无项目欢迎页、响应式最近列表与共用项目行，不新增历史或读取所有者 |
| [WorkbenchScrollStyle.swift](../app/macos/Sources/Workbench/WorkbenchScrollStyle.swift) | 原生固定占位透明轨道滚动条；SwiftUI 内容内 marker 只适配自己的最近滚动祖先 |
| [ProjectTreeText.swift](../packages/HyCodeWorkspace/Sources/ProjectTreeText.swift)、[ProjectTreeTextTests.swift](../packages/HyCodeWorkspace/Tests/ProjectTreeTextTests.swift) | 单个非 MainActor 工作器准备文件名宽度、取消与批次隔离；不改变 Rust 元数据接口 |
| [DirectoryProbe/main.swift](../tools/DirectoryProbe/main.swift) | 默认使用临时样本的无 GUI 目录读取探针 |
| [BrowserState.swift](../packages/HyCodeWorkspace/Sources/BrowserState.swift)、[NativeDirectoryReader.swift](../packages/HyCodeWorkspace/Sources/NativeDirectoryReader.swift) | 标签/历史、后台工作器及 FFI 生命周期 |
| [directory.rs](../crates/hycode-core/src/directory.rs)、[ffi.rs](../crates/hycode-core/src/ffi.rs)、[C 头文件](../bindings/CHyCodeCore/include/hycode_core.h) | 只读单层枚举、资源上限、ABI 1、UTF-8 和释放责任 |

单次最多返回 20,000 项、检查 50,000 项，超限或跳过条目明确提示。默认隐藏点文件；符号链接可见但不跟随。路径策略不宣称能够防御并发重命名竞态的沙箱。阻塞中的系统文件调用返回后仍检查取消和会话。缓存随刷新/关闭清理；全工作区总缓存预算和大规模性能仍待后续实测。

## 构建与证据

当前验证环境为 Apple Silicon、macOS 27.0.1、Xcode 27.1 / Swift 6.4、Rust 1.96.0；部署目标 macOS 14，旧系统运行未验证。工具链和依赖由 [rust-toolchain.toml](../rust-toolchain.toml)、[Cargo.lock](../Cargo.lock) 固定。

```sh
# 本地开发应用：不启动、不安装、不进行分发签名
nice -n 10 bash scripts/build_macos.sh release
# 无 GUI 的格式、静态、单元/桥接和文档检查
nice -n 10 bash scripts/check_native.sh
# Swift 一侧地址检查，Rust 静态库未按 ASan 重新插桩
nice -n 10 swift test --jobs 2 --disable-xctest --sanitize address
```

产物 `build/HyCode.app`，Bundle ID `io.github.hhcme.hycode`，版本 `0.1.0` / build `30`。单独构建 Swift 包前先执行 `bash scripts/build_core.sh`。不运行 `swift run HyCode` 或 UI 测试宿主补验收；`HyCodeDirectoryProbe` 和显式 SDK 的 `HyCodeDartProbe` 均为无应用宿主的后台探针，后者不运行 Pub 或用户项目。macOS 27 的 host proc-macro 链接绕过仅限定在本项目 release build-override，见 [Rust #157750](https://github.com/rust-lang/rust/issues/157750)。

- Rust 15 项单元测试通过，含新增 5 项语法/嵌入范围测试、既有 5 项文本/FFI 测试；格式、Clippy、C11/C++17 头文件检查通过。
- build 32 当时全量 169 项 Swift 与 15 项 Rust 静默检查通过，本批新增 4 项共享样式/工具轨道/窗口按钮几何/最小工作区回归；build 31 新增 8 项 Dart 指令 URI/引用分节/注释边界/菜单宽度回归；build 30 新增 6 项编辑反馈/菜单回归；build 29 新增 8 项项目分析/监听/队列回归。项目行为与限制见[项目后台诊断](PROJECT_ANALYSIS.md)。此前 build 27 的 Swift 125 项后台测试通过；build 27 新增 3 项配置草稿/冲突/校验测试；此前 10 项 Flutter 配置/设备/状态/断点/test reporter/Inspector 与 stdio fixture 用例；此前 11 项悬浮解析/整词命中/缓存与取消/语义代次/屏幕定位/桥接回归，既有 16 项协议/进程/SDK/包模型、8 项视口调度/缓存/取消/远处高亮测试、3 项行号裁剪像素回归、7 项行索引/高亮桥接与 13 项增量文本/安全保存测试；其余 54 项：9 项工作区/桥接、11 项布局、6 项停靠状态、3 项预览像素合成、7 项最近记录/启动恢复、9 项分隔交互状态、4 项后台文字准备、2 项路径、3 项滚动偏移；覆盖 16 种显隐组合、全部组合间动画中间态不重叠、像素边界、小窗口尺寸、拖动及缩窗恢复。测试目标不链接 AppKit 窗口宿主。
- build 26 的 10 项 Flutter 模型/stdio fixture 与既有 12 项协议/进程测试通过 Swift ASan（本轮未重跑 sanitizer）；此前 11 项悬浮模型测试、16 项 Dart 协议/进程/SDK/包模型测试、11 项视口/高亮测试、3 项行号裁剪像素回归、7 项行索引/高亮桥接测试、13 项 Swift 文本/保存测试分别通过 Address Sanitizer；原 7 项 Swift 工作区测试曾通过 ASan，未重跑全部几何测试的 sanitizer，也不推导 Rust 内部 sanitizer 已验证。
- build 5 的窄窗尺寸跳动已保留回归；build 6 停靠、原生拖放、宿主复用、显示刷新及释放路径经独立只读复核，未发现可确认的阻断问题，仍不是实际窗口验收。
- 当前项目诊断计数/点击定位及此前 build 27 的运行配置/断点弹层、自适应调试分区和 Flutter run/debug/热更新、设备、build/test、Inspector 及 Dart 紧凑悬浮/展开说明/候选菜单、中键/⌘点击/下划线清理、诊断/导航、结构、Pub 清单协调/网络/停止与 SDK 设置等端到端交互，以及原生行号/软换行、高亮/主题/开关、原生输入法、撤销/重做、设置/保存/关闭交互，以及既有项目树内边距/圆角高亮、当前项目标题、控件反馈/最近项目欢迎页、应用图标、完整树名称/路径、独立双槽与原生滚动同步、项目切换面板、真实启动恢复和书签权限恢复、滚动条占位/透明轨道、真实长按拖放、命中/排序、跨角滚动状态、分隔悬停清除、窗口视觉、动画、拖动性能、菜单/键盘/无障碍及焦点未验证。本轮没有启动或操作应用，没有使用剪贴板或模拟器。
- 没有进行分发签名、公证、上传或公开二进制发布。开发包附带项目许可与第三方通知。

build 26 的 DAP 模型/stdio fixture 通过与真实 SDK 分开记录：生成 Dart 控制台探针在本机外部 fork 上因 VM Service 启动参数不支持而未通过，不能据此认定真实断点/栈帧可用；Dart LSP 生成样本继续通过。没有运行 Flutter 应用、设备、模拟器、用户项目或 Pub/build/test SDK 命令，真实运行/调试与原生菜单效果均未验证。

## 本地构建记录

2026-10-22 build 30 增强编辑区反馈：插入点独立高对比色、像素对齐宽度及匹配的闪烁重绘、I-beam、活动当前行与非活动选区；编辑右键使用工作台纯色圆角菜单，保留编辑和语义动作及键盘/关闭生命周期。文本视图单独拆出，Rust 文本、输入法和原生撤销所有权保持一致。157 项 Swift、15 项 Rust 全量静默检查通过，其中 6 项新增颜色/几何/重绘/菜单导航与屏幕定位回归；独立复核发现的宽光标脏区问题已修复并复核，本批未执行 sanitizer 或 SDK 探针。Release 开发包约 139.8 MiB、arm64、0.1.0 / build 30、最低系统声明 macOS 14；可执行文件 SHA-256：`1598fdf987331e9e70b3e98369750cf09c3d222518740131f481b7eca01a49d5`。源码和限制见[后台记录](evidence/2026-10-22-build30-editor-feedback.json)及[编辑说明](EDITING.md)。没有启动/安装应用、访问剪贴板、进行分发签名或提交推送；真实光标闪烁、菜单点击、IME/VoiceOver、窗口焦点和帧率未验收。

2026-10-22 build 29 接入项目后台诊断：打开项目分析未打开的 Dart/Web 文件，模块变更检查反向关联；递归文件监听、磁盘与原生覆盖交接、JSON 导入方和删除清理，左下角错误/警告/建议计数及可定位的按文件分组问题列表。151 项 Swift、15 项 Rust 全套静默检查通过，新增分析/监听/队列及进程生命周期 14 项 Swift ASan 通过；Dart 3.11.5 和固定 Web 服务只在生成的临时样本上进行协议验证。独立复核发现的 TS 磁盘快照、删除关联/空 scope、切项目代次问题均已修正，未再确认 P1/P2。Release 开发包约 139.7 MiB、arm64、0.1.0 / build 29、最低系统声明 macOS 14；可执行文件 SHA-256：`ee4f1bda863b1642bbe0e51fef0caebb95426787cd5857fdf23fbbe0f0a111db`。行为、预算和未覆盖范围见[项目后台诊断](PROJECT_ANALYSIS.md)。真实窗口/点击定位/项目规模与渲染性能、旧系统运行仍未验收；未启动/安装应用，未签名发布或提交推送。

2026-10-22 build 27 按用户已有 WebStorm 截图整理 Flutter 工具界面：顶部设备与配置菜单、底部会话胶囊和图标工具条、调用栈/变量自适应分区、独立配置/断点弹层。配置草稿在确认时检查上下文/原值/忙碌状态；复核发现的多行输入吞换行和低高度裁剪已修正。125 项 Swift、15 项 Rust 全量静默检查通过；本轮没有执行 SDK、GUI 或 sanitizer。Release 开发包约 20.9 MiB、arm64、版本 0.1.0 / build 27、最低系统声明 macOS 14；可执行文件 SHA-256：`1df938f73407d6af412cf18250602e4a65a93c12af46babe45009ad5079e9821`。源码与限制见[后台记录](evidence/2026-10-22-build27-webstorm-tools.json)。真实窗口、焦点、滚动、分隔拖动和帧率未验收，没有启动/安装应用、签名发布或提交推送。

2026-10-22 build 26 将完整 Flutter 开发能力确认为九类必做范围，见[能力清单](FLUTTER_PLAN.md)，并接入首批运行链路：显式设备刷新/选择、每工作区运行配置、SDK DAP、普通/条件/日志断点、首个停止线程的栈帧/作用域/变量/求值、手动及可选保存热更新、build/test/Doctor 与基础 Widget summary 树。Rust 仍独占正式文本；断点有磁盘基线与未保存投影，失败保存/部分保存/丢弃分开，后续 adapter 事件驱动确认/移动。修正初始化能力/launch 写入竞态、旧包元数据、连续保存重载、过期变量/错误、Inspector isolate 代次、启动错误保留与结束清理。完整 Inspector/DevTools、智能补全/跨文件修复重构、多 SDK/命名配置、attach、测试调试/覆盖率显示等仍待实现。122 项 Swift、15 项 Rust 全量静默检查通过，22 项运行/协议/进程测试另通过 Swift ASan；Dart LSP 临时样本继续通过。真实 SDK 的生成 Dart 控制台 DAP 探针因本机 fork 不支持 VM Service 参数而未通过，不能计为真实调试验收；没有运行 Flutter GUI、设备、用户项目、Pub/build/test 或操作桌面。一次并行 Rust 高亮测试命中既有 100 ms 预算上限，失败已保留，改成串行降载后全套通过，生产预算/断言未改，实际冷缓存/窗口性能仍未验证。Release 开发包约 20.5 MiB、arm64、版本 0.1.0 / build 26、最低系统声明 macOS 14，可执行文件 SHA-256：`11404da84e2a562fb722192662fa262b91bdb27956c0477777a238850dd1c518`。源码、协议替身、失败与验证限制见[后台记录](evidence/2026-10-22-build26-flutter-runtime.json)。真实 Flutter run/debug/热更新、设备、测试、构建、Inspector 和窗口交互均未验证，没有自动启动/安装 HyCode，没有签名、发布或提交推送。

2026-10-22 build 25 针对悬浮卡片过大、原始 Markdown 围栏外露与响应迟钝，拆分着色签名、声明来源/包路径和说明；默认内容自适应高度、无箭头，右下角菜单提供导航和展开说明。悬浮按整个符号复用，单工作任务并行查询 hover/定义，16 项语义代次缓存含空结果；普通新目标 140 ms，⌘悬浮立即请求。确认定义后显示下划线/手形，支持中键、⌘点击和 ⌘B；滚动/编辑/失焦等清理，恢复被临时覆盖的诊断下划线。复核中修正 Pub 收尾缓存、卡片空白桥接、锚点屏幕定位和短内容截断后的展开入口。112 项 Swift、15 项 Rust 及格式/静态/头文件检查通过，新增 11 项纯悬浮模型回归另通过 Swift ASan；真实 Dart 3.11.5 临时文件探针验证构造函数 hover 分节、整词范围及同符号一致性。协议往返仅是就绪后的小样本，不表示真实窗口延迟/帧率。Release 开发包约 19.5 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`eb96fbaa71326976c1a72946f44e26679ed68a05a05f3a07475adaee4d14df37`。详细命令与源码哈希见[后台记录](evidence/2026-10-22-build25-hover-navigation.json)。真实卡片/菜单、下划线/光标、中键/快捷键、跨屏/失焦和性能均未窗口验证；仅静默构建/模型与 stdio 探针，没有启动、重启或操作应用/设备、剪贴板，没有安装、签名发布或提交推送。

2026-10-21 build 24 接入 Dart/Flutter 首批 SDK 语义与 Pub 依赖：未保存增量诊断、悬浮、定义/引用、显式补全、格式化、文件符号和外部源码只读标签；依赖面板显示解析包版本/来源并提供显式 Pub 操作。清单缓冲保存/冻结/重载与窗口退出保护协调；进程组回收、阻塞管道、重启期间新增文档和活动包切换问题已修正。101 项 Swift、15 项 Rust 及格式/静态/头文件/文档检查通过，新增 16 项协议/进程/SDK/包测试通过 Swift ASan。官方 Dart 3.11.5 临时样本 stdio 探针验证诊断、未保存修复、hover、定义（含 SDK 源码）、引用、补全、层级符号及格式化，磁盘未变；没有跑 Pub、GUI、网络依赖或用户项目。独立只读复核未发现剩余可确认 P1/P2。Release 开发包约 19.2 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`83b925d5432fed306b81de903ff44b3affd9a55238ba3bf96201dfce243c4a2a`。源码、探针及验证限制见[后台记录](evidence/2026-10-21-build24-dart-tooling.json)和[工具说明](DART_FLUTTER.md)。Dart 3.11.5 无版本诊断只能尽力显示，不能证明修订；真实窗口、Pub 网络、Flutter 项目与性能未验证，运行/调试/热重载/Inspector 和跨文件重构尚未实现。本轮没有启动/重启应用、操作桌面或剪贴板，没有安装、签名发布或提交推送。

2026-10-21 build 23 针对用户“滚动后仍白、高亮反应慢”的反馈，修正滚动不断取消在途请求和只保留单屏颜色的问题。滚动加入一个工作任务，完成后读取最新视口；预取附近范围、保留最多 8 个颜色窗口，命中不重新查询，淘汰不抹掉重叠区域。编辑/主题/隐藏等仍使旧票据失效，预取超预算降级可见范围，旧范围失败后继续处理已变化的新范围。新增 8 项后台测试，覆盖持续滚动、缓存/淘汰、Unicode、取消和生成 Dart 文件远处视口；85 项 Swift、15 项 Rust 及静态/格式/头文件/文档检查通过，本轮 11 项视口/高亮测试另通过 Swift ASan。独立复核发现的失败路径丢失最后滚动已修复，未发现剩余可确认 P1/P2。Release 开发包约 18.1 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`345d27fca50bc4962dd39f6495fde5a7cbb982e49bd5aa6aa23c75f67e92d2c9`。源码、生成样本和验证限制见[后台记录](evidence/2026-10-21-build23-syntax-viewport.json)。用户已反馈 build 22 正文恢复，该反馈与自动化验收分开记录；本轮未启动/重启应用、操作桌面或剪贴板，build 23 真实滚动颜色延迟、原生绘制与帧率仍未窗口验证，没有分发签名或发布。

2026-10-21 build 22 针对用户“只有行号、正文空白”的截图修正行号栏越界绘制：显式启用视图裁剪，背景和标签按视图边界与重绘范围的交集绘制，完成后恢复图形状态。新增 3 项纯 CoreGraphics 像素回归通过，覆盖超大/局部/无效重绘范围与状态恢复，另通过 Swift ASan；77 项 Swift、15 项 Rust 测试及格式/静态/头文件/文档检查通过。独立只读复核未发现新增可确认 P1/P2。Release 开发包约 18.1 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`8e96b79d39e3ef4b99405a4f1fb5dee2eef836ae7ce3f70dcf27b4308ef6c717`。源码与验证边界见[后台证据](evidence/2026-10-21-build22-gutter-clipping.json)及[高亮说明](SYNTAX.md)。没有启动、退出或重启应用，没有操作桌面或剪贴板，没有进行分发签名；实际截图症状的恢复及原生正文/标签显示仍未窗口验证。

2026-10-21 build 21 新增原生可见逻辑行号与 Tree-sitter 增量语法着色，覆盖 Dart、Web 常用语法及 C/C++、Rust、JSON/YAML/TOML，设置可分别关闭；诊断、补全和引用关系仍未接入。74 项 Swift、15 项 Rust 测试及格式/静态/头文件/文档检查通过；新增 7 项 Swift 行索引/高亮桥接测试通过 ASan，Rust/C 静态库未插桩。独立复核发现的嵌入范围、合并预算、旧色清理和行索引稀疏块退化均已修正，未发现剩余可确认 P1/P2。37 项锁定 crate 的通知已补齐，36 份保留文件与 crate 原文逐字节一致，另 5 份缺失许可从对应上游提交取得。Release 开发包约 18.1 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`9980c6b98805428e803bab69b0db07ad3c9199d79f6121ed471788d7943ae93e`。源码、许可来源及限制见[后台证据](evidence/2026-10-21-build21-line-syntax.json)，行为与预算见[高亮说明](SYNTAX.md)。本轮没有启动应用、操作桌面或剪贴板，没有进行分发签名；行号、软换行、颜色、IME/Undo 和真实帧率仍未窗口验收。

2026-10-21 build 20 新增基础文本编辑：单击文件打开、原生独立撤销、修改固定标签、默认 800 ms 自动保存及设置开关、手动保存和全部关闭入口保护。Rust 文本修订与增量 C ABI、后台文件读写及权限/冲突/取消已接入。67 项 Swift、10 项 Rust 测试和格式/静态/头文件/文档检查通过，13 项 Swift 文本测试另通过 ASan（Rust 未插桩）。独立复核发现的有效写权限、保存前版本复查、提交后误报与关闭时序问题均已修复，未发现剩余可确认的 P1/P2。Release 开发包约 6.2 MiB、arm64、版本 0.1.0、最低系统声明 macOS 14，可执行文件 SHA-256：`057aab6448e0f4a3135750f16dc2103d7a54441cc819cbdfb8b3571c85cd263f`。源码哈希与限制见[后台证据](evidence/2026-10-21-build20-text-editing.json)，使用与实现边界见[编辑说明](EDITING.md)。没有启动应用、访问剪贴板、操作桌面或进行分发签名；IME、原生撤销、设置、端到端自动保存与关闭提示仍未窗口验收。

以下 SHA-256 仅对应各次 Release 可执行文件，不代替源码提交记录：

| 开发包 | 可执行文件 SHA-256 |
| --- | --- |
| build 1 初始布局 | `b7067c275b35ffcec830a4377c90cad161eed33b69cb311fa0574a8e4a24e341` |
| build 2 样式 | `448cb66401e4d2bed65b8b00ded6514c4be57cdedd151042adc18b02c4d9e700` |
| build 3 WebStorm 参考 | `c5f4c59e5a5e0c0df11623a822611f3bc1643beabefb77fa9dc162a44978a642` |
| build 4 面板动效 | `0112a8b7c2e305b8fc01c67351522a12e2a232c6285a547b114776503763ac13` |
| build 5 纯色四区布局 | `c74760a116300bbdd36dc78b9d31343c598a50fda03b1fc5e8172444036bb4d0` |

2026-10-21 build 5 的 Release 静默打包、格式/静态检查、18 项 Swift 与 5 项 Rust 测试通过。最终开发应用约 2.8 MiB、arm64，最低系统声明 macOS 14；未启动、未进行分发签名或真实窗口验收。

2026-10-21 build 6 的 Release 静默打包、格式/静态检查、24 项 Swift 与 5 项 Rust 测试通过；文档检查覆盖 219 条本地链接和 10 组历史快照。开发应用约 2.9 MiB、arm64。可执行文件 SHA-256：`2a791a2730524529b98221e0c4f2a0d58a02388132c57dc5a3f4c88971122c95`。未启动应用、操作真实窗口或进行分发签名。

2026-10-21 build 7 的 Release 静默打包、格式/静态检查、27 项 Swift 与 5 项 Rust 测试通过，独立源码复核未发现阻断问题。开发应用约 2.9 MiB、arm64，最低系统声明 macOS 14。可执行文件 SHA-256：`3a0cbfd1ca3f3f897a18205a049a1c94a0a22a477e1c7c25392ef69528fc3cd1`。文档检查覆盖 224 条本地链接和 10 组历史快照。本轮未启动应用、操作真实窗口、采集实机帧率或进行分发签名。

2026-10-21 build 8 的 Release 静默打包完成，开发应用约 3.1 MiB、arm64，版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`80ba30e141228094cb43abdd18c915b651ae9a6e6cd1d9bf9bf9feb03b53a0f6`。32 项 Swift 与 5 项 Rust 后台测试、格式/静态/头文件检查通过；独立源码复核发现的刷新展开漏读与平方级节点回收已修复并复核。后台小样本读取记录不能代替树到屏幕的耗时或真实目录速度。本轮未启动应用、操作真实窗口、采集帧率或进行分发签名。

2026-10-21 build 9 的 Release 静默打包、格式/静态/头文件检查与现有 32 项 Swift、5 项 Rust 后台测试通过；独立只读复核未发现可确认的 P1/P2。开发应用约 3.1 MiB、arm64，版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`7ee6a33819aad8f69c9b543c93b61bc5da600a9aa5c8736509b23b4958b6349e`。现有测试没有覆盖 AppKit 的真实文字布局或滚动输入，本轮没有启动应用、操作桌面或进行分发签名。

2026-10-21 build 10 的 Release 静默打包、格式/静态/头文件检查及现有 32 项 Swift、5 项 Rust 后台测试通过。新增系列图标的十尺寸 ICNS、透明角、1024 px 帧一致性及包内 PNG/ICNS 逐字节一致性通过；独立源码复核未发现可确认的 P1/P2。开发应用约 5.4 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`abb80005f0dc8ee8151cdaddc94ef804793f847a160cf510e3149965352fb21f`。图稿与核验见[品牌说明](BRANDING.md)。没有启动应用、操作 Dock/Finder/剪贴板、进行分发签名或公开发布。

2026-10-21 build 11 的 Release 静默打包、格式/静态/头文件检查及 41 项 Swift、5 项 Rust 后台测试通过，其中新增 9 项分隔交互状态测试。独立只读复核未发现可确认的 P1/P2；[后台证据](evidence/2026-10-21-build11-resize.json) 不包含真实窗口或 FPS 数据。开发应用约 5.4 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`895d569ebe5bec66fc248962515487825389bd3dd951fe746dbf4798d9adb351`。本轮没有启动、退出或重启应用，没有操作桌面或进行分发签名。运行中的旧进程不会因文件打包而切换实现，试用需由用户自行退出并重新打开新包。

2026-10-21 build 12 的 Release 静默打包、格式/静态/头文件检查及现有 41 项 Swift、5 项 Rust 后台测试通过。统一控件反馈并加入中央最近项目欢迎页；独立源码复核发现的菜单拖出按压色保留已改为同步原生 cell 高亮，复核未发现剩余可确认的 P1/P2。开发应用约 5.6 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`5cd51ae6420295df33e5bf2160763633270894aed8cb8c188b3686eb578687ca`。源码哈希和验证边界见[后台证据](evidence/2026-10-21-build12-feedback.json)。没有启动、退出或重启应用，没有操作桌面或进行分发签名；真实控件反馈、欢迎页布局与点击仍未窗口验收。

2026-10-21 build 13 按用户确认的无项目状态调整下拉面板：操作区、打开/最近分组与按条目收缩的列表；新建/克隆尚未实现，明确置灰。当前项目头部共用目录身份，空状态显示“打开项目”。Release 静默打包、格式/静态/头文件检查与现有 41 项 Swift、5 项 Rust 后台测试通过；独立源码复核未发现可确认的 P1/P2。开发应用约 5.6 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`1eb13625502d744b671ffb2edc67713155740f98e9ba9fb8c980e2495a1785ee`。源码与验证边界见[后台证据](evidence/2026-10-21-build13-project-switcher.json)。没有启动或重启应用，没有操作桌面、导入其他应用记录或进行分发签名；实际弹层、焦点与视觉仍未验收。

2026-10-21 build 14 统一项目树选中与悬停的整行边界，取消选中背景的额外 2 pt 水平缩进，并使用较弱的树悬停色。Release 静默打包、格式/静态/头文件检查与现有 41 项 Swift、5 项 Rust 后台测试通过；独立源码复核未发现可确认的 P1/P2。开发应用约 5.6 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`af0293b97b91e97f0760d1764f6b0f56603682ad70b100367f096dea6d3650e3`。源码与边界见[后台证据](evidence/2026-10-21-build14-tree-highlight.json)。现有测试不覆盖 AppKit 行绘制；本轮没有启动、退出或重启应用，没有操作桌面或进行分发签名，真实整行边缘与焦点/悬停仍未验收。

2026-10-21 build 15 将项目树滚动区放进固定内边距，横向槽保留在同色列表底带中；高亮左右留白对称，悬停/选中使用可见整行的轻微圆角，滚动与改宽时只重绘已有高亮行。Release 静默打包、格式/静态/头文件检查与现有 41 项 Swift、5 项 Rust 后台测试通过；独立源码复核未发现可确认的 P1/P2。开发应用约 5.6 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`d6992cccbd682b3283aaa14822774fc6407ff4b6030b915abcd961ed95c2cdcd`。源码与限制见[后台证据](evidence/2026-10-21-build15-tree-insets.json)。现有测试没有覆盖 AppKit 滚动槽/行绘制或 clip 通知；本轮没有启动、退出或重启应用，没有操作桌面或进行分发签名，实际窗口边缘与滚动仍未验收。

2026-10-21 build 16 去掉 legacy 滚动条系统底板及树交叉角绘制，普通文件名测量改为后台单工作器，图标按符号复用并跳过重复展开恢复。Release 静默打包、格式/静态/头文件检查、45 项 Swift 和 5 项 Rust 后台测试通过，包含新增 4 项 CoreText 测试；独立源码复核未发现可确认的 P1/P2。开发应用约 5.6 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`9b9b307c09e893f7bb4e108fe382d36aa7accc10e34de6cdf731d8b4ab702f60`。临时样本分阶段读取和文字准备数据、源码哈希与验证边界见[后台证据](evidence/2026-10-21-build16-scroll-expand.json)。没有启动、退出或重启应用，没有操作桌面或进行分发签名；实际透明滚动条、文本排版等价和首次展开到呈现延迟仍未验收。

2026-10-21 build 17 移除根名称后的磁盘路径，目录/文件增加完整路径提示及原生右键菜单，交叉角残留增加同色覆盖处理。Release 静默打包、格式/静态/头文件检查、47 项 Swift 与 5 项 Rust 后台测试通过；独立复核发现的 URL 隐式元数据查询已改为显式目录类型，复核未发现剩余可确认的 P1/P2。开发应用约 5.7 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`2eebe4a9fd483b976eb446872b6e8fd2ca325f557bd4a2f52a99f39ad23cd7e1`。源码与限制见[后台证据](evidence/2026-10-21-build17-tree-menu.json)。没有启动或重启应用，没有执行剪贴板、访达或其他桌面操作，没有进行分发签名；路径提示、右键命中及菜单动作、交叉角像素效果仍未窗口验收。

2026-10-21 build 18 按新截图移除交叉角覆盖方案，项目树改用原生内容滚动加独立双槽；启动默认恢复上次打开项目，包含旧记录迁移和显式关闭语义。Release 静默打包、格式/静态/头文件检查、54 项 Swift 与 5 项 Rust 后台测试通过，含新增 4 项恢复模型与 3 项滚动偏移测试。独立源码复核未发现剩余可确认的 P1/P2；外层滚轮反向转发已移除，避免原生事件回退重入。开发应用约 5.7 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14。可执行文件 SHA-256：`d75e4f0cb955c1f3a7e7e47e68a51bea226bb50852295d7a59cec016e900a035`。源码和验证边界见[后台证据](evidence/2026-10-21-build18-startup-scroll.json)。没有启动或重启应用，没有执行用户偏好读写测试、桌面操作或分发签名；真实重启、权限恢复、滚轮/拖动/键盘/无障碍同步及交叉角像素效果仍未窗口验收。

2026-10-21 build 19 为用户授权的提交前整理：项目树拆分协调器、视口及行/cell 绘制，移除冗余 tracking 存储，交互保持 build 18。拆分前重构源码与 build 18 记录哈希完全一致，独立只读复核未发现可确认的 P1/P2。54 项 Swift、5 项 Rust 测试和全部静态/格式/头文件检查通过；从暂存树导出的干净副本也通过完整检查和 Release 构建。11 项 crate 与 Rust 标准库通知同本地上游原文逐字节一致。开发包约 5.7 MiB、arm64、版本 0.1.0，最低系统声明 macOS 14，可执行文件 SHA-256：`55e8801cd1bb25dc6e7448349eedc98424824f66c69351527055bdc7d7c42f3d`。源码和干净副本结果见[提交前证据](evidence/2026-10-21-build19-source-baseline.json)。本轮未启动应用、操作桌面或进行分发签名；源码提交推送与应用发布分开，原窗口及性能验证缺口继续保留。

2026-10-22 build 31 按用户截图补全 Dart 导入 URI 的整段悬浮与链接：SDK 返回 library/Declared 分节，确认定义后画下划线并复用导航缓存；路径中的标点不再拆分请求。有界扫描覆盖普通多行/条件导入、注释与截断上下文，不解析磁盘或伪造未解析包的跳转。编辑菜单按内容测量收窄，分区改用可见主题细线，参数信息归入导航组。165 项 Swift、15 项 Rust 全量静默检查及 Dart 3.11.5 自建 package/SDK/相对 import 和注释边界探针通过；独立复核的三处注释识别问题已修复并复核。Release 开发包约 139.9 MiB、arm64、0.1.0 / build 31、最低系统声明 macOS 14；可执行文件 SHA-256：`a4668ee78dc6008c2e022e5d188da4534422e25ad3ccfdbfcedf0306aceafe90`。源码、检查和限制见[本轮证据](evidence/2026-10-22-build31-import-menu.json)、[Dart 工具](DART_FLUTTER.md)与[编辑菜单](EDITING.md)。没有启动或安装应用、执行 GUI/剪贴板操作、分发签名或提交推送；真实卡片/下划线/菜单效果与渲染性能未验收。

2026-10-23 build 32 根据用户已提供的 2× WebStorm Islands 截图采样，统一 43 pt 头部、1 pt 左右壳体留白、5 pt 分隔、40 pt 面板标题/工具步进和 36 pt 状态栏；校齐项目树顶部/左右留白、标签/标题字体、原生编辑文本/行号/最小行高。原生系统按钮保留大小与动作，嵌套宿主不额外施加 safe-area，工具拖放标记与可见按钮共用轨道几何。169 Swift / 15 Rust 全量静默检查通过，4 项新增样式/轨道/按钮/最小尺寸回归，27 项相关布局/交互/预览用例通过，独立只读复核未发现确认 P1/P2。Release 开发包约 139.9 MiB、arm64、0.1.0 / build 32、最低系统声明 macOS 14；可执行文件 SHA-256：`6abe22c80755694039a96b87ff0039dbc94631fd3d6f1eaa4a6440bf99cb416e`。目标、推导和未验证项见[视觉说明](VISUAL_ALIGNMENT.md)与[后台记录](evidence/2026-10-23-build32-visual-alignment.json)。没有启动或操作应用/桌面，没有窗口逐像素差分、真实输入或帧率验收；未提交推送或发布。

## build 37：Markdown / HTML 分屏

在原生文本标签内增加源码、左右分屏、仅预览和联动/刷新入口；默认左右，可拖动并记忆比例。静态页面和后台渲染边界见[专题](MARKUP_PREVIEW.md)。本阶段不代表 Swift、SQL、Java 目标完成，参见[完整计划](LANGUAGE_EXPANSION_PLAN.md)。没有启动应用或执行 GUI 验收。

## build 38：Swift / Java / SQL

接入外部 SourceKit-LSP/JDT LS 与内置离线 SQL：高亮、诊断/统一问题面板、补全/说明/导航/结构与格式化；Swift/Java 文本动作沿用修改预览。SwiftPM、Xcode/BSP 及 Maven/Gradle 项目模型的信任、生命周期、SQL DDL 绑定、资源上限与验证限制见[原生语言](NATIVE_LANGUAGES.md)。真实工程、窗口和性能仍分别验收，不以语言服务接通宣称完整 IDEA 功能。

本批全量 217 Swift / 25 Rust / 4 Node、9 项原生语言 Swift ASan、SourceKit SwiftPM/BSP 与 JDT 独立文件/Maven 生成样本检查通过。Release 开发包约 174.9 MiB，arm64、0.1.0 / build 38，未启动或安装；可执行文件 SHA-256 `328e5420896438c523ede9f1b864f4d8bfad98b6cf9628c0d5cfdbcc25b5ebe2`。范围与未验证项见[证据](evidence/2026-10-23-build38-native-languages.json)，未提交推送或发布。

## build 39：Markdown / HTML 预览初始化修复

根据用户窗口的 WKErrorDomain 6，确认原离线规则含 WebKit 不支持的正则分支；改为五条协议前缀并保留失败关闭行为。Foundation 编译器 CLI 在自有临时目录复现旧错误并确认生产规则可编译，未实例化 WebView 或创建应用宿主。7 项预览与全量 218 Swift / 25 Rust / 4 Node 通过，Release 本地包 build 39 未启动；真实窗口恢复未自动测试。说明与哈希见[预览专题](MARKUP_PREVIEW.md)和[修复证据](evidence/2026-10-23-build39-markup-rules.json)。

## build 40：大文件工具条

用户确认经常处理超过 1 GB 的文本；采用 Rust 磁盘 piece table、原生有界页、独占跨页历史和后台整文件查找/完整原子保存。所有扩展名共享大小/长行路由，局部页不得用于全文 LSP 修改。范围、资源预算、真实 GB 后台样本与连续滚动/全局行号/窗口性能缺口见[大文件专题](LARGE_FILES.md)和[ADR 0013](adr/0013-disk-backed-text.md)。
