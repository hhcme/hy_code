# 多语言与分屏预览目标

更新：2026-10-23。用户要求以目标模式完成 Java、SQL、Swift 支持及 Markdown/HTML 左右预览。本页保持全部目标，不将单个阶段完成描述为整体完成。基线提交为 `3fe752f`；所有测试继续遵守[静默约束](DEVELOPMENT.md)，不实例化 WebView、启动 GUI、数据库或用户项目构建。

## 必做范围

| 项目 | 完成要求 | 当前状态 |
| --- | --- | --- |
| Markdown / HTML | 同一文档的源码、左右分屏、仅预览；默认左右；可拖比例并记忆、未保存更改刷新、滚动联动开关；Markdown 标题/表格/任务/代码块/项目图片，HTML 项目 CSS/图片静态预览 | 已实现并通过后台检查；窗口未验证，见 [Markdown/HTML](MARKUP_PREVIEW.md) |
| Swift | 基础高亮；SourceKit-LSP 诊断/补全/说明/定义/引用/结构/格式化，SwiftPM 项目模型，Xcode 项目构建信息适配；工具链/失败/关闭语义 | 已实现并通过后台回归/真实服务或解析样本；窗口/工程限制见[原生语言](NATIVE_LANGUAGES.md) |
| SQL | 方言选择、高亮、离线语法检查与保留注释的格式化；基于项目 DDL/Schema 的表字段补全与导航，错误进入统一问题面板 | 已实现并通过后台回归/真实服务或解析样本；窗口/工程限制见[原生语言](NATIVE_LANGUAGES.md) |
| Java | 基础高亮；JDT LS 诊断/补全/Javadoc/定义/引用/结构/格式化/整理导入/文本重构预览，单文件及 Maven/Gradle 项目；外部 JDK/服务发现、显式项目导入信任与生命周期 | 已实现并通过后台回归/真实服务或解析样本；窗口/工程限制见[原生语言](NATIVE_LANGUAGES.md) |

语言服务按工作区独立拥有，耗时 I/O/解析/索引离开 UI，接入现有修订保护、修改预览、撤销与自动保存。缺少工具不安装或执行任意项目代码，不用同名文本搜索冒充语义引用。不以接入 LSP 宣称完整 IDEA 专用框架功能。

预览左侧保持原生 TextKit/Rust，右侧为系统 WebKit；后台渲染只使用修订绑定快照。HTML 首批是静态页面；JavaScript 运行和开发服务器属于后续独立入口，不能把静态预览称为完整 Web 应用运行。滚动映射精度及不支持项单独登记。

## 验证与完成审计

每项至少包括可核对源码、真实无 GUI 服务或解析样本、失败/取消/旧结果测试、应用编译和依赖通知；窗口交互与性能单列未验证，不因后台检查通过改写为通过。预览不得在测试中实例化 WKWebView 或运行带界面宿主。每阶段记录当前证据与剩余范围，整体目标保持活动直至各项满足可执行的实现与验证要求。

采用来源：[SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp)、[Eclipse JDT LS](https://github.com/eclipse-jdtls/eclipse.jdt.ls)、[sqlparser-rs](https://github.com/apache/datafusion-sqlparser-rs)、[pulldown-cmark](https://github.com/pulldown-cmark/pulldown-cmark)。实际版本、许可与通知见[依赖台账](DEPENDENCIES.md)。

## 本次交付

build 37 完成静态分屏；build 38 完成首批 Swift/Java/SQL 接入、上述后台要求及本地包。全量 217 Swift / 25 Rust / 4 Node、9 项原生语言 Swift ASan 和真实服务生成样本通过，见[交付证据](evidence/2026-10-23-build38-native-languages.json)。人工窗口/性能、真实 Gradle/Eclipse/Xcode 工程等限制保留在专题，不将其算作已验收。完整框架 IDE、数据库执行和 Java/Swift 运行调试不在这次首批语言接入中。
