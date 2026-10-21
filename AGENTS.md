# HyCode 开发入口

- 正式名称 HyCode，仓库为 `hhcme/hy_code`。目标是高性能原生开源代码编辑器；首版仅 macOS / Apple Silicon，Swift 原生界面 + Rust 内核。
- 开始前读 README.md、docs/EDITOR_DIRECTION.md、docs/PRODUCT_REQUIREMENTS.md、docs/TECH_DESIGN.md、docs/DEVELOPMENT.md，再按 docs/README.md 读任务专题。
- 2026-10-21 清理旧实现后，现已重新建立 macOS 文件工作台、原生基础编辑、Rust 文本/目录内核及后台测试。当前范围见 docs/WORKBENCH.md 和 docs/EDITING.md；分析器尚未接入。旧源码和 docs/history/ 仅用于追溯，不据此恢复旧产品。
- 自有代码与文档采用根 MIT LICENSE；可以采用官方或社区开源组件，接入前记录版本、来源、许可、通知与验证。候选和已采用依赖在 docs/DEPENDENCIES.md 分开登记。
- 规划、选型、已实现、后台验证、真实窗口验证、签名打包和应用发布分别记录。公开仓库或文档 CI 通过不表示应用存在或通过验收。
- 测试只能静默执行，不得打断用户工作。只运行不会启动 GUI、弹窗或占用前台的后台构建、静态检查、单元测试和无界面集成测试；禁止启动应用/模拟器、操作真实窗口/键鼠/系统菜单、访问系统剪贴板、截取用户桌面，以及关闭或重启用户应用。
- 隐藏启动、独立数据目录和后台启动参数不能证明测试静默。无法确认不会干扰前台的测试不执行，保留断言并标为未验证；控制 CPU、内存、I/O 和并发，避免测试负载拖慢用户工作。完整规则见 docs/DEVELOPMENT.md。
- WebStorm 布局参考已有本轮用户明确授权的操作记录，观察已结束并恢复展开布局；不计入 HyCode GUI 验收，也不自动授权后续启动 HyCode 或其他应用。
- 不修改 HyHub 或其他独立项目的源码、固定包、用户数据和服务端作为附带步骤。可读取私有源码不等于可以公开，外部项目的测试和性能不计入 HyCode。
- 文档、缓冲、事务与工具任务保持单一所有者；耗时 I/O、解析、扫描和索引离开 UI 线程。FFI 明确生命周期、线程、编码、取消和释放责任。
- 真实入口：`bash scripts/build_macos.sh [debug|release]` 只构建本地开发应用，`bash scripts/check_native.sh` 运行无 GUI 的 Rust/Swift 测试和文档检查。产物为 build/HyCode.app；不得自动启动、安装或将开发构建称为正式发布。
- 保留无关改动；提交、推送和发布按用户授权执行。历史快照保持原文及 manifest 哈希，当前文档使用仓库相对路径，不依赖维护者本机目录。
