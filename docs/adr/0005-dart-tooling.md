# ADR 0005：外部 Dart SDK 的语言服务与 Pub 工具

- 状态：已采用，真实窗口与 Flutter/Pub 项目流程待验证
- 日期：2026-10-21
- 范围：macOS / Apple Silicon，build 24

## 背景

用户要求优先完善 Dart/Flutter 的依赖、语法/类型检查、错误显示、悬浮和快捷跳转，允许分阶段完成。Tree-sitter 着色不提供类型系统或语义引用；不恢复旧源码中的产品实现，也不自行重写 Dart 分析器。

## 决策

1. 使用用户选择的已安装 SDK，直接启动 `dart analysis_server.dart.snapshot --lsp`，以官方 Analysis Server 提供诊断、hover、定义/引用、补全、格式化和文件符号。没有 SDK 时保留基础编辑，不自动安装/更新 SDK 或运行 Pub。
2. 每工作区一个 Swift actor 协议连接；原生编辑投影有序发送 UTF-16 增量。Rust 正式文本/修订与 AppKit UndoManager 的所有权不变；服务响应不能建立第二份可写正式缓冲。
3. 所有显式编辑批次校验文档身份、当前修订、Unicode 边界、大小及范围重叠，通过一次原生可撤销输入提交；本阶段只支持同文档，不声明跨文件事务或接受服务端 applyEdit。
4. SDK/包元数据后台读取；Pub 必须用户点击，先协调保存与冻结清单缓冲，任务结束后重载干净清单。输入按参数数组传入，无 shell 拼接。后台任务拥有独立进程组及可等待退出责任，不借用户终端、不全局杀进程。
5. 导航允许打开依赖/SDK 的本地 `file:` 源码，工作区之外始终只读；不得写 SDK、缓存或将其误作活动包。

## 理由与代价

采用同一 SDK 的分析器和 Pub，可以保持语言/项目模型一致，不分发多份编译器。Swift 只实现窄协议与原生交互，Rust 文本和高亮不增加语言专属 ABI。代价是必须安装合适 SDK，GUI 环境 PATH 发现可能失败，需要明确设置入口；不同 SDK/fork 不能推定兼容。

Dart 3.11.5 的 push diagnostics 没有修订号。HyCode 做顺序门控和显示失效，但不声称能证明每条诊断的版本，不将其用于自动写入。外部 SDK 分析插件和缓存行为也不能被协议包装自动沙箱化。

## 验收与后续

生成临时样本验证官方 stdio 协议、未保存修改、类型错误、hover、定义/SDK 源码、引用、补全、符号与格式化，磁盘保持不变；另做位置/编辑/SDK/包元数据和阻塞/后代进程清理的后台测试。GUI、候选菜单/焦点、IME/Undo、Pub 网络与真实 Flutter 项目不运行，保留未验证。

完整功能矩阵、数量限制、依赖来源及源码地图见 [Dart/Flutter 工具](../DART_FLUTTER.md)。后续按运行/设备与 DAP、热重载、Inspector/DevTools、quick fix/重构和完整 Pub workspace 分阶段推进；本 ADR 不宣称全部已实现。
