# HyCode 文档索引

更新：2026-10-28。当前已有文件工作台与基础文本编辑，后台验证与真实窗口状态分别记录。首版仅 macOS / Apple Silicon，Swift 原生界面 + Rust 内核；自有代码与文档采用 [MIT](../LICENSE)。

## 建议阅读顺序

1. [项目入口](../README.md)：定位、现状和参与方式。
2. [方向与已定事项](EDITOR_DIRECTION.md)：用户已确认与待决事项。
3. [产品需求](PRODUCT_REQUIREMENTS.md)：用户行为、状态与失败语义。
4. [技术设计](TECH_DESIGN.md)：职责和边界。
5. [开发约定](DEVELOPMENT.md)：真实命令、验证及证据。
6. 按任务阅读下列专题；有架构决策先查 [ADR](adr/README.md)。

## 任务专题

| 类别 | 文档 | 用途 |
| --- | --- | --- |
| 品牌 | [品牌与应用图标](BRANDING.md) | 系列视觉、资源来源、图标导出及验证边界 |
| 当前工程 | [文件浏览工作台](WORKBENCH.md) | 布局、交互、源码地图、构建与证据 |
| AI Agent | [内置 Codex](CODEX_AGENT.md) | 右侧多会话、自定义 Responses、运行/凭据隔离、静默验证 |
| 终端 | [本地交互终端](TERMINAL.md) | 原生标签/分屏、Shell、PTY/关闭/修改互斥和静默验证 |
| Git | [工作流与分期验收](GIT.md) | 原生提交/差异编辑/日志/分支/远端、真实索引保护、文档/任务互斥与后续范围 |
| 视觉 | [WebStorm 截图对齐](VISUAL_ALIGNMENT.md) | 像素采样、整体界面覆盖、共享控件与真实窗口验证缺口 |
| 分屏预览 | [Markdown / HTML](MARKUP_PREVIEW.md) | 原生源码、静态预览、资源限制和滚动映射 |
| 原生语言 | [Swift / Java / SQL](NATIVE_LANGUAGES.md) | 外部语义、项目模型、信任与离线 DDL |
| 语言扩展 | [完整目标](LANGUAGE_EXPANSION_PLAN.md) | Swift、SQL、Java 与预览的实施和验收状态 |
| 视频 | [简单只读预览](VIDEO_PREVIEW.md) | MP4/MOV/M4V、原生播放、分段读取、资源释放与验证 |
| 图片 | [只读预览](IMAGE_PREVIEW.md) | 多格式、缩放/平移、解码与资源限制 |
| 大文件 | [磁盘分段文本](LARGE_FILES.md) | GB 文本、字节导航、跨页撤销和完整保存 |
| 基础编辑 | [编辑与保存](EDITING.md) | 单击编辑、自动保存开关、编码与安全写入 |
| 着色与行号 | [行号与语法高亮](SYNTAX.md) | 首批语言、解析所有权、预算和验证 |
| Dart / Flutter | [开发工具](DART_FLUTTER.md) | SDK、诊断/悬浮/引用、包依赖与任务生命周期 |
| Flutter 全量范围 | [完整能力清单](FLUTTER_PLAN.md) | 已确认的九类必做能力、当前缺口、依赖与验收 |
| 项目检查 | [项目后台诊断](PROJECT_ANALYSIS.md) | 项目打开检查、关联增量、左下角计数与可跳转问题列表 |
| 配置文件 | [JSON 与 YAML 工具](CONFIGURATION_TOOLS.md) | 检查、格式化、离线 Schema、补全与安全读取 |
| Web | [开发工具与完整范围](WEB_TOOLS.md) | JS/TS/Vue/HTML/CSS/JSON 服务、修改预览、依赖/脚本与剩余能力 |
| 规划 | [实施路线](ROADMAP.md) | macOS 阶段及验收，不表示交付日期 |
| 性能 | [性能设计与验收](PERFORMANCE.md) | 样本、测量口径和预算决策 |
| 自身资源 | [底栏资源监控](PERFORMANCE_MONITOR.md) | 主进程内存/CPU、闲置缓存清理和保留项 |
| 编辑与语言 | [编辑内核与语言服务](CODE_INTELLIGENCE.md) | 缓冲、语法与语义分层 |
| 开源依赖 | [依赖与来源](DEPENDENCIES.md) | 候选、已采用组件及引入规则 |
| 能力状态 | [能力与格式台账](FORMAT_SUPPORT.md) | 已实现、各类验证及限制 |
| 工程决策 | [架构决策记录](adr/README.md) | 接受、提议与替代关系 |
| 贡献 | [贡献指南](../CONTRIBUTING.md) | Issue、PR、检查与贡献许可 |
| 安全 | [安全说明](../SECURITY.md) | 报告方式与当前支持状态 |
| 分发 | [开源与分发准备](FEASIBILITY_AND_DISTRIBUTION.md) | 源码公开、打包与应用发布分别准备 |
| 外部参考 | [HyHub 参考边界](HYHUB_REUSE.md) | 独立开发与外部代码权属 |
| 追溯 | [重写记录](REWRITE_RECORD.md) | 清理记录与公开文档基线 |
| 历史 | [旧文件浏览器快照](history/2026-10-21-file-viewer/INDEX.md) | 保留原文，不作为当前需求或命令 |

## 维护规则

- 当前事实放入对应专题，README 保持入口职责；新增专题时更新本索引。
- 已确认方向、方案建议、已实现、后台验证、窗口验证与应用发布分开表述。
- 性能和兼容性结论要附版本、样本、环境、命令及限制，未知项标为待测。
- 历史快照不改写，旧机器路径和私有项目引用只用于追溯，不成为公共构建前提。
- 文档检查：在仓库根目录运行 `python3 scripts/check_docs.py` 与 `git diff --check`。
