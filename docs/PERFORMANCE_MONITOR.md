# HyCode 自身资源监控

更新：2026-10-23，build 41。底部常驻主进程内存和 CPU，点击查看详情并显式清理自身闲置语法缓存。实现、后台校验、真实窗口和系统内存回收效果分别记录；没有新增第三方依赖。

## 显示口径

| 项目 | 来源与含义 |
| --- | --- |
| 内存占用 | `proc_pid_rusage(getpid(), RUSAGE_INFO_V4)` 的 `ri_phys_footprint`，主进程物理占用，不是虚拟地址空间或整机已用内存 |
| 进程峰值 | 同一进程的 `ri_lifetime_max_phys_footprint`，清理缓存不会重置历史峰值 |
| 驻留内存 | `ri_resident_size`，与物理占用是不同口径，不相加 |
| CPU | `getrusage(RUSAGE_SELF)` 用户态与内核态累计秒数的差 / 单调时钟实际经过秒数；单核满载 100%，多线程可超过 100% |

系统 API 口径参考 [Apple rusage_info_v4](https://developer.apple.com/documentation/kernel/rusage_info_v4) 和 [XNU resource.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h)。CPU 使用 `timeval` 的秒/微秒，不将 Apple Silicon 的 Mach tick 误当纳秒。显示单位由系统内存格式化器提供。

当前仅统计 HyCode 主进程，不含独立语言服务器、WebKit 预览服务、运行目标或构建工具；详情明确标注。不能把这个读数称作整个开发会话总占用。

场景活动时每 2 秒在独立 actor 读取，窗口不活动时停止轮询，恢复时重建 CPU 间隔基线。首样本/恢复首样本/无效时间差显示 `—`；系统读取失败显示不可用和原因，不伪造零。只保留上一份计数和当前显示，没有采样历史增长、进程枚举、shell 命令或系统探针子进程。单独观察资源状态的子视图更新，计数不写入工作台 store，不驱动树/编辑器/布局重新计算。

## 清理范围与保留项

用户点击“清理自身闲置缓存”后，按原有文档 actor 顺序释放非活动普通文本的 Tree-sitter parser/tree，再移除没有活动引用的共享编译语法查询。共享 `Arc` 缓存加锁检查所有权，昂贵析构在解锁后执行；活动文档和其他请求仍持有的语法对象继续有效。下次需要时在后台重新构造。

共享清理也保护当前路径的语言：大文件临时片段及 HTML/Vue 的 JS/TS/TSX/CSS 嵌入查询即使只剩共享缓存引用，也保留供当前页面继续使用。标签激活取消尚未提交的共享清理，锁排队结束后再次检查票据。

每份排队清理带独立取消票据。标签激活/文档关闭同步使票据失效，文档 actor 真正开始执行及 Rust 缓存移除提交点再次检查；已经开始释放的缓存不回滚。取消清理不取消保存、解析或其他用户任务。

清理不会关闭标签、保存/重载原件、修改正文或修订、取消用户工作、丢弃未保存输入、清空撤销/重做、释放大文件当前页/来源描述符/历史、停掉或重启语言服务。当前文件解析缓存保留，避免清理后当场重编译。图片/视频已有切走卸载策略，本入口不销毁正在显示的媒体或 WebView。

不操作其他应用、系统缓存、磁盘目录、构建产物、用户设置或语言服务数据，不调用整机 purge、制造内存压力、分配大块内存或强制 GC。

结果展示实际清理条目数及清理前/后两次独立测量；不把条目数换算成释放字节。没有闲置条目、部分清理失败、采样不可用分别显示。分配器可能保留已释放内存供后续复用，其他正常任务也可能同时分配，读数不保证立即下降；进程峰值按定义不会下降。

## 源码和验证

- `packages/HyCodeWorkspace/Sources/Performance/`：自身资源 adapter、常量状态采样、后台共享语法缓存维护。
- `app/macos/Sources/Workbench/WorkbenchResourceMonitor.swift`、`WorkbenchResourceStatus.swift`：局部观察、活动生命周期、底栏与详情。
- `EditorWorkspace.releaseInactiveCaches`、`EditorDocument.releaseRebuildableCaches`、`NativeTextDocument.trimRebuildableCaches`：原有单一所有者串行释放，不接触文本/历史。
- `crates/hycode-core/src/document.rs`、`syntax_language.rs`、`document_ffi.rs`：缓存所有权和 additive ABI 1；返回缓冲仍逐个释放。
- `packages/HyCodeWorkspace/Tests/ProcessResourceTests.swift`、`MemoryCacheTests.swift`：纯计数、仅测试自身进程读数、未保存 Unicode/修订/保存和大文件跨页撤销保护；不创建应用宿主。

构建与本批后台结果见[证据](evidence/2026-10-23-build41-performance-monitor.json)。真实窗口布局、悬浮/点击、活动切换、CPU/内存采样开销及清理后的真实应用内存变化保留为未验收，不用 CLI 自身读数代替 HyCode GUI 性能。

build 41 全量静默检查通过：232 项 Swift（43 组）、37 项 Rust、4 项 Node，以及系统内容规则编译器/格式/静态/头文件/依赖/文档检查。新增 5 项采样/缓存 Swift 测试通过 Address Sanitizer；Rust 静态库和 Apple 框架未插桩，不据此宣称 Rust sanitizer 或 GUI 内存验收。Release 本地开发包已构建，版本 0.1.0 / build 41、arm64；没有启动、安装、签名分发、发布、提交或推送。
