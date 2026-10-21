> 历史快照：2026-10-21 更名前的文件浏览器文档。正式名称现为 HyCode，旧实现已按用户要求删除，本文的代码路径、命令、能力与旧产品约束只说明当时状态。当前开发以 [HyCode README](../../../../README.md) 为入口。

# 技术设计与现有骨架

> **2026-10-21 编辑器方向更新**：最新定位改为轻量、原生、完全开源的代码编辑器，借鉴 IDEA 界面组织。先读 [新方向与优先级](EDITOR_DIRECTION.md)；本文旧文件浏览器主线、强制复制入库、付费解锁及商店优先规则遇冲突时仅作历史记录。候选能力和骨架实现状态仍需分别看待。

更新日期：2026-10-21。全端原生、独立项目、文件浏览与编辑是当前方向；新增模块、框架和目录属于工程规划，不表示已实现。

## 1. 当前源码与构建事实

```text
core/                              Rust 库 hc_core 0.1.0
  src/lib.rs                       ArchiveEntry、CoreError、ZipReader
  uniffi-bindgen.rs                 绑定生成器入口
packages/HcCoreSwift/               当前 Swift Package（macOS 14+）
  Sources/HcCore/                   生成的 Swift 绑定，忽略目录
  Sources/HcLibrary/LibraryStore.swift 复制入库、来源、最近记录 JSON
  Headers/                         生成头文件，忽略目录
  hc_coreFFI.xcframework/           生成的 macOS 库，忽略目录
  Tests/HcCoreTests/                Swift 测试及 ZIP Fixtures
App/                               当前 macOS SwiftUI 宿主
  project.yml                      XcodeGen 工程定义
  HcFileViewer/HomeView.swift       ZIP 导入和最近记录
  HcFileViewer/ArchiveView.swift    ZIP 条目列表
scripts/build-core.sh               Rust → Swift 绑定 → macOS xcframework
```

- 当前 UniFFI 0.32.2、zip 9.0.5（deflate）；Swift FFI 模块及 binaryTarget 名为 `hc_coreFFI`。现有 ZIP 能力只是列目录。
- `ZipReader.entries()` 一次返回全部条目，`ArchiveView` 直接调用同步接口；复制和 JSON 读写还在主 actor。这是待后台化的骨架，不是大包流式性能证据。
- `LibraryStore` 是 Swift 实现，最近记录存 JSON；跨端库数据库尚未建立。
- 当前脚本仅打包 macOS 切片，SPM 只声明 macOS，XcodeGen 只有 macOS target。iOS 还需应用 target、设备/模拟器切片、权限和生命周期适配；其他端尚无构建链。
- 骨架暂按 macOS 14+，最终最低系统版本待定。debug dylib 按实际构建设置检查，不仅凭 Xcode 版本推断。
- 2026-10-19 文档记录骨架验证通过。本轮仅核对源码，未重跑构建、测试或应用。

## 2. 目标分层

```text
各平台原生界面
  最近/文件库、快速预览、标签工作台、任务窗、编辑交互
       │
平台适配与语言绑定
  文件选择/授权、句柄/URI、文件协调、原生渲染、分享、生命周期
       │
共享 Rust 应用能力
  文档会话、库记录、任务与取消、编辑事务、归档、格式路由、缓存与导出
       │
格式引擎及可选服务
  Rust crate / 成熟 C/C++ 引擎 / 平台预览适配 / 桌面语言服务
```

按实际功能逐步拆分，不一次性重建整个工程。业务模块用小型类型化接口交互；平台权限对象不进入通用解析器，解析器不创建窗口、弹框或决定导航。

本项目独立维护版本、数据、构建和发布。HyHub 的账号、设备、云盘、远控与发布设施不成为运行依赖，见[复用说明](HYHUB_REUSE.md)。

## 3. 平台适配建议

| 平台 | 界面与系统层 | Rust 接入方向 | 状态 |
| --- | --- | --- | --- |
| macOS | SwiftUI + AppKit | 继续 UniFFI Swift | 已有骨架 |
| iOS / iPadOS | SwiftUI + UIKit | UniFFI Swift，设备/模拟器独立切片 | 规划 |
| Android | Kotlin + Jetpack Compose | 优先验证 UniFFI Kotlin 的 Android 打包 | 建议，未验证 |
| Windows | WinUI 3 + C# | 窄 C ABI + .NET 互操作；其他绑定另评估 | 建议，未验证 |
| Linux | GTK 4，界面可由 Rust 实现 | Rust crate 直接调用；动态边界按需使用 C ABI | 建议，未验证 |
| HarmonyOS NEXT | ArkTS + ArkUI | Rust C ABI + 薄 Native API/Node-API 桥 | 建议，未验证 |

新增框架、最低系统版本和 CPU 架构组合待验证；保留 Mac 仅 Apple Silicon 的既有约束。Windows/Linux x64、arm64 及移动设备/模拟器应分别列构建矩阵。

UniFFI 官方提供 Swift/Kotlin 等绑定，不能据此声称 C#、ArkTS 已统一打通。鸿蒙使用 Node-API 桥也不代表应用具备完整 Node.js 环境。系统 WebView 用于内容渲染，不承担全应用界面。

依据：[UniFFI](https://mozilla.github.io/uniffi-rs/latest/)、[WinUI 3](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/)、[Compose](https://developer.android.com/compose)、[GTK 4](https://docs.gtk.org/gtk4/)、[ArkUI](https://developer.huawei.com/consumer/cn/arkui/)、[OpenHarmony Native API](https://gitee.com/openharmony/docs/blob/master/en/application-dev/napi/napi-guidelines.md)。这些来源说明平台能力，不是本项目验证结果。

## 4. 文件与会话所有权

保留复制入库：外部文件经用户选择/分享导入后建立库内副本；来源路径用于溯源，不自动获得再次访问、覆盖或删除原件的权限。

| 计划对象 | 职责 |
| --- | --- |
| `LibraryItem` | 稳定 ID、库内位置、来源、目录/标签、导入/最近访问时间 |
| `DocumentSession` | 文档身份、版本、阅读状态、编辑缓冲、脏状态及宿主关联 |
| `FileAccess` | 受授权的句柄/URI/路径、访问模式、有效期和关闭责任 |
| `TaskHandle` | 操作 ID、进度、取消、终态及清理，不持有 UI |
| `FormatCapability` | 具体引擎、版本、平台及可执行操作 |
| `WorkspaceContext` | 用户选定项目根、工具链、依赖与索引范围，代码智能阶段引入 |

平台把 security-scoped URL、Android 文档 URI、鸿蒙访问授权转换成受控访问。Rust 按引擎需要接收文件描述符、流、随机访问接口或本地副本，不假设所有端都有持久绝对路径。共享数据契约不代表已经提供账号同步。

目录导入保留内容关系，处理 HTML 相对资源、重名、链接及中断；记录与副本落盘保持一致。现有 JSON 升级时提供版本迁移及恢复，不能静默丢历史。

## 5. 编辑与安全保存

文本、代码、Markdown/HTML 先支持库内副本编辑；Office、PDF、图片和专业格式的可视化编辑、批注、转换分别列能力，不从“万能”推导全部可写。

文档会话保留独立缓冲、撤销、光标、滚动、磁盘版本与草稿。保存前复核版本和权限，按平台采用临时写入、原子替换或文件协调；失败保留缓冲，不显示已保存。截断预览不能充当完整保存输入。

包内条目的预览缓存不作为归档可写入口；编辑前明确提取为库内独立副本，保存不自动改写或重新打包原归档。原位归档编辑单独设计。版本复核与原子替换也不能宣称对所有不协作的外部写入者提供文件系统级比较交换。

保存、导出、重载外部修改、关闭脏标签、退出及草稿恢复分别设计；编码、BOM、换行和元数据保留用真实往返验证。原位置工作区尚待产品决策，不能用库内单文件副本冒充完整原项目或 Git 仓库，见[代码智能](CODE_INTELLIGENCE.md)。

## 6. 后台与大文件

- UI 线程只更新状态和必要可见内容，不承担复制、目录扫描、压缩/解压、完整解码、PDF 首次打开或项目索引；`.task`/`async` 本身不保证同步工作离开主线程。
- 先显示加载态，再执行后台任务；已知总量显示进度，否则显示阶段与转圈，提供取消和重试。
- 归档流式读写，目录/数据列表分页；PDF 按页渲染、图片降采样，限制同时解码与渲染数量，回收不可见缓存。
- 字节数和偏移采用适当的 64 位类型并检查溢出。普通归档不设任意固定字节或总时长上限，仍保留内存、并发、磁盘、嵌套深度和异常膨胀防护。
- 任务区分准备、读取、处理、写入、收尾和成功/失败/取消。输出完成及必要校验后才报告成功，取消仅清理本任务临时输出。
- 会话版本、请求 ID 和代次贯穿异步链路；切换、关闭后丢弃旧结果，回调不在持锁时触发 UI 或重入核心。
- 桌面可评估独立 worker 隔离；移动端按系统允许的进程和后台生命周期实现，不照搬任意子进程。

## 7. FFI 与格式引擎契约

领域类型与绑定 DTO 分离，现阶段继续生成 Swift 绑定。扩展 C ABI 时定义版本、opaque handle、UTF-8 与缓冲长度、申请/释放配对、64 位偏移、错误码、取消及回调注销。Rust panic 和 C++ 异常不得跨外部 ABI；第三方引擎资源与错误在适配层转换。

归档条目 ID 与原始/显示名字分开，输出前校验路径，处理绝对路径、`..`、链接、大小写冲突、磁盘满、损坏、密码错误和非 UTF-8 名字；不能静默跳过错误后报告完整成功。

系统预览属于平台适配器。某端有缩略图或 Quick Look，不等于共享核心或其他端支持相同内容、搜索和编辑。

## 8. 代码智能与构建

原生编辑、高亮/结构解析、语义服务独立分层。语言服务管理器是可选长生命周期模块，处理 LSP 进程、工作区、版本和取消；原生 UI 提供候选列表、悬停、引用结果与导航历史。它不是当前 ZIP 库或 HyHub 一次一进程 worker 的直接替代名称。

桌面先验证 LSP；移动端分别评估内置分析方案，不承诺任意 SDK、Node、JVM 或子进程。详见 [CODE_INTELLIGENCE.md](CODE_INTELLIGENCE.md)。

现有 macOS 骨架构建与测试入口：

```bash
scripts/build-core.sh
(cd App && xcodegen generate)
(cd App && xcodebuild -project HcFileViewer.xcodeproj -scheme HcFileViewer -destination 'platform=macOS' build)
(cd core && cargo test)
(cd packages/HcCoreSwift && swift test)
```

新增平台分别记录工具链、绑定、目标、构建、ABI 和实机证据。核心测试不代替权限、IME、触控、UI、签名或上架验收。格式台账见 [FORMAT_SUPPORT.md](FORMAT_SUPPORT.md)，推进顺序见 [ROADMAP.md](ROADMAP.md)。
