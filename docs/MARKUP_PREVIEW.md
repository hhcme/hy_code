# Markdown 与 HTML 左右预览

更新：2026-10-23，build 40（build 37 首次接入）。Markdown / HTML 在同一文本会话中提供源码、左右分屏、仅预览三种模式，默认左右。Swift、SQL、Java 的当前范围见[完整目标](LANGUAGE_EXPANSION_PLAN.md)与[语言工具](NATIVE_LANGUAGES.md)。

## 交互与资源

支持 `.md`、`.markdown`、`.mdown`、`.mkd`、`.html`、`.htm`。左侧沿用原生 TextKit、Rust 正式缓冲、撤销和自动保存，右侧使用系统 WebKit，只读且不执行页面 JavaScript。可拖动比例（20%–80%，结束后记忆）、切换模式、重载与开关滚动联动；源码未保存更改合并 180 ms 后投影，不等待磁盘保存。Markdown 按块起始行近似联动，HTML 按滚动比例联动；不是任意复杂布局的精确逐行映射。仅预览或关闭联动后重载保留阅读位置。真实窗口交互尚未验证。

Markdown 由固定 pulldown-cmark 0.13.5 生成 HTML，覆盖标题、段落、列表、表格、任务、删除线、脚注、链接和代码块；当前代码块没有独立语法着色。HTML 保留自身静态布局和 CSS，可使用当前授权根内的相对 CSS / 图片。图片经过现有受限 ImageIO/resvg 解码并输出 PNG，只显示首帧，不允许浏览器加载原始 SVG 的外部资源。

右侧不是网站运行器。脚本、开发服务器、表单提交、嵌套页面、远程链接跳转、媒体和字体不加载；不调用外部浏览器。`data:`、远程 URL、文件 URL 与授权根外资源不支持。单文件授权只能读取已授权内容，不因预览扩大父目录权限。资源失败数量和渲染错误显示在工具栏，不自动授权、下载或执行项目代码。

## 所有权与边界

`EditorDocument` 拥有 `MarkupPreviewController`；切走标签、仅源码或关闭时取消在途任务、停止加载、移除脚本/滚动观察并释放 WebView。Rust 在正式文档的期望修订上只读生成投影，不建立第二个可写文本。FFI 沿用 ABI 1 的 owned-buffer/free、panic 隔离与错误模型；Swift actor 串行拥有文档，取消和修订在 await 前后检查，旧代次结果丢弃。

资源使用每次加载私有 `hycode-preview://` 身份和原生授权读取；路径校验、目录描述符、拒绝链接/FIFO/越界、读前读后版本保护均在后台执行。资源 loader actor 串行读取/解码。预览专用 CSP 禁用脚本/网络等，页面 JavaScript 开关关闭；加载前安装覆盖 HTTP/HTTPS/WS/WSS/FTP 的 WKContentRuleList，拦截预连接、DNS 预取等路径。规则准备失败则不创建预览。只有自有固定滚动脚本运行于独立内容世界；不把源码拼接进脚本，也不提供磁盘/命令桥接。

| 资源 | 上限 |
| --- | --- |
| 完整预览源码 / 输出 HTML | 32 MiB / 64 MiB |
| Markdown 解析器构造前结构标点 / CR/LF 字节 | 65,536 / 100,000 |
| Markdown 事件 / 嵌套 / 块标记 | 100,000 / 128 / 8,192 |
| 单页排队请求 | 256，实际 I/O / 解码串行 |
| CSS / 图片原始字节 | 1 MiB UTF-8 / 8 MiB |
| 图片投影边长 / 单张 PNG | 4,096 px / 32 MiB |
| 单页交付总量 / 解码像素累计 | 64 MiB / 32,000,000 px |

这些是资源防护，不是 CPU、RSS 或帧率验收。系统读取/解码中的取消为协作式；180 ms 合并不代表端到端延迟。

## 源码与验证

- `crates/hycode-core/src/markup.rs`、`document_ffi.rs`：受限渲染、源行、修订及 ABI。
- `packages/HyCodeWorkspace/Sources/Markup/`：格式、页面策略、资源预算和后台读取；`Tests/MarkupPreviewTests.swift` 为无 GUI 用例。
- `app/macos/Sources/Markup/`：原生分栏、WebKit 适配、固定滚动桥与生命周期。
- [ADR 0011](adr/0011-markup-preview.md)、[依赖台账](DEPENDENCIES.md)、[第三方通知](../THIRD_PARTY_NOTICES.md)。

后台验证：6 项 Swift 预览测试、3 项 Rust 渲染/修订/FFI 回归，涵盖 Unicode/BOM/换行、未保存快照、预算、取消、私有路径、链接/FIFO拒绝、图片和 CSS；6 项 Swift ASan 通过，Rust 静态库和系统框架未插桩。全量 208 Swift / 22 Rust / 4 Node 检查通过；应用参与编译，不实例化 WKWebView、运行内容规则引擎或执行 GUI。窗口、WebKit 实际布局/网络阻断/滚动、IME/焦点/键鼠与性能仍未验证。构建及源哈希见[阶段证据](evidence/2026-10-23-build37-markup-preview.json)。

## build 39：规则编译失败修复

用户窗口中的 `WKErrorDomain 6` 对应内容规则编译失败；原规则 `^(https?|wss?|ftp)://` 使用了 WebKit 内容规则不支持的分支。通用 ICU 正则测试通过并不能证明 WebKit 子集兼容。现在使用 HTTP/HTTPS/WS/WSS/FTP 五条独立纯协议前缀，升级规则标识到 v2；不限制资源分类，成功安装规则后才创建预览，CSP、页面脚本关闭与原生资源边界保持有效。错误提示优先显示 WebKit `NSHelpAnchorErrorKey` 中的实际编译原因，并限制长度。

新增 [HyCodeMarkupRuleProbe](../tools/MarkupRuleProbe/main.swift) 是同步 Foundation CLI，仅创建自有临时 `WKContentRuleListStore(url:)`、编译固定旧/新 JSON 并删除临时存储；使用原生编译器复现旧规则的相同错误，再断言当前生产规则编译成功。已核对[WebKit API 编译路径](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/APIContentRuleListStore.cpp)：仅 JSON 解析、后台编译和文件映射，无应用宿主、WebView、页面加载、网络或用户默认缓存。该 CLI 纳入通用静默检查；不运行规则匹配/网页布局/窗口测试。

兼容依据：[WebKit URLFilterParser 的 disjunction 拒绝](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/URLFilterParser.cpp)、[Apple WKError 定义](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKError.h)。此修复的后台编译验证不等同于真实预览窗口验收。

本批 7 项预览 Swift 回归、全量 218 Swift / 25 Rust / 4 Node 与原生规则编译回归通过；Release 本地包 0.1.0 / build 39 已构建但未启动。没有执行页面加载或网络匹配，真实窗口恢复仍待验证。源码、日志及包哈希见[修复证据](evidence/2026-10-23-build39-markup-rules.json)。

## build 40：大文件与预览分层

旧 1 MiB 文本门槛已调整；先做结构密度预检，后台取消，不在解析器建树后才依靠事件预算拒绝密集 Markdown。预览失败显示工作台占位，避免空白页；更大源码使用[磁盘分段编辑](LARGE_FILES.md)，完整预览仍受独立预算约束。大文件页的滚动不与完整预览伪造联动。此改动不放开 data URL、远程资源或脚本。
