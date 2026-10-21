# Dart / Flutter 完整开发能力清单

更新：2026-10-22。用户已明确要求 Flutter 相关开发能力全部纳入目标；以下九类是必做范围，不以当前首批功能替代。它们分批实现和验收，不承诺一次构建达到完整 IDEA 插件覆盖，也不以菜单或协议模型代表真实应用流程通过。当前工具说明见 [DART_FLUTTER.md](DART_FLUTTER.md)。

## 功能矩阵

| 类别 | 完整目标 | 当前实现 / 剩余范围 |
| --- | --- | --- |
| F1 设备与运行配置 | 设备/模拟器发现、手动启动与连接、多个命名配置、包/入口、debug/profile/release、flavor、参数、defines/define 文件、环境、attach | 设备显式刷新和选择、每工作区一份入口/模式/flavor/defines/参数配置已接入；多配置、模拟器管理、attach、环境与 define 文件仍待接入 |
| F2 运行与构建 | 运行、停止、构建、安装、打包、平台/模式/入口一致、输出跳源码、任务与取消 | 首批 DAP 运行/停止和 SDK build 按钮已接入；保留独立输出与退出码，运行/构建/测试不隐式 Pub；安装/产物浏览、完整输出定位及更多构建选项待接入 |
| F3 调试 | 普通/条件/命中次数/日志断点、异常暂停配置、继续/暂停/单步、线程/isolate、同步/异步调用栈、变量树、监视、求值、依赖调试与 attach | 首批普通/条件/日志断点、SDK 默认异常过滤、暂停/继续/单步、首个停止线程调用栈/作用域/变量和显式求值已接入；断点事件确认、保存基线与丢弃恢复已建模。命中计数 UI、异常配置、线程切换、变量分页/回退、监视列表及 attach 待接入 |
| F4 热更新 | 手动热重载/热重启、保存后热重载开关、连续保存合并、失败保留运行会话、平台/模式能力降级 | SDK hotReload/hotRestart 及保存成功后重载开关已接入，忙碌期间的保存保留待重载；真实平台能力、重载错误导航与完整恢复交互待验证/完善 |
| F5 测试与覆盖率 | unit/widget/integration/golden、树分组、单项/分组/失败重跑、过滤、测试调试、覆盖率导入/行标记、比较失败结果 | SDK test machine reporter、指定文件/目录、成功/失败结果和 coverage 命令开关已接入；不代表测试发现、覆盖率显示或 golden/integration 专用流程完成。其余均待接入 |
| F6 Inspector 与 DevTools | Widget/RenderObject 树、属性/布局约束、选取并跳源码、布局/重绘/性能叠层、日志，接入 SDK DevTools 的 CPU/内存/时间线/网络能力 | 首批显式刷新 Widget summary 树、节点选择和创建位置导航已接入；isolate/热重启代次隔离。完整属性/布局工具、扩展状态控制、DevTools 服务与各性能页面待接入 |
| F7 智能编辑 | 输入触发补全、snippet/占位跳转、参数提示、自动导入、语义着色、括号/缩进/折叠、Dart/Flutter 专用编辑 | 已有显式基础补全、格式化、Tree-sitter 着色、诊断、紧凑悬浮、定义/引用和层级结构；输入触发、snippet、参数/导入编辑及高级编辑仍待接入 |
| F8 快速修复与重构 | quick fix、代码动作、Flutter wrap/remove/布局辅助、extract method/widget、跨文件 rename、实现/类型/调用/继承导航、符号搜索 | 仍待接入。必须先建立多文件预览、修订/权限/冲突校验、应用/失败恢复及撤销策略；不能绕过脏缓冲直接写磁盘 |
| F9 项目、SDK 与依赖 | 创建 app/package/plugin/module、项目结构、assets/fonts、依赖源码和版本、完整 Pub workspace、FVM/多 SDK、doctor、配置迁移与恢复 | 已有显式 SDK 路径、最近父包发现、Pub 增删/升级/过期、解析版本和只读依赖源码；新增显式 Doctor。创建向导、多 SDK 路由、workspace、模板/资源辅助及更完整依赖图仍待接入 |

编辑器首版仍只运行在 macOS / Apple Silicon。Flutter 项目的构建/设备平台由用户所选 SDK 和外部工具链决定；不能由 HyCode 有一个按钮推定所有平台或 SDK fork 兼容。外部 SDK 不随应用分发，也不自动安装、升级或切换版本。

## 实施依赖与验收

1. 先接通 F1–F4 的受控进程、DAP、保存/关闭与取消，再完善 F5/F6。build 26 属于该链路的首批实现，真实 Flutter 应用流程仍未运行。
2. F7/F8 先完成当前文档的编辑/补全事务，再实现多文件事务；跨文件修改必须能展示具体结果并在冲突时保留缓冲。自动导入、快速修复和重命名共享同一事务所有者。
3. F9 项目模型贯穿全部功能；切换包/SDK 立即失效旧元数据，运行快照固定实际包根、入口和配置；后台操作不能跟随随后点击的另一个包。
4. 每项分别记录实现、纯模型/协议验证、真实窗口、真实 Flutter 项目/设备、平台/SDK 兼容与性能。所有测试仍只静默执行：不启动 Flutter GUI、模拟器、浏览器，不操作桌面/剪贴板，不借用户原项目测试。CLI fixture 可模拟协议；显式 SDK 探针只运行生成的 Dart 控制台样本，不把它算作 Flutter 调试验收。
5. 运行/测试/构建由产品中的明确按钮触发；打开项目、保存普通文件或显示面板不自动启动应用/设备。保存后热重载仅作用于用户已启动的当前会话，且须单独启用。SDK 命令可能更新工具缓存；依赖安装通过独立 Pub 入口协调清单。

完整闭环仍包括缺 SDK、离线、SDK 不支持、构建错误、运行异常、取消/崩溃、项目关闭、SDK/包切换、脏缓冲、外部修改、过期响应、连续保存、IME/撤销和资源负载。真实窗口和设备验收目标保留，当前静默规则下无法执行的部分继续标明未验证。

## 协议依据

使用 [Flutter SDK DAP](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/debug_adapters/README.md)、[Dart 3.11.5 DAP](https://github.com/dart-lang/sdk/blob/3.11.5/third_party/pkg/dap/tool/README.md)、[DAP 规范](https://microsoft.github.io/debug-adapter-protocol/overview) 和 [package:test JSON reporter](https://github.com/dart-lang/test/blob/master/pkgs/test/doc/json_reporter.md)。本地 SDK/fork 的实际兼容性独立验证；不复制上游实现或其他私有产品源码。
