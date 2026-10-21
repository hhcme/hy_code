# 行号与语法高亮

更新：2026-10-21，build 23。当前新增原生逻辑行号和后台 Tree-sitter 着色；本页记录着色链路及 build 23 的滚动修正。build 24 另已接入 Dart/Flutter 首批诊断、补全、定义与引用，见 [Dart/Flutter 工具](DART_FLUTTER.md)；Web、Rust、C/C++ 语义服务仍待实现，不能将各语言着色统称为语义检查完成。

## 当前行为

- 行号默认开启，固定在文本左侧，只绘制可见逻辑行；软换行的后续视觉行不重复编号，空文档和末尾换行保留对应行号，当前行号较亮。
- 高亮默认开启，覆盖 Dart、JavaScript/JSX、TypeScript/TSX、HTML、Vue、CSS、JSON、YAML、TOML、C/C++、Rust；`.h` 默认按 C，其他未知扩展名按普通文本。尚无手动语言选择、SCSS/LESS 或 Markdown 语法包。
- Vue/HTML 的可见 script、style 正文按语言解析，支持 JS/JSX、TS/TSX、CSS；Vue 插值按 TypeScript 解析。尚不支持完整 Vue 模板语义、指令表达式的嵌入着色及其他预处理器。超过嵌入块预算时保留外层着色。
- 深浅主题采用项目自己的配色，未复制 JetBrains 或其他编辑器的主题、图标或实现。设置可分别关闭行号、高亮，并持久化偏好。
- 着色使用 NSLayoutManager 临时前景属性，不写入正文、不创建撤销记录、不改变脏标记或触发保存；输入法组合期间暂停应用新颜色。编辑、主题和开关清除过期颜色；隐藏标签取消请求，滚动保留当前修订的已着色区域。

## 所有权与性能边界

Rust TextDocument 继续独占正式文本与修订。它附带可丢弃的 SyntaxState，拥有解析器和旧语法树，不复制第二份正式文本；编辑以 UTF-8 字节/Point 更新旧树，下一次可见范围请求才增量解析。没有编辑的滚动复用旧树。语法定义/查询来自固定 crate，由后台共享只读缓存持有。

Swift 只向同一后台文档 actor 请求修订绑定的 UTF-16 视口及相邻范围；请求票据、文档修订和组合状态全部匹配才应用结果。滚动加入同一工作任务，不反复取消计时或作废在途结果；结果先保留并应用，再重新读取最新视口，没有滚动事件队列。单次完成后至多等 16 ms 再检查新范围；编辑仍保留 70 ms 合并等待。隐藏标签取消任务，关闭后旧结果失效。Task 取消会在进入 actor 的 FFI 前再次检查，不能抢占已进入 FFI 的同步解析，需等待其协作预算返回。

当前着色限制为 1 MiB 解码后 UTF-8，超过时仍可按既有 8 MiB 编辑上限编辑；单次可见范围至多 65,536 UTF-16 单位，合并结果至多 4,096 条。语法包首次查询初始化单独缓存，解析/捕获使用 100 ms 协作预算；嵌入正文每块至多 256 KiB，嵌入遍历也有节点及总时间限制。预取失败会缩小为实际可见范围再试一次；仍失败时保留已着色区域，并显示原因。失败期间若视口已变化且未缓存，继续处理新范围，同一失败范围不自动循环重试；不截断正文、不把 Tree-sitter 错误节点当正式编译诊断。状态栏语言提示可查看高亮暂停/失败原因。

原生行号使用 UI 输入投影的 UTF-16 行索引，不拥有文本。初始索引在文档 actor 建立，编辑只扫描替换片段和前后邻接单位以修正 CRLF。行起点按至多 512 条分块保存，小编辑重建边界及相邻块并均衡合并、移动后续块基址；可见行查询二分定位。它不要求每次输入重新扫描整篇正文或逐个更新所有后续行。

build 23 在视口两侧各预取一屏（每侧 1,024–4,096 UTF-16 单位，仍服从总范围上限），只读取端点单位调整 Unicode 边界。保留至多 8 个已着色窗口及覆盖元数据；命中缓存不重新查询或清色，淘汰时只清除没有被其他保留窗口覆盖的部分。颜色仍只存在于原生临时属性，不缓存第二份正文。后台状态测试覆盖连续滚动合并、预取命中、覆盖拼接、重叠淘汰、编辑/隐藏取消票据和错误后追最新范围；生成的 4,000 行 Dart 临时文件另检查远处视口返回颜色及保存不变，不使用用户项目。本轮 11 项视口/高亮测试另通过 Swift ASan；结果与限制见[后台记录](evidence/2026-10-21-build23-syntax-viewport.json)。

以上为资源约束和实现方法，不是实机输入/滚动帧率结论。语法包完整语言版本兼容、大文件复杂语法及真实窗口效果继续单独验收。

## 行号绘制修正（build 22）

用户报告行号可见但正文空白。源码确认行号栏直接填充系统传入的重绘矩形，没有限制到自身边界；新 SDK 下该矩形可能越界，背景可能覆盖正文或相邻视图。现在启用 `clipsToBounds`，所有背景和标签绘制另按 `bounds ∩ dirtyRect` 裁剪，并恢复图形状态，避免影响后续文本绘制。行为依据见 [Apple macOS 14 AppKit 发布说明的 NSView 部分](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14)。

新增 3 项纯 CoreGraphics 离屏像素测试，覆盖超大重绘范围、局部重绘、无效/无交集范围及裁剪状态恢复；另通过 Swift Address Sanitizer。测试不启动 AppKit 窗口宿主，不能代替原生行号、正文和标签在真实窗口中的显示验收；本次截图症状的实际恢复仍未窗口验证。

## 依赖与来源

Tree-sitter 0.27.1 及 12 个语法 crate 固定在 [Cargo.toml](../crates/hycode-core/Cargo.toml) 和 [Cargo.lock](../Cargo.lock)。Dart 使用 nielsenko/tree-sitter-dart 0.2.0，Vue 使用 jamie8johnson/tree-sitter-vue 的 tree-sitter-vue-next 0.1.0，二者都是社区语法，不是官方分析器。其余语法及传递依赖、版权和原文许可见[第三方通知](../THIRD_PARTY_NOTICES.md)；37 项锁定 crate 中双许可选择 MIT，foldhash 为 Zlib，保留 Unicode 及嵌入组件通知。没有新增外部 Swift 包。

参考：[Tree-sitter 高亮](https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html)、[解析器](https://tree-sitter.github.io/tree-sitter/using-parsers/)、[Apple 临时属性](https://developer.apple.com/documentation/appkit/nslayoutmanager/addtemporaryattributes(_:forcharacterrange:))。采用决定见 [ADR 0004](adr/0004-line-numbers-syntax.md)。

## 源码与验证

| 入口 | 职责 |
| --- | --- |
| [syntax.rs](../crates/hycode-core/src/syntax.rs)、[syntax_language.rs](../crates/hycode-core/src/syntax_language.rs) | 语言、查询缓存、增量树、嵌入正文、可见范围及预算 |
| [document_ffi.rs](../crates/hycode-core/src/document_ffi.rs)、[C 头文件](../bindings/CHyCodeCore/include/hycode_core.h) | 串行后台文档句柄、UTF-16 请求与结果释放 |
| [TextLineIndex.swift](../packages/HyCodeWorkspace/Sources/TextLineIndex.swift) | 分块行索引及 CRLF/Unicode 增量 |
| [EditorLineRuler.swift](../app/macos/Sources/Editor/EditorLineRuler.swift) | 原生可见行号、软换行位置与当前行号 |
| [EditorGutterDrawing.swift](../packages/HyCodeWorkspace/Sources/EditorGutterDrawing.swift)、[像素测试](../packages/HyCodeWorkspace/Tests/EditorGutterDrawingTests.swift) | 行号绘制边界裁剪、绘制状态恢复及纯 CoreGraphics 回归 |
| [EditorPresentation.swift](../app/macos/Sources/Editor/EditorPresentation.swift) | 请求失效、视口调度、临时颜色与主题 |
| [SyntaxViewportState.swift](../packages/HyCodeWorkspace/Sources/SyntaxViewportState.swift)、[调度测试](../packages/HyCodeWorkspace/Tests/SyntaxViewportStateTests.swift) | 单工作任务票据、范围预取、有界覆盖缓存和重叠淘汰 |
| [NativeTextEditor.swift](../app/macos/Sources/Editor/NativeTextEditor.swift) | 输入原语增量、窗口挂载和既有 Undo/IME |
| [syntax_tests.rs](../crates/hycode-core/src/syntax_tests.rs)、[SyntaxHighlightTests.swift](../packages/HyCodeWorkspace/Tests/SyntaxHighlightTests.swift)、[TextLineIndexTests.swift](../packages/HyCodeWorkspace/Tests/TextLineIndexTests.swift) | 语法/增量/嵌入边界、桥接与行索引后台测试 |

测试仅使用生成文本和临时文件。覆盖 20 万行 CRLF 跨块编辑、600 次随机 Unicode 编辑与完整重建对照，以及文首连续插入 2,000 次、删除 1,500 次的索引占用回归；新增 7 项 Swift 行索引/高亮桥接测试另通过 ASan（Rust/C 静态库未插桩）。原生行号像素、软换行绘制、滚动/主题、颜色清理、IME/Undo 及真实输入性能未通过窗口测试；本轮不启动应用、操作用户桌面或剪贴板。后台检查与开发包哈希记录在[工作台](WORKBENCH.md)。
