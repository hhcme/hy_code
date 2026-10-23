# 基础文本浏览与编辑

更新：2026-10-23，build 34。用户已明确进入文件浏览与编辑阶段；文件列表单击即可编辑，自动保存作为可关闭设置。以下是代码实现和后台证据范围，原生窗口、输入法与键鼠尚未执行验收。

build 34 的图片文件进入[独立只读预览](IMAGE_PREVIEW.md)，不尝试文本解码，不参与自动保存/撤销/语言修改；以下文本规则继续适用于文本编辑。

## 使用行为

- 文件列表单击：后台读取完整文本，中央原生编辑区打开临时标签；首次修改立即固定标签。目录仍只在树内浏览。
- 自动保存默认开启，停止输入约 800 ms 后保存到原文件。输入法组合态暂停；开关位于 HyCode 的设置窗口，也可从顶部齿轮的“编辑设置…”进入，选择持久化。
- 关闭自动保存后使用 ⌘S；⌥⌘S 保存所有已修改文件。标签圆点与状态栏显示未保存、等待保存、正在保存、已保存或失败。
- 关闭标签、关闭项目、切换项目、关闭窗口和退出，共用保存/丢弃/取消保护；保存失败不清空缓冲。重新载入也先保护未保存内容。
- 保存前发现外部修改时停止覆盖，保留当前编辑；用户可继续保留内容，或明确丢弃并重新载入。没有强制覆盖或自动冲突合并。

当前支持有效 UTF-8、UTF-8 BOM、带 BOM 的 UTF-16 LE/BE；原有 BOM 和换行保留，普通 Return 沿原文件换行风格插入。粘贴保留输入片段本身的内容，可能形成混合换行；不是全文件自动转换。读取及编码后保存均限制为 8 MiB，超限、无效编码、二进制、特殊文件和硬链接拒绝编辑，不使用截断或有损解码保存。

编辑视图使用原生等宽文本、软换行、选择与原生撤销；每个打开文件保留自己的编辑视图、选择、滚动和 UndoManager。当前已接入行号及后台 Tree-sitter 基础高亮，见[高亮说明](SYNTAX.md)；Dart SDK LSP 和 Pub 首批工具见 [Dart/Flutter 工具](DART_FLUTTER.md)，Web 文本重构和修改预览见 [Web 工具](WEB_TOOLS.md)。尚无多光标、正式项目搜索与崩溃恢复草稿；[分析文件监听](PROJECT_ANALYSIS.md)不自动重载原生缓冲。支持范围不代表大文件性能或所有编码已验收。

## 编辑反馈与右键菜单

build 30 的原生文本区显式接收点击焦点，空白区域也注册 I-beam 指针；⌘点击/中键导航与确认定义后的手形继续保留。插入点使用独立的深浅主题高对比色，并在当前外观中解析；原生绘制回调将细插入点扩至像素对齐的 2 pt，同时扩大原生闪烁的失效区域，避免扩大部分被裁剪或残留。仍由 AppKit 管理插入点的出现与闪烁，不创建全局光标或额外常驻刷新计时器。窗口失焦/编辑器离焦时切为非活动选区，清除当前行色带；活动编辑器在无选区时用轻微色带指示当前视觉行，只查询该处原生布局，不扫描全文。

编辑区右键、Control 点击、Shift-F10 与无障碍“显示菜单”使用工作台纯色圆角菜单：统一颜色、字体、图标、快捷键列、分隔、悬停/按下反馈。保留撤销/重做、剪切/复制/纯文本粘贴、全选，以及已支持语言的定义/引用、格式化；Web 再提供类型/实现、重命名、修复/重构、整理导入与参数入口。只读/冻结/组合态禁用写操作，执行编辑命令前再次核对可编辑状态；构造菜单不读取系统剪贴板。build 33 将项目树、标签、工具停靠、设备/作用域菜单以及补全/代码动作统一到同一工作台菜单。参数信息使用可换行和滚动的说明面板；系统菜单栏仍采用 macOS 原生实现。

build 31 将编辑菜单按实际标题和快捷键测量宽度，最小宽度 220 pt，较长标题可扩至 360 pt，并受当前屏幕边界限制。分区使用与底色区分的细线，编辑历史、剪贴板/选择、导航、重构/导入和格式化各组留出间隔；只展示已有功能。

菜单以不取得 key 的子面板展示，文本编辑器继续拥有输入法与 first responder。方向键、Tab/Shift-Tab、Home/End、Enter 和 Escape 用于选择/执行/关闭；其他输入先关闭菜单，再交回原有接收者继续处理。键盘选择跳过禁用项与分隔，较短屏幕下可滚动到所选项；菜单按鼠标所在屏幕避开四边。外部点击不被吞掉；滚动、窗口失焦/移动/缩放、编辑器分离或离焦时移除菜单和仅在展开期间存在的本地事件监听。

这些是实现与后台模型断言。没有运行真实光标闪烁、面板点击、VoiceOver、输入法或窗口测试，不能据编译和颜色/几何测试宣称真实视觉、输入与帧率已验收。

## 所有权与数据流

决策见 [ADR 0003](adr/0003-text-editing.md)。Rust TextDocument 是正式文本与修订的单一所有者，不维护第二份撤销历史；macOS 的每文档 UndoManager 是当前唯一撤销历史。TextKit 的 NSTextStorage 是输入法/布局投影，通过 replaceCharacters 原语取得精确 UTF-16 增量，避免每次输入复制/比较全文。

EditorDocument 在 MainActor 即时记录编辑代次并固定标签，将增量按前序任务链送到 NativeTextDocument actor。Rust 检查修订和 Unicode 标量边界；不匹配时保留编辑区并停用继续写入，避免错误偏移保存。它不是 Rope、大规模事务服务或已经测量的低延迟引擎。

保存排在同一任务链中，只确认本次保存对应的修订。保存期间有更新输入时，旧保存完成不清除新修订的脏标记。计时器、手动保存和自动保存设置共用同一文档，数据编码、读取、比较、文件协调与写入均在非 UI actor。

输入法的 setMarkedText、unmarkText、insertText 及 textDidChange 都回报实时组合状态。开始关闭时先暂停自动保存、取消未提交的自动写入、结束组合态并冻结完整文档集合，排空在途操作后再决定提示；关闭期间阻止新文件、外部保存入口与历史导航。提示中的保存使用专门路径；结束前复查全部候选文档，取消或失败后恢复输入。取消不能撤销已经到达 rename 提交点的保存，因此关闭会等待其结束，不能让旧写入晚于丢弃/重开。

## 文件保存边界

授权生命周期沿用 WorkspaceAccess，文档任务保活到所有读取/保存返回。平台文件层通过目录描述符和逐级 openat/no-follow 锚定用户项目内的相对路径；只处理普通且单硬链接文件。写前除模式位保护外，还无截断地打开写描述符，由内核验证当前用户权限与 ACL；不因其他用户具有写位而授予写入。

NSFileCoordinator 协调替换，并持有原件 advisory lock。保存比较磁盘身份/版本及完整原字节；临时文件位于同目录，写入、复制权限/ACL/xattr、更新修改时间、同步数据后，再核对描述符和路径版本并 renameat 原子落位。失败清理临时文件，原件与编辑缓冲保留。提交后使用仍持有的描述符记录新基线，不因目标随后移动而把已提交数据报告成未保存。

版本检查与 rename 之间仍有不可完全消除的非协作外部写入竞态；文件协调和 advisory lock 只能约束参与者，不是对抗恶意并发重命名的文件系统沙箱。没有宣称断电持久性、网络文件系统全部行为或所有 ACL/扩展属性组合已通过；当前测试使用本机临时文件。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| [document.rs](../crates/hycode-core/src/document.rs) | 有界文本、编码/BOM、UTF-16 增量与修订检查 |
| [document_ffi.rs](../crates/hycode-core/src/document_ffi.rs)、[C 头文件](../bindings/CHyCodeCore/include/hycode_core.h) | 独占文档句柄、结果/错误缓冲和释放契约 |
| [NativeTextDocument.swift](../packages/HyCodeWorkspace/Sources/NativeTextDocument.swift) | 单个后台 actor 拥有 Rust 文档及磁盘基线 |
| [TextFileIO.swift](../packages/HyCodeWorkspace/Sources/TextFileIO.swift)、[DocumentSaveCancellation.swift](../packages/HyCodeWorkspace/Sources/DocumentSaveCancellation.swift) | 受限文件读写、权限/冲突、元数据与提交前协作取消 |
| [DocumentEditState.swift](../packages/HyCodeWorkspace/Sources/DocumentEditState.swift) | 已编辑/已保存修订确认 |
| [EditorDocument.swift](../app/macos/Sources/Editor/EditorDocument.swift) | UI 投影的任务顺序、自动保存、错误和关闭排空 |
| [NativeTextEditor.swift](../app/macos/Sources/Editor/NativeTextEditor.swift) | TextKit 原语增量、原生输入、撤销、组合态与视图保留 |
| [CodeTextView.swift](../app/macos/Sources/Editor/CodeTextView.swift) | 插入点/当前行、焦点、指针、语义导航与组合输入适配 |
| [EditorContextCommands.swift](../app/macos/Sources/Editor/EditorContextCommands.swift)、[WorkbenchContextMenu.swift](../app/macos/Sources/Workbench/WorkbenchContextMenu.swift) | 编辑菜单动作与工作台主题弹层、键盘和事件生命周期 |
| [EditorFeedback.swift](../packages/HyCodeWorkspace/Sources/EditorFeedback.swift)、[ContextMenuInteraction.swift](../packages/HyCodeWorkspace/Sources/ContextMenuInteraction.swift) | 颜色/局部重绘与菜单选择/定位模型 |
| [EditorWorkspace.swift](../app/macos/Sources/Editor/EditorWorkspace.swift)、[EditorCloseGuard.swift](../app/macos/Sources/Editor/EditorCloseGuard.swift) | 打开文档、关闭/退出保护、窗口代理转发 |
| [EditorPanel.swift](../app/macos/Sources/Editor/EditorPanel.swift) | 中央编辑区、失败重试/重载与设置开关 |
| [TextDocumentTests.swift](../packages/HyCodeWorkspace/Tests/TextDocumentTests.swift) | 无 GUI 的桥接、文件保存与失败验证 |

## 验证

沿用[静默开发规则](DEVELOPMENT.md)。测试仅触及生成的临时文件，不打开用户项目、不访问真实偏好或系统剪贴板；ACL 测试只对自己的临时文件运行 chmod，不启动图形程序。格式、Clippy、C/C++ 头文件、Rust 单元测试、Swift 命令行测试与本地开发包构建分别记录在[工作台](WORKBENCH.md)。

真实点击、窗口/退出提示、设置窗口、IME、Undo/Redo、原生滚动、焦点、布局和端到端自动保存仍待真实窗口验收；后台测试不代替这些断言。

build 30 的开发包、源码哈希和静默检查记录见[编辑反馈证据](evidence/2026-10-22-build30-editor-feedback.json)。插入点与失效接口依据 Apple 的 [drawInsertionPoint](https://developer.apple.com/documentation/appkit/nstextview/drawinsertionpoint(in:color:turnedon:)) 和 [setNeedsDisplay](https://developer.apple.com/documentation/appkit/nstextview/setneedsdisplay(_:avoidadditionallayout:))；后台纯模型断言不能代替系统绘制回调的窗口验收。

build 31 的 import 引用与菜单宽度/可见分区记录见[本轮证据](evidence/2026-10-22-build31-import-menu.json)；新增 8 项回归后全量 165 Swift / 15 Rust 静默检查通过，Dart SDK 临时样本协议探针通过。原生菜单宽度与分隔线、鼠标指针、链接下划线仍未执行真实窗口验收。

build 32 采用 14 pt 系统等宽字、最小 22 pt 行高、10 × 8 pt 文本内边距和 12 pt 行号。段落样式仅初始化显示投影和输入属性，不改变文本字符、Rust 修订或撤销所有权；不设置最大行高，保留系统 fallback 字形需要的空间。完整对齐与限制见[视觉说明](VISUAL_ALIGNMENT.md)。


build 33 的整体样式覆盖见[视觉对齐清单](VISUAL_ALIGNMENT.md)。设置窗口跟随用户选择的工作台深浅主题；重命名与未保存确认改为工作台样式 sheet，保留原有修订/保存保护，提交响应后立即禁用操作并只完成一次。无可用窗口时关闭保护保守取消，不弹出独立模态框。未执行真实焦点、输入法、sheet 或辅助功能验收。
