# HyCode 文档索引

更新：2026-10-21。当前为文档基线，没有应用实现。首版仅 macOS / Apple Silicon，Swift 原生界面 + Rust 内核；自有代码与文档采用 [MIT](../LICENSE)。

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
| 规划 | [实施路线](ROADMAP.md) | macOS 阶段及验收，不表示交付日期 |
| 性能 | [性能设计与验收](PERFORMANCE.md) | 样本、测量口径和预算决策 |
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
