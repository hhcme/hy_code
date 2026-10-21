> 历史快照：2026-10-21 更名前的文件浏览器文档。正式名称现为 HyCode，旧实现已按用户要求删除，本文的代码路径、命令、能力与旧产品约束只说明当时状态。当前开发以 [HyCode README](../../../README.md) 为入口。

# 原生开源代码编辑器（名称待定）

目标是做一个轻量、原生、可扩展的开源代码编辑器：追求 VSCode 式轻量体验，借鉴 IDEA 的界面组织，使用各平台原生界面 + Rust 共享核心。代码编辑与项目工作区成为主线，通用文件预览、归档及整理作为配套能力。

**2026-10-21 最新方向优先**：先阅读 [编辑器方向、开源边界与实施顺序](docs/EDITOR_DIRECTION.md)。正式名称讨论中，推荐 HyCode，备选 AvenCode / NivoCode；暂不更改 `hc_file_viewer` 目录、target、包名和数据位置。现有实现仍仅是 macOS + Rust 的 ZIP 目录浏览骨架，未实现 IDE 功能，也尚未完成开源许可证与公开仓库的准备。

## 文档入口

| 文档 | 内容 |
| --- | --- |
| [最新编辑器方向](docs/EDITOR_DIRECTION.md) | 当前定位、IDEA 式布局、轻量路线、工作区、完全开源及命名状态 |
| [产品需求与格式范围](docs/PRODUCT_REQUIREMENTS.md) | 定位、格式范围、文件所有权、预览与编辑交互 |
| [技术设计与现有骨架](docs/TECH_DESIGN.md) | 当前源码、全端分层、平台适配、FFI 与后台任务 |
| [格式能力台账](docs/FORMAT_SUPPORT.md) | 当前实现与候选能力、逐平台兼容性记录 |
| [代码编辑与语言服务](docs/CODE_INTELLIGENCE.md) | 高亮、补全、引用跳转及现成服务清单 |
| [分阶段实施](docs/ROADMAP.md) | 骨架、通用浏览编辑、代码智能和全端适配的推进顺序 |
| [HyHub 能力复用](docs/HYHUB_REUSE.md) | 参考源码、迁移差异与项目独立性 |
| [开发约定](docs/DEVELOPMENT.md) | 后台验证、样本与平台交付证据 |
| [技术、离线与分发可行性](docs/FEASIBILITY_AND_DISTRIBUTION.md) | 当前分发边界及历史 Apple 专项研究 |

开始设计或开发前，先阅读最新编辑器方向，再阅读产品需求、技术设计和开发约定，再阅读任务对应专题。文档区分已明确方向、工程建议、当前实现和待验证能力。

## 此前文件浏览器规划（部分已由编辑器方向替代）

- 覆盖广泛的日常文件类别，并持续扩充格式。
- HTML、Markdown、办公文档、电子书等按适合内容的方式浏览。
- 支持压缩包浏览、解压和创建压缩包。
- 核心文件处理以本地完成、离线可用为方向。
- Rust 共享核心，各端原生界面；macOS 先行验证，具体平台方案见下表。
- 保留复制入库规则：默认编辑库内副本，保存到文件库；导出另选目标。直接修改外部原件的工作区模式尚未确认。
- 首页展示最近文件与目录；文件库提供目录和颜色标签。桌面默认网格，可切换列表；快速预览保留浏览位置，持续编辑进入标签工作台。
- 界面采用各平台设计语言，兼顾键鼠、触控、无障碍与减少动态效果设置。
- 大文件流式处理、分页或按需渲染，耗时任务可取消且不阻塞 UI；普通归档不设任意固定字节上限，实际受格式、平台、磁盘和资源条件约束。
- 浏览与普通编辑是主线；依赖工具链的代码智能按阶段接入，不阻塞文件功能。
- 希望以个人 Apple 开发者身份开展，尽量减少公司、服务器及额外资质的负担。

此前文件浏览器规划中，Apple 平台曾约定**先只走 App Store / Mac App Store**、Mac 仅支持 Apple Silicon 的约束，本轮不新增商店外公证分发路线；其他端渠道、最低系统版本、价格及日期待定。2026-10-19 政策和费用研究作为历史资料保留，发布前复核。

## 全端原生规划

本轮将“全端”拆为以下规划范围；新增框架是工程建议，不代表已建立工程或逐项确定版本。

| 平台 | 原生界面方向 | 当前状态 |
| --- | --- | --- |
| macOS | SwiftUI + AppKit | 已有 Apple Silicon 骨架，工程暂为 macOS 14+ |
| iOS / iPadOS | SwiftUI + UIKit | 尚无应用 target 与可交付 iOS 切片 |
| Windows | 建议 WinUI 3 + C# | 规划 |
| Linux | 建议 GTK 4，界面可由 Rust 实现 | 规划 |
| Android | 建议 Kotlin + Jetpack Compose | 规划 |
| HarmonyOS NEXT | 建议 ArkTS + ArkUI | 规划，Rust Native API 桥待验证 |

共享文件处理与数据契约，各端界面和系统交互分别实现。系统 WebView 可用于 HTML/Markdown 内容渲染。Web/WASM 仅为可选预研，暂非正式交付端；手表、电视不自动进入本轮范围。

## 工程骨架状态

实际已有“选择 ZIP → 复制入库 → Rust 列目录 → SwiftUI 展示”的骨架，最近记录存本地 JSON。已有测试源码覆盖选定 ZIP、UTF-8 中文名、缺失文件和入库持久化。2026-10-19 文档记录骨架验证通过；**本次只核对源码，没有重跑构建、测试或启动应用**。通用预览、解压/创建、编辑保存、LSP、Git 和其他平台宿主尚未实现，HyHub 的成果不计入本仓完成度。

以下仅适用于现有 macOS 骨架：

```bash
scripts/build-core.sh
(cd App && xcodegen generate)
(cd App && xcodebuild -project HcFileViewer.xcodeproj -scheme HcFileViewer -destination 'platform=macOS' build)
(cd core && cargo test)
(cd packages/HcCoreSwift && swift test)
```

构建和单元测试默认后台执行；真实窗口、模拟器、输入和剪贴板测试遵循[开发约定](docs/DEVELOPMENT.md)。生成的绑定与 xcframework 不手改。
