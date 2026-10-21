# HyCode 定名与重写重置记录

日期：2026-10-21。用户确认：“可以叫 HyCode，把那边的文档记录都改好吧，实现都清理掉就好了，因为要重写”。本轮据此完成更名、文档整理和旧实现清理，没有开始新的功能开发。

下列重置记录描述清理时的状态；同日后续已明确 macOS 首版并建立开源文档基线，见文末。历史数字和当时验证不作为新应用验收。

## 名称与目录

- 正式产品名称：HyCode。
- 原目录名：`hc_file_viewer`。
- 当前目录名：`hy_code`；公开克隆不要求固定机器路径。
- 保留原 `.git` 和提交历史；原分支不变，未创建提交、标签、远程仓库或执行推送。现有本地工具配置 `.v2c` 保留，不是应用实现或构建产物。

## 删除范围

旧实现基线提交：`97588e1336931ba92af6c15f091826327d46ee58`。以下 **17 个已跟踪文件**从工作区删除，仍可通过该提交或历史读取：

- `App/HcFileViewer.xcodeproj/project.pbxproj`
- `App/HcFileViewer.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `App/HcFileViewer.xcodeproj/xcshareddata/xcschemes/HcFileViewer.xcscheme`
- `App/HcFileViewer/ArchiveView.swift`
- `App/HcFileViewer/HcFileViewerApp.swift`
- `App/HcFileViewer/HomeView.swift`
- `App/HcFileViewer/Info.plist`
- `App/project.yml`
- `core/Cargo.lock`
- `core/Cargo.toml`
- `core/src/lib.rs`
- `core/uniffi-bindgen.rs`
- `packages/HcCoreSwift/Package.swift`
- `packages/HcCoreSwift/Sources/HcLibrary/LibraryStore.swift`
- `packages/HcCoreSwift/Tests/HcCoreTests/Fixtures/sample.zip`
- `packages/HcCoreSwift/Tests/HcCoreTests/HcCoreTests.swift`
- `scripts/build-core.sh`

同时清理上述目录内的 Rust `target`、SwiftPM `.build`、生成 Swift 绑定/头文件、xcframework 和旧测试样本。四个目录合计清理 5877 个文件，文件长度合计 1,355,751,050 字节；该数字不是磁盘实际释放空间测量。没有删除用户文档、应用数据、HyHub 源码或其固定包。

## 保留与重写

清理前的 README 和全部 9 份专题文档（含此前未提交的调研）完整归档到[历史区](history/2026-10-21-file-viewer/INDEX.md)，加入历史提示；原文本和归档摘要见该目录的 `manifest.json`。根 README、开发入口及当前专题全部以 HyCode 的原生开源编辑器方向重新整理，废止“当前已有 ZIP 骨架”等完成度描述和旧构建命令。

重置完成时没有应用源代码、依赖清单、锁文件、应用工程、测试或构建入口；没有功能、构建或运行验证通过的声明。语言服务调研保留来源与当时状态，不视为已选型。当时根许可证、贡献约定、公开仓库、工程名与发布身份尚待确定，后续许可和仓库进展见文末。

## 重置阶段记录的验证与限制

当时记录：12 份当前 Markdown 与 11 份历史 Markdown 的 79 个本地文件链接检查通过；10 份原始文档及对应归档文本 SHA-256 一致，17 个旧源码/配置/测试删除项均可从原 Git 提交读取，未发现残留源码或构建产物。`git diff --check` 通过，原 Git HEAD 与索引保留，HyHub 与固定包未动。该阶段未运行旧构建、未启动/停止应用、未打包、发布、提交或推送；这些描述只对应重置阶段。

独立只读复核已收尾，无剩余确定 P1/P2；前期语言服务调研的时态与零实现基线已澄清，macOS 仅 Apple Silicon 的既有范围已在当前文档中一致保留。

下一步依[实施路线](ROADMAP.md)建立新文档会话与原生编辑器原型；不自动恢复旧工程。

## 同日后续：公开文档基线

用户进一步明确首版只做 macOS，Swift 原生界面 + Rust 内核，以高性能和完全开源为要求，并允许复用合适的开源组件。随后指定公开仓库 [hhcme/hy_code](https://github.com/hhcme/hy_code)，授权整理文档、提交并推送。

本次采用根 MIT 许可，补充贡献与安全说明、文档索引、ADR 0001、性能和依赖台账、Issue/PR 模板及真实文档检查工具。当前方向与路线统一为 macOS / Apple Silicon；SwiftUI/AppKit、缓冲所有权、桥接工具和具体依赖仍为待原型事项。移除当前文档中的固定机器路径和私有仓库代码地图，历史快照及 manifest 原文保持不变。

本地 `python3 scripts/check_docs.py` 通过：33 份 Markdown、145 个本地链接、10 组原文/归档 SHA-256；`git diff --check` 通过。检查脚本完成 Python 语法检查，工作流 YAML 解析通过。远程使用 `Documentation` 工作流检查文档，提交、远程同步及 CI 实际结果以 Git/GitHub 记录为准。本次没有新增应用工程、启动应用、签名打包或发布应用版本。

## 同日后续：基础文件浏览工作台

用户要求先实现 IDEA 风格基础交互和布局，能够浏览文件列表，暂不接入分析器。由此新建 SwiftPM macOS 工程、Rust 只读目录内核和 C ABI，提供原生项目树、目录表格、临时/固定标签、面包屑、历史导航、文件信息、隐藏开关、刷新和取消。

本轮在后台完成构建和 Rust/Swift 测试，没有恢复旧 ZIP 应用，没有启动 GUI 或操作用户桌面。窗口、视觉、性能与应用分发继续标为未验证。当前入口、源码地图和证据见[工作台说明](WORKBENCH.md)，工程决策见 [ADR 0002](adr/0002-file-workbench.md)。本地源码改动与远程提交状态以 Git 为准，不沿用上一轮文档推送记录。

## 同日后续：目录读取与工作台精简（build 8）

按用户最新截图移除中央目录表格与目录标签；目录只在项目树选择/展开，文件标签保持独立。项目切换改为打开/最近项目分组、徽标与名称/路径双行，最多持久化 30 条 HyCode 自己的历史与可选访问书签。应用所属纵向滚动条采用透明轨道、细滑块和固定占位。

目录读取改为两工作器共享 FIFO 有界并发，树按变化分支更新，刷新后补齐已展开分支的请求；节点回收沿父子索引执行，避免重复全表过滤。独立只读复核发现的展开漏读与平方级删除路径已经修复并复核。小型临时样本探针及限制见[性能记录](PERFORMANCE.md)，不作为用户目录或真实窗口速度证明。当前打包与检查证据见[工作台说明](WORKBENCH.md)，没有启动应用或操作用户桌面。

## 同日后续：源码整理与提交（build 19）

用户认可 build 18 的工作台进展，并明确授权整理后提交推送。本次整理保持现有交互：项目树协调器、视口/列宽适配、行/cell 绘制、滚动容器和右键菜单分别成文件；Swift 可测试状态模型、C ABI 和 Rust 目录内核仍保持独立。构建缓存、开发应用和临时复核资料不纳入源码提交。

同时对齐当前构建号、源码地图、依赖及验证记录；第三方通知与 11 个锁定 crate、官方 Rust 工具链许可逐字节核对。仅执行静默验证，用户的积极反馈不替代全部窗口、性能或正式分发验收。提交与远程同步以 Git 为准，不将源码推送称为应用发布。
