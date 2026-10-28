# HyCode 依赖与来源

更新：2026-10-28。自有代码与文档采用 [MIT](../LICENSE)。当前应用为文件工作台与基础文本编辑；使用系统 TextKit 1 和 Tree-sitter 基础着色，无第三方编辑器框架；Dart 语义、Pub 与 Flutter DAP/工具命令使用用户安装的外部 SDK，不随应用分发。

## 已采用

build 48 新增 SwiftTerm 1.20.0（MIT，commit `5d14406844143538cd8f8851d2d8a67c1fe443e5`），作为原生终端模拟器/AppKit 视图；不采用其 LocalProcess。上游 CLI 依赖 swift-argument-parser 1.8.2（Apache-2.0）由 SwiftPM 锁定但不链接应用；版本/来源/原始许可哈希见[终端依赖台账](../third_party/terminal-dependencies.json)，`python3 scripts/check_terminal_dependencies.py` 离线校验。资源与 C helper 由构建脚本打包，范围见[终端专题](TERMINAL.md)。本批开始采用外部 Swift 包，以下早期“没有新增外部 Swift 包”为当时状态。

| 组件 | 固定方式 | 用途与来源 |
| --- | --- | --- |
| Rust | [rust-toolchain.toml](../rust-toolchain.toml)：1.96.0 | 标准库与静态文本/目录内核；标准库通知纳入第三方清单 |
| Swift / macOS SDK | 当前验证 Swift 6.4 / Xcode 27.1，声明部署目标 macOS 14 | SwiftUI、AppKit TextKit 1 / UndoManager、Foundation NSFileCoordinator、Darwin 文件系统接口、CoreServices FSEvents 递归后台监听、CoreText 后台文件名测量、CoreGraphics 几何、QuartzCore 显示刷新与分隔图层、CoreGraphics 离屏图像、os 性能区间、系统图标；平台依赖，不重新许可为本项目代码 |
| serde / serde_core / serde_derive | 1.0.229；[Cargo.toml](../Cargo.toml) 与 [Cargo.lock](../Cargo.lock) | JSON 响应模型序列化；[上游](https://github.com/serde-rs/serde) |
| serde_json | 1.0.154；同上 | ABI 结果编码；[上游](https://github.com/serde-rs/json) |
| Swift Testing | 验证环境随 Xcode 提供，不下载外部 Swift 包 | 工作区与几何数据模型的无 GUI 测试 |
| Tree-sitter 与语法包 | 主库 0.27.1，15 个语法 crate 由 Cargo.toml/Cargo.lock 固定 | 增量树、可见范围高亮；Dart/Vue 为社区语法，版本/来源/许可见第三方通知及[高亮说明](SYNTAX.md) |
| Dart Analysis Server / Dart Pub / Flutter CLI / SDK DAP | 外部 SDK，不在构建锁文件或应用内；语言 LSP 验证 Dart 3.11.5；DAP fixture 通过，当前 fork 真实控制台调试未通过；Flutter 安装元数据 3.41.10-ohos-0.0.2-beta | 官方 [Dart SDK](https://github.com/dart-lang/sdk/tree/3.11.5) / [Flutter](https://github.com/flutter/flutter)，上游均 BSD-3-Clause；仅调用已安装命令，未复制 SDK 或 IDE 插件；[Dart 许可](https://github.com/dart-lang/sdk/blob/3.11.5/LICENSE)、[Flutter 许可](https://github.com/flutter/flutter/blob/3.41.5/LICENSE)。此 fork 与其他版本兼容未完整验证，细节见 [Dart/Flutter 工具](DART_FLUTTER.md) |
| ImageIO / CoreGraphics | macOS 系统框架；随系统版本变化 | 图片类型识别、首帧与方向处理、受限降采样和立即解码的只读 RGBA 投影；不分发第三方解码器 |
| AVFoundation / CoreMedia / CoreVideo | macOS 系统框架；部署目标仍为 macOS 14 | 视频异步属性、AVPlayer/AVPlayerLayer、受限本地资源；测试只生成无音轨小样本和离屏单帧，无播放器/窗口；未新增第三方解码器或 SDK 分发 |
| resvg / usvg / roxmltree | resvg/usvg 0.48.1，预检 roxmltree 0.21.1；Cargo.lock 固定 | Rust 后台 SVG 栅格化；禁用外部资源和嵌入图片，限制复杂效果；52 项新增 crate 的版本/许可/通知哈希见[机器台账](../third_party/image-preview-crates.json)与 [ADR 0008](adr/0008-image-preview.md) |
| pulldown-cmark / pulldown-cmark-escape / unicase | 0.13.5 / 0.11.0 / 2.10.0，Cargo.lock 固定 | Markdown 受限 HTML 投影；[来源、校验与原始通知](../third_party/markup-preview-crates.json)，MIT（unicase 选择 MIT）；未启用 SIMD 或命令行组件 |
| WebKit | macOS 系统框架 | 仅静态预览，非工作台 UI；资源由原生受限读取，页面脚本关闭，网络规则预先安装 |
| Swift / Java / SQL 工具 | SourceKit-LSP 外部 Swift 6.4；外部 JDT LS 探针版本 1.50.0 / JDK 21.0.12.1；sqlparser 0.63.0 | [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) Apache-2.0（附运行库例外）；[JDT LS](https://github.com/eclipse-jdtls/eclipse.jdt.ls) EPL-2.0；二者及 SDK 不随包分发。SQL/递归保护与 3 个新语法包共 16 项新增或变更 crate 的来源、许可与原始通知见[台账](../third_party/native-language-crates.json)和[语言说明](NATIVE_LANGUAGES.md) |
| Python 标准库 | Python 3.9+ | 本地文档检查，无第三方 Python 包 |
| Web 语言服务 | TypeScript 6.0.3、typescript-language-server 6.0.2、@vue/language-server 3.3.13、vscode-langservers-extracted 4.10.0、yaml-language-server 2.0.0 | npm 固定锁文件与 119 项直接/传递条目，来源/许可/校验见 [Web 工具](WEB_TOOLS.md) 和[第三方通知](../THIRD_PARTY_NOTICES.md)；外部 Node 22.22.2+ 不分发 |
| SchemaStore 离线数据 | commit `4b9347599acb42276483fc514f641505e205d331`，14 个原始 JSON Schema | [上游](https://github.com/SchemaStore/schemastore/tree/4b9347599acb42276483fc514f641505e205d331)，Apache-2.0；[来源与哈希](../tools/web-language-services/schemas/catalog.json)、原文 LICENSE/NOTICE 随包保留；不是可执行项目配置 |
| GitHub Actions checkout | SHA 固定在[工作流](../.github/workflows/docs.yml) | 现有 CI 只检查文档，不进入应用分发 |

Cargo 共 107 项直接/传递依赖（原 37 项、图片新增 52 项、Markdown 新增 3 项、原生语言净新增 15 项；SQL 语法的 cc ~1.2.1 约束另使 cc 从 1.9.0 改为 1.2.67），版本与源码校验值以 Cargo.lock 为准；运行时与构建时来源均记录在[第三方通知](../THIRD_PARTY_NOTICES.md)，并保留许可原文。双许可组件选择 MIT，foldhash 采用 Zlib，Unicode 数据和嵌入子组件另保留通知。没有复制第三方编辑器源码或从私有安装包提取组件，没有新增外部 Swift 包。

当前 Swift/Rust 桥接为仓库内窄 C ABI，未采用 UniFFI 或 cbindgen。文本与目录内核通过单元测试及 Swift 桥接/保存测试；系统 UI 的真实窗口、旧系统及应用分发仍未验证。

## 内置 Codex 运行程序

采用官方 Codex CLI 0.164.0（Apache-2.0）及其 Code Mode host、ripgrep 15.2.0（MIT，含 PCRE2 10.45 BSD 通知）。作为独立子进程随包分发，不与本项目 Rust 内核链接，也不要求系统 Node。固定来源、原生 npm 归档 SHA-512、四个文件 SHA-256 与许可原文哈希见 [manifest](../tools/codex-runtime/manifest.json)；上游 LICENSE/NOTICE 和 Ratatui/ripgrep/PCRE2 原始通知保留于[许可目录](../third_party/licenses/codex-0.164.0)。采用上游编译产物，第三方代码保留自身许可。Voice 相关二进制/动态库/资源未采用。

首次约 135 MiB 下载，运行文件约 318 MiB；构建、校验和协议探针分别记录。真实模型工具环路、App 内本地凭据、窗口、旧系统、性能和分发签名尚未验收，见[内置 Codex](CODEX_AGENT.md)。

## 品牌素材与构建工具

HyCode 应用图标由内置 imagegen 根据用户要求重新创作，HyHub 只作视觉参考，其原图和脚本未复制；图稿、提示词与来源边界见[品牌说明](BRANDING.md)。构建使用 macOS 自带 `sips` / `iconutil` 导出 ICNS，属于平台工具；应用运行不需要 imagegen。图片预览新增的 Rust 图像依赖另列于已采用台账，不用于品牌图标生成。

## 研究候选，尚未采用

| 组件 | 拟用职责 | 状态 |
| --- | --- | --- |
| [Ropey](https://github.com/cessen/ropey) | Rust 正式文本缓冲 | 版本、性能、所有权和接入待验证 |
| [rust-analyzer](https://rust-analyzer.github.io/book/) | Rust 语义服务 | 环境、协议和资源待验证 |
| [UniFFI](https://github.com/mozilla/uniffi-rs) | 后续复杂桥接评估 | 当前目录接口未使用，不预判编辑事务方案 |

官方和社区组件均可采用，但维护方身份不代替实际质量验证。每次新增或升级应记录：固定版本与校验、来源、许可/版权/传递依赖、使用模块、链接和分发方式、生命周期/线程/取消/错误、资源预算、本项目证据与限制。第三方内容保留自身许可，不能以项目 MIT 覆盖。

## Codex 界面参考（未采用组件）

VS Code Codex 扩展 26.1007.21434 及官方 IDE 文档图片仅用于观察侧栏结构，没有复制或打包其 VSIX、脚本、样式、图标或图片。界面由自有 SwiftUI/AppKit 代码实现，采用 Apple 系统符号；不将此参考登记为已采用的开源依赖。参考与验收边界见[内置 Codex](CODEX_AGENT.md)。
