# HyCode

<img src="app/macos/Resources/brand/icon.png" width="96" height="96" alt="HyCode 应用图标">

A high-performance, native macOS code editor — built with Swift and Rust, fully open source.

HyCode 是高性能、轻量、原生的开源代码编辑器。首版专注 **macOS（Apple Silicon）**，采用 **Swift 原生界面 + Rust 内核**，借鉴 IDEA 的工作台组织，追求快速启动、低输入延迟和可控的资源占用。

**当前已建立 macOS 基础文件浏览工作台。** 启动时恢复上次打开的项目；未打开项目时中央显示最近项目，可选择和切换项目、展开项目树、使用文件标签和面包屑导航、查看文件信息；目录仅在项目树浏览，不生成中央列表或标签；当前只读，尚无文本编辑或代码分析器。静默构建与后台测试已通过，真实窗口及性能尚未验证。旧文件浏览器实现保留在 Git 历史中；本次为新工程，尚无正式应用发布。

- 源码：[hhcme/hy_code](https://github.com/hhcme/hy_code)
- 许可证：[MIT](LICENSE)
- 反馈与需求：[GitHub Issues](https://github.com/hhcme/hy_code/issues)
- 参与贡献：[CONTRIBUTING.md](CONTRIBUTING.md)

## 产品方向

- **先做好代码编辑**：本地文件与项目目录、项目树、多标签、面包屑、可靠编辑与安全保存。
- **macOS 原生体验**：Swift 开发，保留系统输入法、菜单、快捷键、窗口和无障碍行为；SwiftUI/AppKit 的具体组合通过原型确定。
- **Rust 内核**：承载文档、编辑事务、搜索与后台任务；语法解析和语言服务按需接入，避免阻塞界面。
- **实测性能**：启动、输入、滚动、文件加载、搜索、内存及取消恢复分别测量；尚未公布性能结果或承诺文件上限。
- **复用开源生态**：允许采用官方和社区的开源组件，按职责、维护情况、性能和许可选择；不要求所有依赖均由 Rust 实现。
- **完整开源**：原生界面、核心、桥接、构建和文档均纳入公开源码，不依赖私有编辑内核或必须登录的后台。

高亮、补全、导航、Git、终端与任务逐阶段增加；首批语言和首个可交付版本的具体范围仍需评审。其他平台属于未来议题，不纳入首版计划。文件预览与归档作为后续配套能力。

## 文档导航

完整目录与阅读顺序见 [docs/README.md](docs/README.md)。

| 文档 | 内容 |
| --- | --- |
| [方向与已定事项](docs/EDITOR_DIRECTION.md) | 已确认范围与尚未决定的事项 |
| [产品需求](docs/PRODUCT_REQUIREMENTS.md) | 工作区、编辑、保存和工作台交互 |
| [技术设计](docs/TECH_DESIGN.md) | Swift/Rust 分层、文档所有权和 FFI |
| [开发约定](docs/DEVELOPMENT.md) | 开发入口、真实命令、验证与证据规则 |
| [品牌与应用图标](docs/BRANDING.md) | 同系列设计、资源、提示词与打包 |
| [当前文件工作台](docs/WORKBENCH.md) | 布局、交互、源码地图、构建及验证边界 |
| [实施路线](docs/ROADMAP.md) | macOS 分阶段目标和验收条件 |
| [性能设计与验收](docs/PERFORMANCE.md) | 测量口径、样本和待确定的预算 |
| [编辑内核与语言服务](docs/CODE_INTELLIGENCE.md) | 文本、语法、语义的候选与边界 |
| [依赖与来源](docs/DEPENDENCIES.md) | 已采用依赖与调研候选分别登记 |
| [能力台账](docs/FORMAT_SUPPORT.md) | 当前实现、后台证据及未验证项 |
| [架构决策](docs/adr/README.md) | 已接受的技术方向及后续 ADR 规则 |
| [开源与分发](docs/FEASIBILITY_AND_DISTRIBUTION.md) | MIT、公开源码及未来应用发布准备 |
| [重写记录](docs/REWRITE_RECORD.md) | 原实现清理与文档基线整理 |

## 现在如何参与

```sh
git clone https://github.com/hhcme/hy_code.git
cd hy_code
python3 scripts/check_docs.py
```

文档检查仅需 Python 3.9+ 标准库。开始开发前先读 [AGENTS.md](AGENTS.md) 和开发约定。

macOS / Apple Silicon 的本地构建（当前验证环境：Xcode 27.1 / Swift 6.4、Rust 1.96.0）：

```sh
bash scripts/build_macos.sh debug
bash scripts/check_native.sh
```

构建产物为 `build/HyCode.app`，脚本不会启动、安装应用或操作窗口。声明的最低系统为 macOS 14，尚未进行真实窗口或旧系统运行验证。完整结构与操作见[工作台说明](docs/WORKBENCH.md)。

**测试只能静默执行，不得打断用户工作。** 不启动应用或模拟器，不操作用户桌面、焦点、键鼠与剪贴板；需要真实窗口的项目保留为未验证。详细约束见[开发约定](docs/DEVELOPMENT.md)。

## 许可证

HyCode 自有代码与文档采用 [MIT License](LICENSE)。实际采用组件的来源、版本和许可见[依赖台账](docs/DEPENDENCIES.md)与[第三方通知](THIRD_PARTY_NOTICES.md)；调研候选与已接入依赖分别登记。
