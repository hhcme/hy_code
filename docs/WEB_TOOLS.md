# Web 开发工具

更新：2026-10-23。用户要求补齐 Web 开发能力；本页是实现与验收台账，不能把范围确认当成完成。首版宿主仍为原生 macOS，Rust 独占正式文本；Web 项目不迁入 WebView 编辑器，也不复制 WebStorm 插件。

build 36 增加 YAML/YML；JSON/JSONC 和 YAML 共用固定离线 Schema 与原生授权读取，检查、格式化及常用配置文件范围见[配置工具](CONFIGURATION_TOOLS.md)。TS/Vue 等既有能力不由此扩为全部配置格式。

## 完整范围

| 类别 | 目标 |
| --- | --- |
| 语言 | JavaScript/TypeScript、JSX/TSX、Vue SFC、HTML、CSS/SCSS/LESS、JSON/JSONC；React 以 TSX 与项目类型依赖提供语义 |
| 分析 | 未保存增量诊断、问题定位、缺工具/崩溃/重启、同工作区多语言并存、资源与取消边界 |
| 编辑与导航 | 悬浮、定义/类型/实现、引用、结构、补全/自动导入、参数提示、格式化、符号搜索、代码动作、重命名与多文件预览 |
| 项目与依赖 | package.json、npm/pnpm/yarn、脚本、依赖版本、显式安装/增删/过期、锁文件保护和 monorepo 包选择 |
| 质量 | TypeScript 检查、显式 lint/format/test/build、ESLint/Prettier、单项测试/重跑、测试树与覆盖率 |
| 运行与调试 | Node 与浏览器目标、配置、停止、断点、调用栈/变量、求值、source map、浏览器连接和开发服务 |
| 框架 | React/Vue 基础语义后继续覆盖框架配置、模板/资源路径、CSS modules/Tailwind、Angular/Svelte/Astro 等独立服务适配 |

这些全部保留为后续验收项；没有接入的能力明确标为待实现，不提供假的诊断、断点或成功结果。浏览器/应用与真实窗口测试继续受静默约束，不能为了补验收启动浏览器或用户项目。

## 本轮选型

采用公开 npm 包，固定版本和完整性由 [package.json](../tools/web-language-services/package.json) 与锁文件记录；生命周期脚本禁用。安装只发生在显式开发构建准备，不因用户打开项目自动安装依赖。应用调用外部 Node，不分发本机 Node 或第三方 IDE 资源。

| 包 | 固定版本 | 来源与许可 | 职责 |
| --- | --- | --- | --- |
| typescript | 6.0.3 | [Microsoft TypeScript](https://github.com/microsoft/TypeScript)，Apache-2.0 | TS/JS/JSX/TSX 类型服务 |
| typescript-language-server | 6.0.2 | [上游社区项目](https://github.com/typescript-language-server/typescript-language-server)，Apache-2.0 | TypeScript 的 LSP 适配，非 Microsoft 官方语言服务器 |
| @vue/language-server | 3.3.13 | [Vue Language Tools](https://github.com/vuejs/language-tools)，MIT | Vue 模板与脚本，桥接所附 @vue/typescript-plugin |
| yaml-language-server | 2.0.0 | [Red Hat](https://github.com/redhat-developer/yaml-language-server)，MIT | YAML 检查、格式化、Schema、结构、补全与锚点导航 |
| vscode-langservers-extracted | 4.10.0 | [上游提取项目](https://github.com/hrsh7th/vscode-langservers-extracted)，MIT | 公开 VS Code HTML/CSS/JSON 服务，非从本机安装包提取 |

Vue 3 服务需要转发 `tsserver/request` / `tsserver/response`，不能只启动一个进程就声称模板类型检查可用。依据：[Vue 集成说明](https://github.com/vuejs/language-tools/discussions/5456)、[TypeScript 服务配置](https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md)。Node 要求与固定服务版本一致，最低 22.22.2。自动类型下载、JSON schema 网络请求与隐式 npm 安装默认关闭；打开项目不执行 package scripts、ESLint/Prettier 项目配置或构建脚本。

## build 28 基础工具与 build 29 项目诊断

| 功能 | 实现与限制 |
| --- | --- |
| JS/TS/JSX/TSX、HTML/CSS/SCSS/LESS、JSON/JSONC | 按需 stdio 服务，UTF-16 增量、未保存诊断、悬浮、定义/类型/实现、引用、结构、显式补全和格式化；实际能力由对应服务提供，不能将 TS 能力套用到全部语言 |
| Vue SFC | 同时同步 TS 与 Vue，按功能路由并回送嵌套通知；模板 hover/TS 桥接已做真实协议检查。默认关闭，需要在 Web 分析面板显式信任项目插件；TS 服务也仅在信任后注册 Vue 插件 |
| 补全/自动导入 | Ctrl-Space 菜单；选择后 resolve，合并 import 与主替换并修正光标；基础 snippet 默认值/选择/Tab/Shift-Tab；不支持转换和镜像同步，不自动弹出补全 |
| 参数与重构 | ⌘P 参数信息、⌥Return 代码动作、重命名/整理导入；多文件文本先预览，应用后按各文件撤销和自动保存；命令式动作和 resource operations 明确拒绝 |
| 项目/依赖 | 当前文件向上找最近 package.json，声明依赖/版本/种类、workspaces、scripts；npm/pnpm/Yarn 1/4+ 安装/增删/查询与脚本入口，有界输出和停止；Yarn 2/3 未支持，Yarn 4 无内置 outdated，明确提示 |
| 项目检查 | 打开项目自动发现源文件并后台检查，未保存模块编辑检查自身及反向引用；FSEvents 磁盘更新、JSON 导入方与删除回收；范围/预算及验证见[项目后台诊断](PROJECT_ANALYSIS.md) |
| 原生集成 | 问题/结构/悬浮/状态与 Dart 复用原生交互，拥有独立服务；Node 设置、重启与工作区释放；打开文件不安装 npm 包 |

包任务只执行用户点击的命令。依赖操作使用 npm/pnpm `--ignore-scripts`，Yarn 4 使用 `--mode=skip-build`，依据 [Yarn install](https://yarnpkg.com/cli/install)、[add](https://yarnpkg.com/cli/add) 与 [remove](https://yarnpkg.com/cli/remove)；显式 scripts 仍会执行项目代码。运行前保存缓冲并保护清单/锁文件，重新读取并核对所选脚本，退出后刷新；monorepo 当前以活动文件的最近 package 为任务目录，尚无完整 workspace 图形选择器。

### 预算与编辑安全

语义文档最多 1 MiB，基础编辑仍为 8 MiB。六类语言进程按项目分析或编辑需求启动，Node 每进程 old-space 上限 512 MiB；这不是实测 RSS 或性能达标结论。诊断最多 500 URI、每 URI 1000、合计 5000；补全/代码动作菜单最多 100 项，符号/引用最多 2000 项。Vue 隧道最多 64 个在途请求，过量请求返回 null 结束等待。

修改预览最多 32 文件、5000 edits、新文本总计 8 MiB、输入总计 8 MiB，单文件差异展示最多 256 KiB；拒绝越界/远程 URI、路径别名、符号链接逃逸、重叠、无效 UTF-16 和 NUL。全工作区原生编辑都会使在途旧结果失效；脏目标必须已同步给生成修改的服务，超过语义限制或仅同步给其他服务的脏文件拒绝应用。应用前再次校验文档 ID 和修订。外部磁盘写入继续由既有保存指纹检查保护，不声称跨文件磁盘事务或外部变化下服务缓存永远最新。

### 仍需继续实现

- Web Node/浏览器调试适配、断点/变量/栈/source map、开发服务生命周期与浏览器连接。
- 测试树、单项测试/重跑、覆盖率和项目测试框架适配；目前仅能显式运行已有 package scripts。
- 专用 ESLint/Prettier 诊断/项目格式化配置（YAML 已使用固定包内格式化器）、完整命令式重构、调用/继承层级和符号搜索交互。
- 更完整 React/Vue 依赖项目与框架配置，Angular/Svelte/Astro、Tailwind/CSS modules、资源路径等独立适配。
- 自动补全弹层、snippet 镜像、批量统一撤销和真实窗口/IME/性能验收。

这些属于用户要求的完整范围，持续保留为待做；本批不声称全部 WebStorm 功能已经完成。

## 固定依赖与通知

完整 119 项在 [third-party.json](../tools/web-language-services/third-party.json)，通知原文在 [npm 目录](../third_party/licenses/npm/)。`scripts/setup_web_tools.sh` 使用 primary registry 的锁定归档，禁用 hooks；`scripts/web_tools.mjs` 校验版本、来源、integrity 元数据和保留通知 SHA。构建将固定服务复制到应用，不复制外部 Node。

有三个缺少 npm 原文通知的包使用 [补充记录](../tools/web-language-services/license-supplements.json)。其中 @johnsoncodehk/pug-beautify 0.2.2 在归档与所查上游均无独立 MIT 原文，只保留原始 package.json 许可声明与 README，不能将其描述成已取得完整版权原文；公开二进制分发前仍需复核。

## 验证边界

仅使用自有临时文本/协议替身和固定上游服务执行无 GUI 检查；不运行用户应用、浏览器、dev server、真实项目 scripts 或依赖生命周期钩子。每项分别记录实现、模型/真实协议、窗口、性能和发布。build 28 的检查与本地开发包记录见[证据文件](evidence/2026-10-22-build28-web-tools.json)。原生菜单、修改预览、包任务、真实项目和性能仍未做 GUI/真实运行验收。
