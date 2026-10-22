# HyCode 开发约定

Web 固定运行资源另需外部 Node 22.22.2+ 与 npm。首次执行 `bash scripts/setup_web_tools.sh` 联网准备锁定的公开 npm 包（禁用 hooks），不修改用户项目。构建缺资源时调用此步骤，应用带服务 JavaScript 而不带 Node。`check_native.sh` 仅检查已准备资源，不安装 npm 包。设置中可指定 Node 路径。

`swift run --jobs 2 HyCodeWebProbe /absolute/path/to/node tools/web-language-services` 仅用自建临时 fixture 检查 stdio、未保存分析、自动导入、Vue 桥接和不执行配置插件的 canary；不启动 AppKit、浏览器/dev server 或用户 scripts。完整边界见 [Web 工具](WEB_TOOLS.md)。

更新：2026-10-22。首版仅 macOS / Apple Silicon，Swift 原生界面 + Rust 内核。当前已有文件工作台、原生基础编辑、Rust 文本/目录内核及无 GUI 测试；实际功能与证据见[工作台说明](WORKBENCH.md)和[编辑说明](EDITING.md)。

## 开始工作

先读 [README](../README.md)、[方向](EDITOR_DIRECTION.md)、[需求](PRODUCT_REQUIREMENTS.md)、[技术设计](TECH_DESIGN.md)，再按[文档索引](README.md)阅读任务专题和 [ADR](adr/README.md)。检查 Git 状态与真实源码后判断现状。历史区只用于追溯，旧 Xcode/SwiftPM/Cargo 命令不再有效。

新增工程时同步补充工具链固定版本、可执行命令和验证环境，不复制旧完成度。文档、架构建议、已实现、后台检查、真实窗口、签名打包和应用公开可用分别记录。外部项目或依赖的测试和性能不能算作 HyCode 的成果。

## 当前真实命令

在仓库根目录运行。当前验证环境为 Apple Silicon、macOS 27.0.1、Xcode 27.1 / Swift 6.4、Rust 1.96.0；Rust 由 `rust-toolchain.toml` 固定，Cargo 版本由锁文件固定依赖。Swift 包声明 macOS 14 部署目标，旧系统运行仍未验证。

```sh
# 仅构建开发应用，不启动
bash scripts/build_macos.sh debug
# 格式、Clippy、Rust 测试、原生桥接构建、Swift Testing、文档检查
bash scripts/check_native.sh
# 只检查文档，需 Python 3.9+ 标准库
python3 scripts/check_docs.py
git diff --check
# 受控的无 GUI 目录读取探针：默认只创建/删除 72 项临时样本
nice -n 10 swift run --jobs 2 HyCodeDirectoryProbe
```

原生脚本最多使用两个构建任务；日常可用 `nice -n 10 bash scripts/check_native.sh` 降低优先级。`swift test --disable-xctest` 运行文本增量/编码/保存冲突/权限/取消、工作区、工具停靠/分隔交互状态及最近项目记录、CoreGraphics 几何/离屏像素合成、CoreText 后台文件名测量的 Swift Testing 命令行入口，不链接应用 target 为测试宿主，不启动 `NSApplication` 或创建窗口。AppKit/SwiftUI 只参与编译，没有 UI 自动化测试。

Rust 用例使用 `--test-threads=1` 串行降载；build 26 复查时曾在并行高亮用例遇到既有 100 ms 后台预算超时，失败记录保留，未放宽生产预算或断言。降载后通过不能代替高亮实际延迟、冷缓存或前台帧率验收。

脚本只读取文档，检查 UTF-8、本地链接目标及历史 manifest 哈希，不请求网络、不构建应用、不启动窗口。GitHub Actions 的 `Documentation` 工作流运行同一检查；它不是 macOS 应用构建或验收。

当前仓库组织：

| 路径 | 职责 |
| --- | --- |
| `README.md`、`AGENTS.md` | 项目与开发入口 |
| `LICENSE`、`CONTRIBUTING.md`、`SECURITY.md` | 许可、贡献与安全说明 |
| `docs/` | 方向、需求、架构、性能、依赖及能力状态 |
| `docs/adr/` | 编号化架构决策 |
| `docs/history/` | 原文快照及完整性清单 |
| `.github/` | Issue/PR 模板和文档检查流程 |
| `scripts/check_docs.py` | 可在本地与 CI 执行的文档检查 |
| `Cargo.toml`、`crates/hycode-core/` | Rust 文本/修订/编码与只读目录内核 |
| `Package.swift`、`packages/HyCodeWorkspace/` | Swift 包、FFI 包装及可独立测试的模型 |
| `bindings/CHyCodeCore/` | ABI 1 头文件与模块声明 |
| `app/macos/` | SwiftUI 工作台、AppKit 项目树/文本编辑、品牌源图及开发应用元数据 |
| `scripts/build_core.sh`、`scripts/build_macos.sh`、`scripts/check_native.sh` | 真实构建和静默检查 |
| `scripts/build_icons.sh` | 源 PNG → 十尺寸 iconset → ICNS，纯后台，不操作 Dock/Finder |
| `tools/DirectoryProbe/` | 无 AppKit/应用宿主的单层读取探针，默认使用临时样本 |
| `tools/DebugProbe/` | 显式 SDK DAP 探针，只调试生成的 Dart 控制台；当前 fork 因 VM 参数拒绝而未通过，不自动运行 |
| `tools/fixtures/dap_adapter.py` | 自有无 SDK stdio 替身，供协议测试；不执行项目/GUI/设备 |
| `tools/DartProbe/` | 显式 SDK、临时样本/缓存的 stdio 分析器协议探针；不运行 Pub、GUI 或用户项目 |
| `THIRD_PARTY_NOTICES.md`、`third_party/licenses/` | 实际依赖与标准库通知 |

当前 Bundle ID 为 `io.github.hhcme.hycode`，本地开发版本 `0.1.0` / build `31`。这些标识不表示已有正式版本或商店记录。先运行 `bash scripts/build_core.sh` 才能单独构建 Swift 包；普通使用以组合脚本为准，不运行 `swift run HyCode` 做测试。

Dart/Flutter 首批工具与 SDK 协议检查见 [DART_FLUTTER.md](DART_FLUTTER.md)。`HyCodeDartProbe /path/to/sdk` 是纯命令行临时样本，未运行 Flutter 应用、设备、Pub 或网络安装；真实 SDK 操作不会自动加入通用检查脚本。新原生进程适配的取消/后代清理测试仅生成自己的 cat/sleep/sh 固定 fixture，不执行用户命令。

新增 DAP 使用自有 `tools/fixtures/dap_adapter.py` stdio fixture；`HyCodeDebugProbe /path/to/sdk` 是另一个显式入口，只尝试调试生成的 Dart 控制台脚本，不是 Flutter 应用。本机 fork 拒绝 `enable_vm_service` 等启动参数，当前真实 DAP 探针未通过；不把该入口自动加入通用测试，不为补验收改动外部 SDK 或启动 GUI/设备。完整 Flutter 必做范围见[能力清单](FLUTTER_PLAN.md)。

## 静默测试规则

**测试只能静默执行，不得打断用户工作。** 这是一项执行约束，适用于本机手动命令、自动化脚本、测试 runner 和性能测量，不能仅因命令从终端或后台发起就视为静默。

- 允许不启动带界面宿主的后台构建、静态检查、单元测试、无界面集成测试和受控的后台 benchmark。
- 禁止启动带界面的应用、模拟器或测试宿主；不显示、激活、移动或切换窗口，不抢焦点，不切换桌面或全屏空间。
- 禁止真实或合成键鼠输入、系统菜单操作、权限弹窗、系统通知和声音，不截取或录制用户桌面，不读取或改写系统剪贴板。
- 不关闭、重启或修改用户正在使用的应用、窗口、会话和数据；测试使用临时目录、可分发样本与进程内替身，不使用用户原件或真实项目做破坏性验证。
- 隐藏启动、`open -g`、独立数据目录、直接运行可执行文件和所谓“不激活”参数，都不能作为静默保证；执行前检查测试入口及其子进程会不会创建 GUI 或影响桌面。
- 限制 CPU、内存、磁盘 I/O 与并发；可能明显拖慢前台工作的压力测试或长时间测量应降载或跳过，不能只保证不弹窗。
- 无法确认静默的入口不执行；需要 GUI、焦点、真实输入、系统剪贴板或桌面截图的测试保留断言并标为未验证，不绕过限制补测。

真实交互与后台证据仍分开命名和报告。保留真实窗口、IME、焦点与键盘等验收目标，不通过删除断言或用后台替身结果宣称真实交互已通过；本规则下不能执行的部分记录为验证缺口。历史文档中的交互测试许可不覆盖当前静默约束。

2026-10-21 本轮用户明确授权操作 WebStorm 记录布局行为；该例外仅用于指定参考应用的工具窗口切换，已结束并恢复原展开状态。未由此授权启动 HyCode 或其他 GUI 测试。操作与证据边界见[工作台记录](WORKBENCH.md)。后续默认仍按上述静默规则执行。

## 架构与数据

- 每个文档、编辑事务和工具任务明确所有者及生命周期；单一正式缓冲，跨视图共享文档会话。
- Rust 内核与 Swift UI/系统适配分离，接口明确所有权、编码、位置、线程、取消、错误、回调与释放。
- 增量更新跨语言边界，不因每次输入复制整篇文本。性能与资源预算按[性能设计](PERFORMANCE.md)验证。
- 文件访问来自明确授权的工作区或单文件。原文件、副本、缓存、草稿与导出目标分别标明，不静默切换保存位置。
- 版本检查、失败保存、草稿恢复与脏标签/窗口/退出保护采用同一语义；不保存截断预览，不重放过期服务响应。
- 重型 I/O、扫描、解析和索引离开 UI 线程；任务可取消，旧会话结果不能写回新会话。

## 测试与证据

使用临时目录和可分发样本。编辑验证中文组合输入、emoji/位置、撤销重做、编码/换行、冲突、取消和失败恢复；语言服务另验修订、导航、缺 SDK、崩溃及关闭。

并发、FFI 和原生内存变化按风险采用可静默执行的竞态、sanitizer 和 ABI 检查。性能测量记录硬件、系统、工具链、构建配置及样本；涉及真实窗口或输入的测量不在当前执行范围。文档改动检查链接、状态、历史完整性和 diff，不运行不存在的构建或 GUI。

## 开源、提交与命名

自有代码与文档使用 [MIT](../LICENSE)，贡献说明见 [CONTRIBUTING.md](../CONTRIBUTING.md)。引入外部组件前更新[依赖台账](DEPENDENCIES.md)，记录来源、版本、许可与分发方式。Apple 系统框架属于平台依赖，不称为本项目开源组件。

当前文档使用相对路径，不要求维护者的本机目录或私有仓库。不要提交凭据、私人数据或缓存；历史快照保留原文及哈希，其旧路径不是运行前提。

`.gitattributes` 保留历史快照与上游许可的原始字节；上游许可不参与本项目的空白格式改写，避免为通过检查修改通知原文。

保留无关改动；只有用户授权时才提交、推送或发布。默认分支为 `main`，新自动化工作分支使用 `codex/` 前缀。新应用 target、crate、CLI、Bundle ID 和数据目录围绕 HyCode 定义，不沿用旧产品标识。应用打包和发布另行授权，不由文档推送自动触发。

项目后台诊断的 FSEvents 测试只监听生成的临时目录，在 utility 队列接收事件，不使用主 run loop 或 GUI 宿主；扫描/汇总/有序同步测试同样在命令行执行。真实外部 SDK/Node 探针仍需显式运行，不加入通用检查；入口及边界见[项目分析](PROJECT_ANALYSIS.md)。
