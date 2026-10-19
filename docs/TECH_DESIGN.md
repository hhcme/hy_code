# 技术结构（工程骨架）

记录日期：2026-10-19。本页记录工程骨架的实际结构与关键决策，对应需求和可行性文档中的方向，随开发演进更新。

## 目录结构

```
core/                          Rust 核心 hc_core（UniFFI proc-macro 导出）
  src/lib.rs                   当前能力：ZIP 目录读取（ZipReader::open / entry_count / entries）
  src/uniffi-bindgen.rs        绑定生成器入口
packages/HcCoreSwift/          Swift 桥接包（SPM，两个产品）
  Sources/HcCore/              UniFFI 生成的 Swift 绑定（构建产物，不入库）
  Sources/HcLibrary/           应用侧代码：RecentItem + LibraryStore（复制入库、最近记录 JSON 持久化）
  Headers/ + hc_coreFFI.xcframework/   构建产物，不入库
  Tests/HcCoreTests/           Swift 测试 + ZIP 样本（含中文文件名）
App/                           macOS 应用（SwiftUI）
  project.yml                  xcodegen 工程定义（源头）；.xcodeproj 是生成物，不要手改
scripts/build-core.sh          构建链：cargo → uniffi-bindgen → xcodebuild -create-xcframework
```

## 关键决策

- FFI 采用 UniFFI proc-macro 模式（uniffi 0.32），Swift 绑定由 `scripts/build-core.sh` 生成；Swift 侧 FFI 模块名为 `hc_coreFFI`，SPM binaryTarget 与之同名。
- 骨架部署目标 macOS 14.0，属默认起步值；最终最低版本仍按需求文档待定。
- Xcode 27 默认启用 debug dylib：主可执行文件是壳，实际代码在 `HcFileViewer.debug.dylib` 内，验证符号时应看后者。
- 测试策略：`cargo test` + `swift test` 全部命令行静默运行（含 ZIP 中文文件名样本、入库复制与持久化用例），不启动 App 窗口。
- iOS 复用路径：Rust 侧已具备 aarch64-apple-ios 构建目标；后续为 xcframework 追加 iOS 切片，App 侧另建 iOS target 即可，core 与 HcLibrary 不需要改动。

## 本地开发流程

1. `scripts/build-core.sh` —— 首次克隆后或改动 core 后必须执行，生成绑定与 xcframework。
2. `cd App && xcodegen generate` —— 改动 project.yml 后重新生成工程。
3. 构建 App：`xcodebuild -project HcFileViewer.xcodeproj -scheme HcFileViewer -destination 'platform=macOS' build`
4. 测试：`cd packages/HcCoreSwift && swift test`；`cd core && cargo test`
