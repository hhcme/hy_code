> 历史快照：2026-10-21 更名前的文件浏览器文档。正式名称现为 HyCode，旧实现已按用户要求删除，本文的代码路径、命令、能力与旧产品约束只说明当时状态。当前开发以 [HyCode README](../../../../README.md) 为入口。

# HyHub 能力复用与独立项目边界

> **2026-10-21 编辑器方向更新**：最新定位改为轻量、原生、完全开源的代码编辑器，借鉴 IDEA 界面组织。先读 [新方向与优先级](EDITOR_DIRECTION.md)；本文旧文件浏览器主线、强制复制入库、付费解锁及商店优先规则遇冲突时仅作历史记录。候选能力和骨架实现状态仍需分别看待。

更新日期：2026-10-21。用户已把万能文件浏览编辑器方向放到本项目独立推进。本页仅建立迁移参考，不表示源码已搬入或依赖已接入。

## 1. 参考基线

本机参考仓库：`/Volumes/hhcStorage/hhc_project/hy_hub`；可追溯基线为 `v0.5.42`，源码提交 `712e9e15e1f3fb69c7337a14315ecb9ba3bc50fd`。以下路径相对此参考仓库，不是 hc_file_viewer 内已存在的模块。

HyHub 维护自己的应用、版本、文件权限和远端会话。本项目独立构建、运行、文件库、版本与发布，不读取其用户数据、不绑定其账号/NAS、不依赖它安装或运行，也不因文档更新移除 HyHub 现有功能。

## 2. 可参考的能力与入口

| 能力 | HyHub 入口 | 本项目迁移重点 |
| --- | --- | --- |
| 流式归档、列目录、创建/解压 | `core/file-core/src/archive.rs`、`archive_sources.rs`、`archive_disk.rs` | 引擎/许可、64 位数据、输出事务与取消；从进程协议转换成适合本仓的接口 |
| 文本完整读取、编码、安全保存 | `core/file-core/src/editing.rs` | 版本复核、编码往返和元数据；保存对象改为本仓库内副本 |
| 高亮与 Markdown 渲染 | `core/file-core/src/syntax.rs` | syntect/渲染规则可参考；当前着色预算是 HyHub 工作预算，不是本项目既定上限 |
| Git 只读状态/差异 | `core/file-core/src/repository.rs` | 先明确项目与仓库所有权，不把独立导入副本当作原仓库 |
| 文件任务与预览会话 | `app/mac/Sources/HyHub/Core/Files/` | 后台队列、请求代次、取消、缓存与宿主切换；拆除应用/设备耦合 |
| 首页、网格/列表、预览侧栏、标签工作台 | `app/mac/Sources/HyHub/Features/Files/` | 状态保留及交互模型可复用，UI 各端原生重做 |
| 原生编辑、行号、分栏预览 | `app/mac/Sources/HyHub/Features/Files/FileTextEditor.swift` | TextKit 仅 Apple；其他端编辑控件、IME、撤销与光标单独适配 |
| 编辑、最近和工作台模型 | `app/mac/Sources/HyHub/Model/FileEditSession.swift`、`FileRecentHistory.swift`、`FileWorkspaceModel.swift` | 与本仓 DocumentSession、文件库和保存事务整合，不复制两套来源 |
| 大 PDF/图像后台预览 | `app/mac/Sources/HyHub/Features/Files/FilePDFPreview.swift`，以及 `app/mac/Sources/HyHub/Core/Files/` 下的 `FilePDFSource.swift`、`FilePreviewWork.swift` | Apple 框架和生命周期专属，其他端选择各自引擎/适配器 |

架构与兼容记录还可参考 HyHub 的 `docs/文件浏览与通用预览.md`、`docs/macOS系统压缩与解压.md`。历史验证只能用于理解风险和挑选样本，不能直接算成本仓通过。

## 3. 不能直接复制的假设

- **文件所有权不同**：HyHub 已有本地路径编辑/远端缓存等语义，本仓已明确默认复制入库，不能把所有来源直接作为原文件可写路径。
- **平台范围不同**：AppKit、TextKit、Quick Look、PDF/ImageIO、Finder 服务等是 Apple 适配层，不会随 Rust 核心自动覆盖 Windows/移动端。
- **权限和渠道不同**：HyHub 公证直发包不等于本仓 Mac App Store 沙盒/iOS 宿主；文件授权、引擎装载、帮助进程与 SDK 访问重新验证。
- **进程模型不同**：HyHub 文件核心使用 worker 请求；本仓已有 UniFFI。抽出平台无关逻辑，不让 Swift 为复用而重复绕一套无必要的协议。LSP 又是独立的长生命周期服务，需单独设计。
- **数据与产品不同**：HyHub 的账号、设备浏览、云盘和远控拖文件不是本仓默认需求；未来互通通过窄接口单独设计。
- **源码与许可不同**：迁入前核对相关源码、依赖、许可证、通知与发布约束，不从包里提取二进制或私人数据代替源码迁移。

## 4. 建议迁移步骤

1. 先稳定本仓文件访问、文档会话、任务/取消、错误与保存目标契约。
2. 一次迁入一个有实际场景的能力，保持既有 ZIP 骨架可回归；不整体复制 HyHub 应用目录。
3. 引擎逻辑、平台适配和 UI 分开，清理旧应用配置、路径、账号和远端依赖。
4. 迁移可分发的样本/生成方法与有意义用例，重做本仓核心、绑定、宿主和大文件验证。
5. 更新[格式台账](FORMAT_SUPPORT.md)、依赖许可和各端状态，再扩下一项。

此时未实施迁移，HyHub 源码和固定包保持原状。本项目亦未承接 HyHub 的 LSP 成果，因为其基线没有补全与引用服务实现。
