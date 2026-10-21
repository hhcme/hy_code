# HyCode 依赖与来源

更新：2026-10-21。自有代码与文档使用 [MIT](../LICENSE)。当前没有应用工程、应用依赖清单或第三方语言服务二进制。

## 已采用工具与平台依赖

| 项目 | 用途 | 固定与来源 | 说明 |
| --- | --- | --- | --- |
| Python 标准库 | 本地文档检查 | Python 3.9+；[官方文档](https://docs.python.org/3/) | 不安装第三方 Python 包 |
| GitHub Actions checkout | 文档 CI 检出仓库 | 具体提交固定在[工作流](../.github/workflows/docs.yml)；[上游](https://github.com/actions/checkout) | CI 开发工具，不进入应用分发 |
| macOS SDK / 系统框架 | 首版原生宿主的平台条件 | 最低系统与 Xcode 版本待原型固定 | 平台依赖，不称为本项目开源代码；尚无应用接入 |

当前不存在需随应用分发的第三方组件，也没有将候选代码复制到仓库。旧实现的依赖锁文件已删除，Git 历史中的旧版本不代表新工程依赖。

## 研究候选

| 组件 | 拟用职责 | 状态 |
| --- | --- | --- |
| [Ropey](https://github.com/cessen/ropey) | Rust 文本缓冲 | 仅候选，版本/性能/接入待验证 |
| [Tree-sitter](https://tree-sitter.github.io/tree-sitter/) | 增量语法解析 | 仅候选，各语言语法包另审 |
| [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) | Swift 语义服务 | 仅候选，工具链及项目模型待验证 |
| [rust-analyzer](https://rust-analyzer.github.io/book/) | Rust 语义服务 | 仅候选，环境/协议/资源待验证 |
| [UniFFI](https://github.com/mozilla/uniffi-rs) | Swift/Rust 绑定 | 与窄 C ABI 共同评估，未采用 |

允许采用官方和社区开源组件，按维护方准确标注；“官方”不等于符合本项目性能与分发要求。系统框架、开源库、语言服务、语法/词库数据分别登记。

## 引入记录

实际接入前，新增一条包含以下内容的记录，并视影响补 ADR：

- 名称、上游维护方、源码 URL、固定 tag/commit 与校验值。
- 所解决的问题、使用模块、候选比较及 macOS / Apple Silicon 验证。
- 所选版本的许可、版权、通知文件、传递依赖和来源授权。
- 链接方式、运行时、系统工具链条件；随包、可选下载或使用本机已有安装分别记录。
- 文本位置、生命周期、线程、取消、错误恢复和资源预算。
- 本项目的后台测试、真实窗口及性能证据，已知限制和升级策略。

可读源码、可运行、可公开及可随包分发分别核对。第三方组件保留自身许可与通知，不能用 HyCode 的 MIT 覆盖它们，也不从私有安装包抽取二进制代替公开源码。首次引入需分发组件时，再添加真实的第三方通知清单。
