# JSON 与 YAML 配置工具

更新：2026-10-23，build 36。首批接入 JSON/JSONC、YAML/YML 的检查、格式化和常用编辑能力；沿用原生文本、撤销、自动保存与问题面板。需要用户安装的外部 Node 22.22.2+。没有 Node 时基础编辑和已有 Tree-sitter 着色仍可用，语义服务提示实际失败，不把空诊断当成通过。

## 当前能力

| 格式 | 能力与限制 |
| --- | --- |
| JSON | 严格语法诊断、Schema 类型/必填/枚举检查、字段补全与说明、结构、格式化；尾逗号报错 |
| JSONC | 注释可用；固定上游服务将尾逗号标为警告而非语法错误。`.jsonc`、`tsconfig.json` / `tsconfig.*.json` / `jsconfig.json` / `jsconfig.*.json`，以及 `.vscode/` 内的 settings/tasks/launch/extensions.json 使用 JSONC 服务模式 |
| YAML/YML | YAML 1.2 语法、重复键、Schema 检查、字段补全/说明、结构、格式化、锚点定义与锚点重命名预览；快速修复仅显示服务实际返回的文本动作 |

例如 `tsconfig.json`、`tsconfig.app.json` 和 `jsconfig.json` 使用 JSONC；普通 `data.json` 保持严格 JSON。当前名称识别按文件名，不尝试推断所有自定义配置方言。

错误/警告/建议沿用编辑区诊断装饰与左下角计数，可点击问题定位。结构在已有结构工具中显示；Ctrl-Space 显式补全，格式化使用现有代码菜单、右键或 ⌥⌘L。YAML 的 ⌘B / ⌘点击 / 中键用于服务可解析的锚点定义；不把它描述成任意配置值都有引用关系。菜单只展示配置服务已有入口，不提供无意义的 TS 导入整理、类型实现或参数菜单。没有自动弹出的补全列表。

格式化由服务返回文本编辑，检查文档修订后进入原生撤销和自动保存，不把 JSON 解析为 JavaScript 数字再序列化。真实协议样本检查注释、YAML 锚点和 `900719925474099312345` 数字原文保留，不由单个样本推导所有方言无损。

## 离线规则与项目规则

四组常用文件关联固定的 SchemaStore 原始数据：

| 文件 | 规则 |
| --- | --- |
| package.json | npm 清单类型与字段 |
| tsconfig.json、tsconfig.*.json、jsconfig.json、jsconfig.*.json | TypeScript / JavaScript 项目配置 |
| .github/workflows/*.yml / *.yaml | GitHub Actions workflow |
| pubspec.yaml / pubspec.yml | Dart / Flutter Pub 清单 |

四个入口及十个传递引用共 14 个文件，固定在 SchemaStore commit `4b9347599acb42276483fc514f641505e205d331`。来源、原字节 SHA-256、关联和许可哈希见 [catalog.json](../tools/web-language-services/schemas/catalog.json)；原始 Apache-2.0 LICENSE 与 NOTICE 随包保留，见[第三方通知](../THIRD_PARTY_NOTICES.md)。校验 Schema 不等于运行 npm、Pub、GitHub Actions 或构建，也不是持续联网更新的完整 SchemaStore 目录。

JSON 可用 `"$schema": "./schema.json"`，YAML 可用 `# yaml-language-server: $schema=./schema.json` 指定项目内 JSON Schema；相对引用和传递引用由对应服务解析。文件名可以使用其他扩展名，内容仍必须是服务理解的 JSON Schema。保存规则文件或收到外部文件事件后通知服务清除相关缓存并检查依赖文档；手动全量重查包括已观察但已删除、曾读取失败的路径。未保存规则缓冲暂不作为依赖 Schema 的数据源，关闭自动保存后需保存规则文件。

未知远程 Schema、项目外路径、被排除目录、链接或特殊文件会明确报错，不静默联网兜底。SchemaStore 只有已随包固定的 URI 可映射到本地字节；SchemaStore 目录下载和 Kubernetes CRD 在线目录均关闭。尚无自定义关联设置界面、联网下载开关、完整 Kubernetes/Docker Compose 规则库、JSON5/TOML/XML 语义服务；这些不能列为已实现。TOML 现有基础着色保持独立。

## 线程、读取与预算

- `WebLanguageServer` 为工作区惰性拥有 JSON/YAML 独立 stdio 进程；Node 每进程 old-space 上限 512 MiB，服务解析、校验和格式化不在 UI 线程。六类服务总量及 RSS 尚未实测，不据此宣称帧率达标。
- 自有固定启动适配器注入 Schema reader。随包 Schema 由 Node 读取自己资源；项目文件 URL 只能通过 `hycode/schemaContent` 反向请求交给原生读取，不将任意 file URL 交给 Node 默认 fs resolver。
- 原生连接最多记录 500 个已观察本地 Schema URI，含失败路径；适配器最多 8 个在途本地请求。URI 最长 8192 字节，单文件最多 1 MiB。授权根内逐级 `openat/O_NOFOLLOW`、普通文件检查、UTF-8/BOM UTF-16 解码与取消复用 `ProjectSourceCatalog`，阻塞 I/O 位于 utility 任务。
- 不遍历依赖/产物或一般隐藏目录，明确允许 `.github` 和 `.vscode`。文件监听也保留非标准扩展名规则的事件；未知格式不因此注册为编辑语言或触发无关 TypeScript 全扫。扫描/诊断总预算沿用[项目分析](PROJECT_ANALYSIS.md)。
- YAML 格式化调用固定包内 Prettier standalone 与固定 YAML/ESTree 插件，不发现 `.prettierrc.js`、不加载项目插件。配置工具不自动执行项目脚本、包任务或依赖安装；已有 Vue 信任规则保持独立。

## 源码与后台验证

| 入口 | 职责 |
| --- | --- |
| [WebProject / WebToolchain](../packages/HyCodeWorkspace/Sources/Language/WebProject.swift) | 文件模式与服务路由；固定工具启动参数见同目录 WebToolchain.swift |
| [ConfigurationSchemas](../packages/HyCodeWorkspace/Sources/Language/ConfigurationSchemas.swift) | 有界离线关联、原生授权读取 |
| [StdioProtocolConnection](../packages/HyCodeWorkspace/Sources/Language/LanguageServerConnection.swift) | 反向请求、依赖记录与缓存失效通知 |
| [固定启动适配器](../tools/web-language-services/native/config-language-server.mjs) / [Schema reader](../tools/web-language-services/native/schema-runtime.mjs) | 固定上游 JSON/YAML、离线/原生读取策略 |
| [配置测试](../packages/HyCodeWorkspace/Tests/ConfigurationLanguageTests.swift) / [Node 测试](../tools/web-language-services/native/schema-runtime.test.mjs) | 路由、路径/编码/预算/取消、离线规则与远程拒绝 |
| [真实服务探针](../tools/WebProbe/ConfigurationProbe.swift) | 临时配置样本的诊断、编辑、Schema 关联与刷新 |

全量静默检查通过 202 项 Swift（38 组）、19 项 Rust 与 4 项 Node 测试；配置和 FSEvents 共 7 项 Swift 另通过 ASan，Rust 静态库未插桩。配置真实服务探针与既有完整 Web 协议回归通过，覆盖 JSONC 导入方未保存更新/关闭交接及 Schema 增量/全量刷新。日志、哈希、独立审查修复与开发包信息见[build 36 后台证据](evidence/2026-10-23-build36-configuration-tools.json)。

只使用自有临时文件和固定语言服务；没有启动 HyCode、其他 GUI、模拟器、用户项目或执行包脚本。真实窗口中的菜单/提示/下划线、输入法和项目规模性能尚未验收。构建只是本地未签名开发包，不是应用发布。

可显式静默执行配置真实协议探针（不会打开窗口）：

```bash
nice -n 10 swift run --jobs 2 HyCodeWebProbe /absolute/path/to/node tools/web-language-services --configuration
```
