# ADR 0007：原生 Web 多语言服务与修改预览

- 状态：首批采用；真实窗口、项目脚本和完整 Web 工具待验证/实现
- 日期：2026-10-22
- 范围：[Web 开发工具](../WEB_TOOLS.md)

## 背景与决策

用户要求补齐 Web 开发能力。保留 Swift/AppKit 编辑视图、Rust 正式文本和原生 UndoManager，不另建 WebView 编辑器。通过外部 Node 调用包内固定的公开 TypeScript/Vue/HTML/CSS/JSON 服务，按工作区惰性启动，复用现有 stdio、UTF-16、取消和进程组所有权。

`EditorLanguageController` 是编辑交互协议，Dart 与 Web 拥有独立服务和诊断。Vue 同时同步到 TS 和 Vue 服务，转发固定 tsserver 隧道；解析 completion/codeAction 时带回服务来源。诊断保留不透明 data，不能丢弃 Vue provider 的版本/插件信息。阻塞读写等待使用 utility/串行队列，避免占满 cooperative executor。

仅打开目录不执行项目 scripts 或安装依赖。Vue 配置可能 require 项目插件，默认不注册 Vue 插件；需用户在 Web 分析面板显式信任当前工作区，变更信任会关闭旧服务后重启。Node 路径可配置，不复制维护者 Node 或本地 IDE 内容。

## 文本与工具事务

自动导入先 resolve 补全项，再校验主编辑和附加编辑。支持有界基础 snippets，Tab/Shift-Tab 移动字段，不声称支持变量解析器、转换或镜像同步。

重命名与代码动作限工作区内已有本地文件的文本修改，先展示具体差异。请求和预览准备绑定全工作区编辑代次；未同步的脏目标拒绝应用。应用前验证文档 ID/修订/权限，然后交回原生文本与保存流程。每文件可撤销，不保证跨文件磁盘原子写入。创建/删除/改名文件等 resource operations、任意命令式重构另行设计。

包任务读取最近 package.json；显式执行前保存缓冲并保护清单/锁文件，重新检查包管理器与所选脚本，保留停止和有界输出。命令使用参数数组；依赖操作禁用生命周期 hooks，scripts 只在用户点击后执行。Yarn 1 与 4+ 分别处理，2/3 与 Yarn 4 outdated 明确提示未支持。

## 依赖、资源与验收

固定版本、106 项传递依赖和通知见 [依赖台账](../DEPENDENCIES.md) 与 [第三方通知](../../THIRD_PARTY_NOTICES.md)。来源、integrity 与通知检查进入构建；缺失上游许可原文的情况明确保留，不补造声明。

语义输入限制为 1 MiB/文档；服务 Node old-space 为每进程 512 MiB，最多五类惰性连接，不表示实际内存预算已达标。诊断/补全/编辑有数量和文本上限。模型测试和真实固定服务探针只使用生成 fixture；原生预览、输入/IME/撤销、用户项目运行、真实性能、签名与分发仍单独验收。完整 Web 调试、测试/覆盖率与更多框架不由本 ADR 自动视为完成。
