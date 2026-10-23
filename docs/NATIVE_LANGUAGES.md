# Swift / Java / SQL 工具

更新：2026-10-23，build 38。原生 TextKit/Rust 继续拥有文档、撤销和保存；语言服务只接收有界协议投影。HTML 已有 Web 语义服务，Markdown/HTML 的左右预览另见[分屏预览](MARKUP_PREVIEW.md)。本页记录首批语言能力，不宣称完整 IDEA 框架、数据库或 Xcode 功能。

## 使用与支持范围

| 语言 | 当前能力 | 环境与限制 |
| --- | --- | --- |
| Swift | Tree-sitter 高亮；SourceKit-LSP 诊断、补全、悬浮、定义/类型/实现/引用、结构、格式化和服务返回的文本动作/重命名预览 | 外部已安装 SourceKit-LSP；当前验证 Swift 6.4。自动发现 Xcode 默认工具链或在编辑设置填写可执行文件。SwiftPM 使用真实项目模型，Xcode 项目需兼容 BSP 服务与现有 buildServer.json |
| Java | Tree-sitter 高亮；JDT LS 诊断/Javadoc、补全、定义/引用、结构、格式化、整理导入及文本重命名/代码动作预览 | 外部 JDK 21+ 与 Eclipse JDT LS；设置 JAVA_HOME 和含 plugins/config_mac 的服务目录。委托 JDT LS 导入独立文件、Maven、Gradle 或 Eclipse 项目，不捆绑 JDK/服务或自动安装 |
| SQL | Tree-sitter 高亮；离线语法检查、保留注释/字面量的格式化、项目 CREATE TABLE 的表/字段补全、说明、结构、定义/引用 | 通用、PostgreSQL、MySQL、SQLite、SQL Server、DuckDB、BigQuery、Snowflake、ANSI；编辑设置选择方言。没有数据库连接、执行或在线 Schema 查询 |

Swift 和 Java 按当前工作区分别显式信任。信任后 SwiftPM/BSP/Maven/Gradle 可以读取项目配置、准备或编译目标、解析依赖并运行构建脚本；信任默认关闭，缺少工具不安装，不调用可能弹安装提示的系统 Java 占位命令。SQL 内置离线解析不需要项目执行信任。设置提供状态、工具路径与重启；取消信任/切项目会停止所属进程和旧任务。

打开项目后单次后台扫描 Swift/Java/SQL。信任已建立且工具存在时，即使文件未打开也进入检查；编辑同步增量，文件监听通知服务并重新发现变化源。SourceKit 和 JDT LS 自己管理项目依赖和关联文件，HyCode 不用同名搜索冒充语义引用。左下角错误/警告/建议与统一问题面板包含三种语言；点击定位复用现有文档导航。编辑菜单沿用工作台样式、现有下划线/中键/⌘点击/⌘B、补全和修改预览流程。

Java 整理导入优先使用标准 CodeAction 文本编辑；兼容命令只允许固定的 `java.edit.organizeImports`，参数限定当前已同步文件；客户端声明 workspace/applyEdit=false，结果作为文本修改预览。任意服务命令、反向工作区写入、终端、资源创建/移动/删除不执行。其他代码动作只有返回可预览文本编辑才可应用。修改仍经过原生修订/工作区代次、授权根检查、撤销与自动保存。

## 项目模型与 SQL 边界

SwiftPM 使用应用缓存内 scratch/generated 目录、两任务参数和固定解析版本优先；后台索引启用以支持引用，真实项目的依赖准备可能较慢。Xcode 不自建解析器：仅当已有合法 `buildServer.json` 时让 SourceKit 使用外部 BSP 的编译参数。文件必须是授权根内受限普通文件，argv/languages/大小经过检查；真正执行仍在信任之后。只有 xcodeproj/xcworkspace 而无 BSP 时，状态明确说明仅有单文件语义，不能将其称为完整 Xcode 工程支持。此版不生成 buildServer.json、不安装构建服务器、不提供运行/签名或 SwiftUI 预览。

JDT LS 直接以真实 JVM 的 headless 模式运行，自己的 Eclipse 缓存位于项目根之外；物理路径/符号链接检查也拒绝根与缓存相同或缓存落入项目。导入完成 `ServiceReady` 后才同步源文件，180 秒未就绪会报告失败，可在设置重启。配置启用 Maven/Gradle 导入与自动增量构建，限制并发构建、JVM CPU 和内存；大型真实工程及外部插件兼容没有验收。此版不提供 Java 应用运行/调试、Gradle 任务树、框架专用向导或反编译源码。

SQL 的分析器是语法解析器，不是数据库编译器；合法语法不代表字段存在、类型正确或 SQL 能在目标数据库执行。Schema 来自当前受限扫描内的 `CREATE TABLE`（含未保存缓冲），不执行迁移。表/列/别名按 AST 的 FROM/JOIN 绑定，未知、歧义、CTE、派生表等未支持作用域不猜测目标。PostgreSQL 的未引号名称按小写折叠，ANSI/Snowflake 按大写；依赖数据库排序规则的其他方言按精确拼写保守匹配。复合带引号表名暂不提供补全/导航，避免丢失组件引号后插入错误名称。补全尚无完整光标上下文过滤，项目重复/复杂 Schema 可能得不到导航。SQL 重命名/跨文件重构未提供。

## 所有权、预算与取消

- 项目模型检查、目录发现、文件读取、进程协议、解析和索引均离开 UI。一个元数据扫描/文件监听所有者，Swift、Java、SQL 各自一个服务所有者；活跃文档同步不等待全项目扫描。
- 发现最多 50,000 条目、2,000 源文件、总计 32 MiB；隐藏/VCS/依赖/构建目录与符号链接跳过，UTF-8/BOM UTF-16 有界解码。Swift/Java 每文件语义限 1 MiB，SQL 限 256 KiB；超出仍可基础编辑，分析状态标为受限。
- 单 URI 至多 1,000 条诊断、项目 2,000 URI/10,000 条；诊断解析一个工作任务，最多 32 URI 排队，同 URI 合并最新 ticket。修订、服务代次及文档身份不匹配则丢弃；文件删除/关闭释放票据，旧扫描错误不会覆盖新工作区。
- SQL 最多 30,000 token、48 层分隔符、512 结构复杂度、64 层解析递归；专用单线程/单等待槽，16 MiB 栈拥有 AST 解析/遍历/析构。单次同步 FFI 不能中途抢占；入场/离场检查取消且遵守上述预算。格式化重新解析验证结构等价，保留原始字面量、标识符和注释；不会把关键字大小写重写误用于非保留名称。
- SQL Schema 投影至多 10,000 目标、补全 1,000 项、引用 2,000 项/100,000 次访问。没有第二份可写编辑器，协议文本只为分析，停止时释放。
- 进程、连接、服务缓存由当前所有者回收；JDT stdio 清除继承的 socket/JVM 注入选项。协议 URI 在真实服务路径与客户端原路径间转换，不替换正文或 newText。崩溃/缺工具显示原因，不自动循环重启。

## 源码与验证

| 入口 | 职责 |
| --- | --- |
| [NativeLanguageServer.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/NativeLanguageServer.swift) | SourceKit/JDT stdio、初始化/信任、修订、就绪、已知文本动作、停止 |
| [NativeProjectModel.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/NativeProjectModel.swift)、[NativeLanguage.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/NativeLanguage.swift) | 工具发现与项目模型检查 |
| [NativeSourceCatalog.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/NativeSourceCatalog.swift)、[NativeLanguageURIs.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/NativeLanguageURIs.swift) | 源文件预算、读取、协议路径身份 |
| [SQLLanguageService.swift](../packages/HyCodeWorkspace/Sources/NativeLanguages/SQLLanguageService.swift)、[sql.rs](../crates/hycode-core/src/sql.rs) | SQL 会话、DDL/引用投影、解析/格式化与窄 FFI |
| [NativeCodeController.swift](../app/macos/Sources/NativeLanguages/NativeCodeController.swift)、[NativeToolsController.swift](../app/macos/Sources/NativeLanguages/NativeToolsController.swift) | 原生同步、分析调度、单诊断队列、设置/问题入口 |
| [NativeLanguageTests.swift](../packages/HyCodeWorkspace/Tests/NativeLanguageTests.swift)、[语言探针](../tools/NativeLanguageProbe/main.swift) | 无 GUI 回归与真实外部服务临时样本 |
| [BSP fixture](../tools/fixtures/swift_bsp.py) | 自有只提供编译选项的 stdio fixture，无目标构建/运行命令 |

验证只使用生成的临时项目、独立缓存和低并发后台进程。真实 SourceKit、BSP fixture、JDT LS 独立文件/Maven 的协议检查分别记录，不使用用户项目。Gradle/Eclipse 真工程、真实 Xcode 工程/BSP 提供方、窗口补全/悬浮/跳转/修改应用、IME 和性能未验证；不把 CLI 协议成功称为 GUI 验收。依赖版本、原始通知与源码校验见[依赖](DEPENDENCIES.md)、[机器台账](../third_party/native-language-crates.json)和[ADR 0012](adr/0012-native-languages.md)。

本批全量静默检查通过 217 项 Swift（40 组）/25 项 Rust/4 项 Node；9 项原生语言 Swift 测试另通过 Address Sanitizer，Rust 静态库和系统框架未插桩。真实 SwiftPM、BSP 编译信息及索引 fixture、Java 独立文件/Maven 样本通过诊断、未保存修改清错、悬浮、定义/引用、补全、结构、格式化和重命名文本预览；Java 标准整理导入编辑也通过。BSP fixture 的索引仅由自有库 swiftc -typecheck 准备，没有构建或运行应用。Maven 初次空离线仓库失败，改为自有隔离仓库解析标准插件后通过，未使用用户 Maven 缓存。首次网络准备需时，Java 就绪等待为可取消的 180 秒。

Release 本地开发包为 0.1.0 / build 38，arm64，未启动/安装/发布；包内原始通知与台账逐字节校验通过。源码、日志和产物哈希见[本批证据](evidence/2026-10-23-build38-native-languages.json)。

显式外部服务验证入口（先构建 Rust 内核，只使用探针生成的样本）：

```sh
swift run --jobs 2 HyCodeNativeLanguageProbe swift
swift run --jobs 2 HyCodeNativeLanguageProbe swift-bsp
swift run --jobs 2 HyCodeNativeLanguageProbe java "$HYCODE_PROBE_JAVA_HOME" "$HYCODE_PROBE_JDTLS_ROOT"
swift run --jobs 2 HyCodeNativeLanguageProbe java-maven "$HYCODE_PROBE_JAVA_HOME" "$HYCODE_PROBE_JDTLS_ROOT"
```

Java 两条命令需先将任务专用变量设为已有工具目录，不下载或安装 JDK/JDT。Maven 探针会联网解析自有样本的标准构建插件，使用 ignored `.build/native-probe-maven-home`，其余探针使用临时隔离 HOME；通用检查不会调用这些入口。BSP 探针只对生成的库执行 typecheck 以准备索引，始终不构建或运行应用。
