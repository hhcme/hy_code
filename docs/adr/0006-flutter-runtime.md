# ADR 0006：Flutter 运行、DAP 与工具任务

- 状态：已采用首批实现；真实 Flutter/设备、窗口与性能待验证
- 日期：2026-10-22
- 范围：macOS / Apple Silicon，build 26；完整目标见[九类能力清单](../FLUTTER_PLAN.md)

## 决策

1. WorkbenchStore 独占 FlutterWorkspaceController；它与 Dart 分析器分开持有运行任务，重启分析器不停止运行中的应用。工作区关闭/切换等待两个所有者回收，旧任务捕获原访问上下文，不能写入新会话。
2. FlutterDebugSession actor 使用所选外部 SDK 的 `flutter debug_adapter`，遵循 DAP 与 SDK 扩展，不自行实现 Dart VM 调试器。StdioProtocolConnection 复用有界 Content-Length/进程组/写端/超时取消，显式分开 LSP 与 DAP 消息策略；LanguageServerConnection 保留为 LSP 默认策略的源码别名。反向终端/调试请求始终拒绝。
3. initialize 能力、initialized 事件、launch 帧写完三个条件全部满足才发送初始断点/异常配置及 configurationDone；不依赖不同任务 continuation 的恢复顺序。停止先请求 disconnect/terminateDebuggee，再回收自有进程组，不全局杀应用或设备进程。
4. 每工作区保存一份运行配置和有界断点基线。运行前保存打开文档，保存失败取消启动。入口、包根和配置固定在本次会话；显式设备刷新不启动模拟器。run/build/test 传 `--no-pub`，依赖操作仍走原清单租约；SDK 自身缓存行为不保证无副作用。
5. 断点投影跟随未保存编辑，持久化与 SDK 同步只使用磁盘基线。保存前捕获快照，成功后根据是否仍有新编辑分别更新；丢弃恢复最近成功保存基线。响应与后续 changed/removed 事件按 adapter ID 关联；事件可先于响应到达，UI 合并刷新。
6. 原生调试面板显示调用栈/变量/求值；所有回写含错误都校验会话、停止代次、所选帧及查询票据。保存后热重载默认关闭，忙碌时保留最新保存并合并补一次；停止清除待重载。Inspector 节点绑定 isolate/重启代次，显式刷新后可选择并导航源码，旧树不能用于新 isolate。
7. 设备、Doctor、build、test 均为明确按钮任务，参数数组调用、无 shell；输出与 test reporter 分开收流，避免 stderr 混进 JSON。控制台最多保留约 256 KiB 字符内容、80 ms 合并；测试最多 1,000 项/单行 64 KiB，树最多 2,000 节点/32 层，断点最多 1,000 项。新功能不增加 Rust ABI、独立正式文本或撤销历史。

## 验证与后续

后台使用纯模型和自有 Python stdio fixture，覆盖握手相邻消息/分片、默认异常过滤、拒绝反向终端、断点确认/移动、状态代次、变量请求、控制命令和阻塞写端退出；AppKit/SwiftUI 仅编译。不得由 fixture 推导真实 Flutter/平台兼容。

显式 SDK 的语言探针继续通过；新增 DAP 探针只尝试生成的 Dart 控制台，不运行 Flutter GUI/用户项目/设备/Pub。本机 Dart 3.11.5 fork 在 debuggee 启动时拒绝 `enable_vm_service` 等 VM 参数，该探针未通过，不能记录真实断点/调用栈通过，也不修改外部 SDK 规避。其他 SDK 与真实 Flutter 流程仍待验证。完整 Inspector/DevTools、测试调试/覆盖率显示、更多配置、attach、智能补全和跨文件重构继续按能力清单实现。
