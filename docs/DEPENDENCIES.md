# HyCode 依赖与来源

更新：2026-10-22。自有代码与文档采用 [MIT](../LICENSE)。当前应用为文件工作台与基础文本编辑；使用系统 TextKit 1 和 Tree-sitter 基础着色，无第三方编辑器框架；Dart 语义、Pub 与 Flutter DAP/工具命令使用用户安装的外部 SDK，不随应用分发。

## 已采用

| 组件 | 固定方式 | 用途与来源 |
| --- | --- | --- |
| Rust | [rust-toolchain.toml](../rust-toolchain.toml)：1.96.0 | 标准库与静态文本/目录内核；标准库通知纳入第三方清单 |
| Swift / macOS SDK | 当前验证 Swift 6.4 / Xcode 27.1，声明部署目标 macOS 14 | SwiftUI、AppKit TextKit 1 / UndoManager、Foundation NSFileCoordinator、Darwin 文件系统接口、CoreText 后台文件名测量、CoreGraphics 几何、QuartzCore 显示刷新与分隔图层、CoreGraphics 离屏图像、os 性能区间、系统图标；平台依赖，不重新许可为本项目代码 |
| serde / serde_core / serde_derive | 1.0.229；[Cargo.toml](../Cargo.toml) 与 [Cargo.lock](../Cargo.lock) | JSON 响应模型序列化；[上游](https://github.com/serde-rs/serde) |
| serde_json | 1.0.154；同上 | ABI 结果编码；[上游](https://github.com/serde-rs/json) |
| Swift Testing | 验证环境随 Xcode 提供，不下载外部 Swift 包 | 工作区与几何数据模型的无 GUI 测试 |
| Tree-sitter 与语法包 | 主库 0.27.1，12 个语法 crate 由 Cargo.toml/Cargo.lock 固定 | 增量树、可见范围高亮；Dart/Vue 为社区语法，版本/来源/许可见第三方通知及[高亮说明](SYNTAX.md) |
| Dart Analysis Server / Dart Pub / Flutter CLI / SDK DAP | 外部 SDK，不在构建锁文件或应用内；语言 LSP 验证 Dart 3.11.5；DAP fixture 通过，当前 fork 真实控制台调试未通过；Flutter 安装元数据 3.41.10-ohos-0.0.2-beta | 官方 [Dart SDK](https://github.com/dart-lang/sdk/tree/3.11.5) / [Flutter](https://github.com/flutter/flutter)，上游均 BSD-3-Clause；仅调用已安装命令，未复制 SDK 或 IDE 插件；[Dart 许可](https://github.com/dart-lang/sdk/blob/3.11.5/LICENSE)、[Flutter 许可](https://github.com/flutter/flutter/blob/3.41.5/LICENSE)。此 fork 与其他版本兼容未完整验证，细节见 [Dart/Flutter 工具](DART_FLUTTER.md) |
| Python 标准库 | Python 3.9+ | 本地文档检查，无第三方 Python 包 |
| GitHub Actions checkout | SHA 固定在[工作流](../.github/workflows/docs.yml) | 现有 CI 只检查文档，不进入应用分发 |

Cargo 共 37 项直接/传递依赖，版本与源码校验值以 Cargo.lock 为准；运行时与构建时来源均记录在[第三方通知](../THIRD_PARTY_NOTICES.md)，并保留许可原文。双许可组件选择 MIT，foldhash 采用 Zlib，Unicode 数据和嵌入子组件另保留通知。没有复制第三方编辑器源码或从私有安装包提取组件，没有新增外部 Swift 包。

当前 Swift/Rust 桥接为仓库内窄 C ABI，未采用 UniFFI 或 cbindgen。文本与目录内核通过单元测试及 Swift 桥接/保存测试；系统 UI 的真实窗口、旧系统及应用分发仍未验证。

## 品牌素材与构建工具

HyCode 应用图标由内置 imagegen 根据用户要求重新创作，HyHub 只作视觉参考，其原图和脚本未复制；图稿、提示词与来源边界见[品牌说明](BRANDING.md)。构建使用 macOS 自带 `sips` / `iconutil` 导出 ICNS，属于平台工具；应用运行不需要 imagegen 或额外图像库。

## 研究候选，尚未采用

| 组件 | 拟用职责 | 状态 |
| --- | --- | --- |
| [Ropey](https://github.com/cessen/ropey) | Rust 正式文本缓冲 | 版本、性能、所有权和接入待验证 |
| [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) | Swift 语义服务 | 工具链、项目模型和生命周期待验证 |
| [rust-analyzer](https://rust-analyzer.github.io/book/) | Rust 语义服务 | 环境、协议和资源待验证 |
| [UniFFI](https://github.com/mozilla/uniffi-rs) | 后续复杂桥接评估 | 当前目录接口未使用，不预判编辑事务方案 |

官方和社区组件均可采用，但维护方身份不代替实际质量验证。每次新增或升级应记录：固定版本与校验、来源、许可/版权/传递依赖、使用模块、链接和分发方式、生命周期/线程/取消/错误、资源预算、本项目证据与限制。第三方内容保留自身许可，不能以项目 MIT 覆盖。
