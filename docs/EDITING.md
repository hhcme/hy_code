# 基础文本浏览与编辑

更新：2026-10-21，build 20。用户已明确进入文件浏览与编辑阶段；文件列表单击即可编辑，自动保存作为可关闭设置。以下是代码实现和后台证据范围，原生窗口、输入法与键鼠尚未执行验收。

## 使用行为

- 文件列表单击：后台读取完整文本，中央原生编辑区打开临时标签；首次修改立即固定标签。目录仍只在树内浏览。
- 自动保存默认开启，停止输入约 800 ms 后保存到原文件。输入法组合态暂停；开关位于 HyCode 的设置窗口，也可从顶部齿轮的“编辑设置…”进入，选择持久化。
- 关闭自动保存后使用 ⌘S；⌥⌘S 保存所有已修改文件。标签圆点与状态栏显示未保存、等待保存、正在保存、已保存或失败。
- 关闭标签、关闭项目、切换项目、关闭窗口和退出，共用保存/丢弃/取消保护；保存失败不清空缓冲。重新载入也先保护未保存内容。
- 保存前发现外部修改时停止覆盖，保留当前编辑；用户可继续保留内容，或明确丢弃并重新载入。没有强制覆盖或自动冲突合并。

当前支持有效 UTF-8、UTF-8 BOM、带 BOM 的 UTF-16 LE/BE；原有 BOM 和换行保留，普通 Return 沿原文件换行风格插入。粘贴保留输入片段本身的内容，可能形成混合换行；不是全文件自动转换。读取及编码后保存均限制为 8 MiB，超限、无效编码、二进制、特殊文件和硬链接拒绝编辑，不使用截断或有损解码保存。

编辑视图使用原生等宽文本、软换行、选择与原生撤销；每个打开文件保留自己的编辑视图、选择、滚动和 UndoManager。当前没有语法高亮、行号栏、多光标、正式项目搜索、解析器或 LSP，也没有崩溃恢复草稿与文件监听。支持范围不代表大文件性能或所有编码已验收。

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
| [EditorWorkspace.swift](../app/macos/Sources/Editor/EditorWorkspace.swift)、[EditorCloseGuard.swift](../app/macos/Sources/Editor/EditorCloseGuard.swift) | 打开文档、关闭/退出保护、窗口代理转发 |
| [EditorPanel.swift](../app/macos/Sources/Editor/EditorPanel.swift) | 中央编辑区、失败重试/重载与设置开关 |
| [TextDocumentTests.swift](../packages/HyCodeWorkspace/Tests/TextDocumentTests.swift) | 无 GUI 的桥接、文件保存与失败验证 |

## 验证

沿用[静默开发规则](DEVELOPMENT.md)。测试仅触及生成的临时文件，不打开用户项目、不访问真实偏好或系统剪贴板；ACL 测试只对自己的临时文件运行 chmod，不启动图形程序。格式、Clippy、C/C++ 头文件、Rust 单元测试、Swift 命令行测试与本地开发包构建分别记录在[工作台](WORKBENCH.md)。

真实点击、窗口/退出提示、设置窗口、IME、Undo/Redo、原生滚动、焦点、布局和端到端自动保存仍待真实窗口验收；后台测试不代替这些断言。
