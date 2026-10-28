# 内置 Codex Agent

更新：2026-10-28。用户确认在 HyCode 内接入自己的 Codex 系统，默认在右侧，提供专用图标和多个对话。系统 CLI 和官方 App 继续使用其现有官方配置，HyCode 仅使用项目选择的自定义服务。实现、后台协议验证、真实服务、窗口和发布分别验收。

## 当前范围

- 默认展开右上 Codex 面板，工具条使用独立的代码图标；沿用四角移动、排序、显隐与可拖分隔。初始右侧宽度 380 pt，窄窗口继续由工作台压缩。
- 每个项目最多保存 24 个对话，分别持有名称、草稿、模型、思考强度、权限、消息和官方线程 ID。支持新建、切换、重命名、删除、流式回复、命令输出、文件变化、停止及失败提示；后台对话继续运行，事件不会随当前选择改变归属。
- 最多两个只读对话并行。修改任务独占该项目，不能与其他 Agent 或 Dart/Web/Flutter 执行任务同时运行；修改前要求文档已保存、组合输入结束和工具/修改预览空闲。执行期间冻结原生编辑和自动保存，结束并回收子进程后重载已打开文档。
- 默认只读。修改模式允许 Codex 在授权根内直接改写磁盘；需要人工处理的命令/文件审批显示在所属对话中。沙箱提权和未知客户端请求不自动批准。命令可以联网，目前不提供网络出口隔离；不存在全盘文件访问选项。
- 模型服务可设为 HyCode 默认值，未配置的项目继承默认服务；项目显式设置优先。设置包含 Responses 地址、模型、思考、上下文和密钥。每个对话分别调整模型、思考与上下文；下一轮生效，运行中禁止改变这些字段。模型可手动填写，不把内置模型目录当作第三方权限证明。
- 默认不连接服务或启动 Codex；只有明确发送才启动。每个运行中的对话拥有一个 app-server，结束后回收进程，下一轮通过官方持久化线程恢复历史。

这不是仅绘制聊天界面：HyCode 拥有工作区授权、凭据、会话与任务生命周期、输出预算、审批交互、文档写入互斥和错误恢复；Codex 拥有推理与工具循环。可视终端不是前置依赖。

## build 47：应用自管 API Key，不使用系统钥匙串

2026-10-28 用户明确要求 API Key 等由 HyCode 自己管理，避免系统钥匙串和密码授权交互。本决定替代 build 42–46 的钥匙串设计；build 46 只完成后台中间构建，未作为最终方案交付。菜单和消息指令改动保留。

- API Key 存在应用自己的 `Application Support/HyCode/Credentials/Codex` 目录，目录 0700、独立记录 0600，名称仅为账户标识的 SHA-256。记录为有界 UTF-8 本地文件，最多 16 KiB；采用文件权限隔离，不宣称系统钥匙串加密。该目录不属于项目源码、状态 JSON、Codex 运行目录或系统 Codex 配置。
- App 与设置工具使用同一个 actor，不导入 Security/LocalAuthentication 或调用 SecItem/SecKeychain；应用重建和签名变化不再参与凭据读取。不会自动读取、迁移或删除旧系统条目。本批配置从用户已提供的输入重新保存到本地，不读取旧钥匙串。
- 目录拒绝符号链接，文件通过目录相对 `openat`、`O_NOFOLLOW`、普通文件/属主/单硬链接/大小校验读取；所有 FD 都有单一所有者、CLOEXEC 和释放路径。短跨进程 flock 与同目录临时文件、fsync、renameat 保证替换时不先截断旧值，忙锁和损坏输入显示行内错误。
- Agent 文件沙箱始终排除凭据目录，即使它位于用户选择的宽工作区中；同时禁止移动其祖先，防止改路径绕过。临时样本已验证读取、移动及硬链接拒绝，普通项目文件仍可读写。运行时仅按原有协议取得当前服务密钥，Shell 工具环境继续不携带它。
- `HyCodeCodexSetup` 现在只需 `/project/root`，旧可选 App 参数为兼容保留，不校验或绑定签名。隐藏 stdin 仍是新密钥入口；空输入只能复用本地已有同服务凭据，项目配置可显式复用 HyCode 默认服务的本地值。配置仍通过独立交接文件保护运行窗口的草稿和历史。

通用验证只使用生成目录和假值，覆盖持久化/权限、账户隔离、原子替换、非法/超限值、符号与硬链接、忙锁及真实 Seatbelt 边界。本批完整检查通过 268 Swift（47 suites）、37 Rust、4 Node，Codex 相关 Swift ASan 36 项通过。用户配置后的私有文件写入与重新读取已通过，默认服务和当前源码项目均已交接；只报告成功、模式和数量，不输出密钥。随包引擎的最终 6 次 loopback 请求通过，并确认新回复策略作为 system/developer 内容传出；没有新增真实模型调用。当前没有启动 GUI 或访问系统凭据服务；最终产物、日志和剩余窗口验收见 [build 47 证据](evidence/2026-10-28-build47-local-codex-credentials.json)。

## build 46：钥匙串修补尝试（已被 build 47 替代）

用户提供的新截图显示，HyCode 请求访问登录钥匙串中的 `HyCode Codex API Key`，并且输入区仍出现蓝色默认菜单及额外箭头。这是用户报告的真实窗口问题，不以先前设置工具读写成功反驳或代替 App 验收。

钥匙串是本项目记住第三方 API Key 的设计选择，不是 Codex 或 Responses API 的协议要求。此前 App 的读取查询只传 `LAContext.interactionNotAllowed` 与 `kSecUseAuthenticationUIFail`，而设置工具另外调用 `SecKeychainSetUserInteractionAllowed(false)`；两条执行路径并不等价。当前开发包又只有链接器 ad-hoc 签名，钥匙串锁定状态、旧条目 ACL 或重建后的应用身份均可能影响访问，单凭截图不能确定是哪一种。不会让用户以输入 Mac 登录密码来掩盖自动访问的缺陷。

本轮在共享凭据适配的每次读写之前设置并读取确认禁用可选交互；设置/确认失败直接返回错误，不执行 SecItem 操作，也没有重新开启交互的路径。该进程级策略只影响当前进程，不改变登录钥匙串、其他应用权限或系统 Codex 登录。查询级禁止交互仍保留。它继续使用现有旧版 Security API，弃用警告和开发签名限制仍存在；并不宣称跨任意后续构建的凭据访问已经稳定。

载入失败不再由 `try?` 隐去原因，按项目 generation 保留 `credentialIssue`，在输入区和设置中提示重新填写 API Key。设置说明明确区分模型 API Key 与 Mac 登录密码。现有密钥条目和聊天历史不因错误而删除。

输入区的加号、权限、模型/思考与顶部更多菜单改用既有 `WorkbenchMenuButton` 和应用自有菜单。各按钮按标签固有宽度布局，避免 SwiftUI 默认 Menu 的系统强调色、额外箭头和尺寸行为；权限靠左、上下文及模型靠右。共享控件新增的颜色/中性状态参数具有原默认值，其他工作台菜单不因此换样式。

Responses API 提供消息与工具事件，不包含官方客户端的字体、控件或排版。HyCode 当前复用官方执行引擎，模型是 DeepSeek，界面仍为自有原生实现。DeepSeek 的基础指令补充简洁回答、避免装饰性 emoji 和无依据的能力目录，不能宣称尚未接入的绘图/语音/市场等产品入口；不重写已经生成的旧消息，也不保证不同模型输出与官方模型一致。

新增无 GUI 的凭据策略测试只调用 Security 的进程交互标志 set/get，不查询任何 Keychain item、不保存样本凭据、解锁或创建钥匙串。真实 App 启动、无弹窗、窗口样式与真实模型遵循情况仍未测试；实现与后台证据见 [build 46 记录](evidence/2026-10-28-build46-codex-credentials-and-menus.json)。

## build 45：按用户截图和录屏修订

用户继续提供 Codex 桌面端截图和一段 19.68 秒录屏，要求消息样式与展开交互对照修改。这些素材只用于观察，不进入仓库或应用资源；录屏在后台提取静帧，没有播放音频、启动参考应用或截取桌面。build 44 只对齐了侧栏组织，不能视为视觉还原验收。

- 聊天区采用独立中性配色，深色正文背景 `#181818`、输入框 `#303030`，不改变工作台其他面板。正文 14 pt、行距 6 pt，内容列最大 760 pt，在右侧窄面板收缩；用户气泡靠右，助手正文直接排版，行内代码、标题、列表、引用和代码块分别呈现。最终回复提供复制按钮，其他正文可通过上下文菜单复制，复制不占用生成中正文的空白高度。
- 连续工具活动合并为低对比度摘要，点击后在有界区域展开。按真实 `commandActions` 显示读取、搜索、列目录和命令，多动作命令分别列出；再次展开可读完整命令/输出/退出码。文件变化列出文件名、增删行数和新文件标记，悬停显示报告路径。终态、断线与取消会结束进行中状态，不把缺失结果宣称成功。
- 输入区采用大圆角、左侧权限、右侧模型与思考组合菜单、上下文指示和蓝色发送/停止。权限仍只有只读或授权项目访问，不因参考画面出现“完全访问”而扩大范围。上下文环与详情只使用实际最近一次请求的 token 数据；无数据时不填入比例，运行中可查看但不能修改预算。原生输入法、独立撤销、增长高度与 Enter/Shift+Enter 语义沿用 build 44。
- 输入框上方汇总本轮报告的文件数与增删行。优先采用最新 `turn/diff/updated`，避免同时叠加逐工具 diff；服务端给出空 diff 时清空汇总。缺少整轮 diff 时按实际完成的逐文件补丁展示。点击汇总或文件行打开只读差异快照，可选文件、滚动和复制，不读取路径、执行命令或回滚磁盘；差异列表最多投影 256 个文件，超限仍显示实际报告数和“仅展示前 256 个”，不把局部增删行数标成总数；单文件最多投影 4096 行，完整捕获内容仍可复制。
- 公共思考摘要以低对比度文字显示、点击展开；只接收公开 summary，不收集原始 reasoning content。轮次完成显示实际状态与服务端提供的耗时。历史支持搜索、按更新时间排序和运行状态；切换后回到该对话的最新位置。
- 聊天滚动只观察所属原生 ScrollView。用户向上滚动暂停跟随，回到末尾或点击向下按钮恢复；没有全局事件监听或合成输入。活动分组、差异分析与协议文本投影在 utility 任务完成，回写仅更新所属对话的消息/线程/token 字段，不覆盖期间编辑的草稿或标题。

公开消息/工具元数据与 diff 一起计入 256 KiB 单项和 1 MiB 对话预算；旧消息缺少可选字段仍可读取，保留旧记录的普通折叠展示。素材中的目标、排队、语音、附件、子 Agent 面板和完整桌面工作区并未在本批接入，不添加假入口。

本批全量静默检查通过 263 Swift（46 suites）、37 Rust、4 Node；Codex 相关 Swift ASan 31 项通过。最终随包引擎的 6 次本机替身请求通过并发、流式、继续对话、上下文覆盖、固定命令与取消回收。原有设置工具为最终构建重新关联 HyCode 默认服务和本项目的专用凭据，写入/静默读取通过，没有新增真实模型调用。源码审查提出的状态刷新、未知状态、重复补丁、预算边界和列表超限问题均已修复并增加回归。只有源码审查、编译和无 GUI 模型/协议验证；原生输入、实际滚动条/折叠/弹层与像素效果仍未运行窗口验收，不能称为逐像素复刻。后台结果与未验证项见 [build 45 证据](evidence/2026-10-28-build45-codex-transcript.json)。

## build 44：IDE 插件式侧栏

用户要求界面效果对齐 VS Code 的 Codex 插件。参考本机已安装的 26.1007.21434 静态界面资源，以及 OpenAI [IDE 说明](https://learn.chatgpt.com/docs/codex/ide)中的[官方侧栏图片](https://learn.chatgpt.com/images/codex/ide-review.webp)。只观察组织、层级与间距，没有运行 VS Code、复制 VSIX 代码/样式/图标或将其资源打包；本轮实现仍为自有 SwiftUI/AppKit。

- 顶部为历史、新对话和更多操作；历史按需弹出，活动对话展示标题，不再永久占用一排蓝色列表。
- 底部是统一圆角输入区，模型/思考/权限使用无边框紧凑菜单；窄面板把次要选项合并到更多菜单。上下文数值移入弹层，正文区域不显示配置表单。
- 原生 NSTextView 随输入增长，空输入 46 pt、上限 166 pt，超过后内部滚动。Enter / ⌘Enter 发送，Shift+Enter 换行；组合输入中的 Enter 留给输入法。聚焦只响应用户动作并在进入 key window 后消费请求。每个输入拥有独立 UndoManager，不清理编辑器或其他字段的历史。
- 用户消息使用右侧气泡，回复支持基本 Markdown、标题、列表、引用和带复制按钮的代码块；命令与文件变化为可折叠条目。解析在 utility 任务完成，旧结果取消后不写回；核心围栏最多 128 块、原生投影最多 256 块，超限显示完整原文。CRLF 代码复制保留原行尾；不加载远程图片或执行 HTML。复制仅由用户点击触发，测试没有访问剪贴板。
- 新对话提供可填入草稿的建议；发送/停止位于输入区右下角。没有为未实现的附件、云端、跨文件统一撤销或修改 Review 添加可点击假入口。

截图中的 Desktop 模型为空来自旧版只配置了源码项目。本轮增加 `defaults/provider-setup.json` 持久默认服务；未配置项目在打开时继承，并保留已有未发送输入。应用级凭据使用独立 `hycode-default` account 前缀，项目级凭据仍按根路径区分。同地址默认凭据更新时，继承者只刷新凭据 ID，保留模型、思考、上下文与聊天历史；不同地址或显式项目设置不会被覆盖。设置中的“作为 HyCode 默认服务”用于后续配置，不读取系统 Codex。

界面只完成源码、编译与后台模型检查；没有创建应用宿主、原生视图测试或桌面截图，真实输入法、滚动、布局与像素一致性仍待窗口验收。

## 隔离和认证

使用官方原版 Codex CLI 0.164.0 的 `app-server --listen stdio://`，原生 Swift actor 通过 JSONL 请求/通知连接；不经过登录 Shell，不建立 TCP 控制端口。模型请求走用户配置的第三方地址与其 API Key，不提供或复制官方 ChatGPT 登录。

数据位于 HyCode 的 Application Support 目录下，项目按规范化根路径的 SHA-256 区分；各对话拥有独立 `CODEX_HOME`。目录 0700，设置/消息 0600，以临时文件原子替换保存；不将地址或密钥写进仓库 `.codex/config.toml`。系统配置、项目供应商配置与应用私有配置是不同来源，项目层本身不能可靠承载供应商重定向。

凭据由 HyCode 的本地文件适配保存，账户仍按项目根或应用默认作用域、服务地址及可选 UUID 区分。打开项目只读应用自管文件，失败保留具体原因并提供重新填写 API Key 的入口。新输入写入新记录；空输入保留当前本地账户。旧系统钥匙串不作为回退来源，也不会自动清理。现有对话和新服务的身份分离保持不变。

子进程从固定白名单环境启动，独立传递 `HYCODE_CODEX_API_KEY`，使用进程内认证存储，不继承系统 API Key、代理、Node 注入变量或整个 PATH。Shell 工具另有独立环境，不传递模型密钥。关闭反馈、统计、Shell snapshot 与原生子 Agent 扩散。现有工具进程默认环境策略保留，只有 Codex 使用新白名单入口。

外层 macOS Seatbelt 限制 app-server/Code Mode host 读取：授权项目、自己的运行目录和状态，以及必要系统路径；仅允许其自有状态和修改模式的授权项目写入。目录祖先只提供遍历/目录项读取，不放开同级文件。过滤路径使用 POSIX `realpath`；Foundation 对 `/private/var` 的缩写不能用于内核过滤。macOS 27 dyld 还需要根目录项读取。Codex 使用 `externalSandbox` 声明复用宿主边界，避免 macOS 拒绝嵌套 `sandbox_apply`；网络声明为 enabled，与实际可联网行为一致。固定版本的 granular 审批协议需开启 experimentalApi capability。该规则不是完整的系统交互/网络出口白名单，最低系统和所有命令兼容性仍需单独验证。

打开目录不启动 Agent、自动信任项目插件或导入全局 MCP/登录记录。启动配置不信任项目 `.codex` 层，并在创建线程前检查实际服务地址、供应商与额外 MCP/hooks/notify；有冲突时停止。

## DeepSeek 预设与上下文

2026-10-26 依据 DeepSeek 官方 [Codex 接入](https://api-docs.deepseek.com/quick_start/agent_integrations/codex/)、[Responses 兼容说明](https://api-docs.deepseek.com/guides/responses_api/)和[模型规格](https://api-docs.deepseek.com/quick_start/pricing/)接入原生接口，无需本地 HTTP 转换代理。设置中提供 V4 Pro 与 Flash 预设；默认 V4 Pro，地址 `https://api.deepseek.com`，思考 `max`，上下文 1,048,576 tokens。DeepSeek 支持关闭思考、low、high 和 max；xhigh 只是 high 的兼容别名，不能代表最高档。

已知模型的离线元数据由 `CodexModelCatalog` 生成到各对话自己的 `models.json`，声明 max 与 1M 上限，并使用 HyCode 自有基础指令。不会执行 DeepSeek 的全局安装脚本、下载远程提示词或修改 `~/.codex`。固定 Codex 0.164.0 的思考字段为非空字符串，支持向模型传递实际的 max。

上下文覆盖传递为 `model_context_window`，不只是界面显示。空值采用模型元数据默认值；可填写 token 数或选择常用档位，已知 DeepSeek 模型拒绝超过 1,048,576 或低于 8192。该设置只改变客户端上下文预算，不能扩展服务端能力。沿用官方 95% 输入预算和提前自动压缩策略，给指令、工具与输出留空间；因此 1M 并不表示每轮可填满 1M 用户正文。普通自定义模型的范围校验不证明其服务端实际容量。

build 42 状态文件中缺失上下文字段时按空值读取，保留既有线程、草稿、模型和思考选择；不会为升级擅自清空历史。

`HyCodeCodexSetup` 是单独的无 GUI 配置工具。`configure` 把 DeepSeek 默认值写入指定项目的独立 `provider-setup.json`，密钥从标准输入读取且关闭终端回显，保存到同一 HyCode 专用本地凭据目录。它不读取系统钥匙串，也不需要 App 签名或系统密码授权。

应用的 CodexStore 整个生命周期持有 `.owner.lock` 的非阻塞跨进程租约，其他实例不能同时维护可写快照。设置工具始终只生成交接文件，不写运行窗口的 `state.json`；下次打开项目时应用持锁合并最新状态，再原子保存并移除交接。独立 `.setup.lock` 保护短交接，失败保留来源。这样旧版窗口在退出时写回旧快照也不能抹掉待应用设置；既有草稿、消息和线程保留，不通过关闭或重启用户应用完成配置。

`verify` 从同一本地私有凭据记录取密钥，使用原生 URLSession 向固定 Responses 接口发送短提示。请求 `tools=[]`、`tool_choice=none`、`store=false`、输出上限 512 tokens；不创建 Agent 进程或提供工具，流式数据总预算 256 KiB、单行 64 KiB，资源超时 45 秒。不会读取用户源码、加载临时项目、执行命令或用真实模型验证工具环路。官方引擎的工具与并发继续只用本机替身验证。

```sh
# 仅用户要求配置时显式运行；按提示输入密钥，不作为参数或环境变量传入
swift run --configuration release --jobs 2 HyCodeCodexSetup configure /project/root
# 设置 HyCode 默认服务，供未配置项目继承；同样只有显式运行才读取输入密钥
swift run --configuration release --jobs 2 HyCodeCodexSetup configure-default /project/root
# 只验证默认凭据可静默读取，不联网
swift run --configuration release --jobs 2 HyCodeCodexSetup check-default /project/root
# 仅用户授权真实服务后执行；会产生真实模型调用费用，不属于自动测试
swift run --configuration release --jobs 2 HyCodeCodexSetup verify /project/root
# 只检查当前凭据能否静默读取，不产生网络请求
swift run --configuration release --jobs 2 HyCodeCodexSetup check-credentials /project/root
```

## 文档和修改边界

正式文本仍由既有 Rust/Swift 文档所有者管理。首版修改模式使用独占磁盘工具窗口：已有未保存内容时拒绝开始，不为了运行 Agent 自动保存用户草稿；在途保存/编辑先排空，期间新打开文件也只读。任务退出后才释放保护并重新载入文件。

文件变化面板展示 Codex 提供的变化，不代表跨文件原子事务、原生统一撤销或改动前预览全部可用。修改后的重载会重建文档撤销历史。当前没有 Git worktree 任务隔离、自动合并、附件、完整 Markdown 富文本、计划模式或所有 Codex 桌面功能；这些不是本批已实现能力。

系统外部进程仍可能修改原项目，既有磁盘指纹/保存冲突保护继续适用。大文件局部页不作为全文传给 Agent：本批没有将原生缓冲自动注入提示，Agent 读取的是授权磁盘文件。

额外 SDK/工具链目录的授权入口尚未接入。项目外的 Homebrew、Flutter 或 Xcode 工具链可能被文件边界阻止；不能把固定 Shell 样本成功当作真实项目的构建、测试或 SDK 能力已经验收。

## 预算

- 两个只读运行或一个修改运行；会话不保留闲置进程。
- 单个用户消息/草稿 64 KiB；单项正文和工具元数据合计 256 KiB；每对话 256 条消息、合计 1 MiB；最多 24 对话，状态文件 32 MiB。
- JSONL 单帧 2 MiB，客户端请求 1 MiB，在途请求 32 个、事件队列 256 个；超限关闭，不能丢帧后继续展示成功。
- 单次协议请求默认 20 秒；模型轮次由用户停止。停止优先发送 `turn/interrupt` 并有界等待终态，再终止自有进程组和升级 SIGKILL；不会按名称杀系统 Codex。
- 诊断最多 8 KiB，显示前移除当前密钥，超预算不显示截断诊断。API Key 不进入命令行、项目 JSON、运行资源或探针日志。
- 原版 CLI、Code Mode host 和 rg 合计约 318 MiB，仅按需启动。主进程资源栏仍不统计这些子进程，不宣称已完成 Agent 内存/CPU 性能验收。

## 依赖和构建

固定来源、归档 SHA-512 和四个文件 SHA-256 见 [manifest](../tools/codex-runtime/manifest.json)。官方 npm 原生包仅用于获取独立可执行文件，不需要安装 Node 或全局 npm 包；voice 二进制、动态库与资源没有分发。上游 Apache-2.0、NOTICE、Ratatui/ripgrep MIT 和 PCRE2 通知保留在[许可目录](../third_party/licenses/codex-0.164.0)。许可关系见[依赖台账](DEPENDENCIES.md)。

```sh
# 显式准备固定官方资源，首次约 135 MiB 下载；不执行 CLI、不安装全局命令
python3 scripts/codex_runtime.py setup
# 离线校验；不会联网或执行 Codex
python3 scripts/codex_runtime.py check
# 静默构建，包含官方私有运行资源；不会启动应用
bash scripts/build_macos.sh debug
```

构建只复制校验通过的四个文件。运行前还在 utility 任务中校验应用自己的资源，不使用系统 PATH 或从其他应用提取二进制。正式嵌套签名、公证与公开分发尚未实施，不能把此开发包称为正式版本。

## 验证

`CodexTests` 是无 GUI 的模型/持久化/协议/固定 Shell 样本测试，覆盖会话独立、并发准入、取消、超限、损坏帧、环境白名单、符号链接目标拒绝及真实 Seatbelt 文件边界；不运行真实模型、用户项目、AppKit 宿主或钥匙串操作。build 44 全量后台检查通过 251 Swift、37 Rust、4 Node；19 项 Codex 相关 Swift ASan 通过，第三方官方二进制和 Rust 静态库未插桩。新增 DeepSeek 元数据、上下文边界、凭据 UUID、旧状态兼容、跨进程租约与旧窗口晚到写入的交接断言。

显式运行的官方二进制探针只启动自有 loopback Responses 替身与生成项目，使用假密钥。它通过 6 次本机请求验证 max 实际出现在请求、1M 上下文以及同线程重建后的 128K 覆盖、两个并行会话、流式输出、真实 `exec_command` 读取/写入生成样本，以及运行中固定 sleep 命令的中断和回收；Shell 内也断言模型密钥未传入。它不请求真实服务商或官方账号：

```sh
nice -n 10 swift run --jobs 2 HyCodeCodexProbe \
  .build/codex-runtime/bin/codex tools/fixtures/codex_provider.py
```

该探针不自动加入通用检查，不启动浏览器、窗口、系统通知、声音或用户命令。所有运行样本及服务进程均在退出时清理。用户要求配置后，独立原生探针两次通过 DeepSeek V4 Pro/max 的真实流式固定回复，HTTP 200；首次 input 105/output 52，最终凭据 input 105/output 62 tokens。最终设置工具的钥匙串写入/读取已通过；重建导致旧条目身份校验失败（-25293）的情况已实际遇到，随后使用新的凭据 UUID 为最终构建创建并验证了新条目。真实模型与 Codex 工具环路的组合、服务商审批、完整 1M 压力/长会话压缩、实际账单、App 内钥匙串访问、窗口输入/停靠/滚动和性能仍未验收；不能把原生接口或本机替身成功当作这些结论。

Release 0.1.0 / build 47 已静默构建，未启动或安装；开发包约 521 MiB，内置运行资源约 318 MiB。主程序只有链接器 ad-hoc 签名，Info.plist/资源未做分发封装，没有 Developer ID、公证或发布。本轮设置为下次项目打开时导入，当前旧窗口没有重启或自动重载。本批源码、产物、日志哈希和各项验收边界见 [build 47 证据](evidence/2026-10-28-build47-local-codex-credentials.json)。[build 46 中间记录](evidence/2026-10-28-build46-codex-credentials-and-menus.json)标记为已替代。[build 45 证据](evidence/2026-10-28-build45-codex-transcript.json)保留原始状态。[build 44 证据](evidence/2026-10-26-build44-codex-panel.json)、DeepSeek 原生连通的 [build 43 记录](evidence/2026-10-26-build43-deepseek.json)和初始接入的 [build 42 记录](evidence/2026-10-26-build42-codex-agent.json)保留为上一阶段证据。

## 源码入口

| 路径 | 职责 |
| --- | --- |
| `packages/HyCodeWorkspace/Sources/Agent/` | 配置、模型元数据、会话、准入、JSONL、运行所有者、本地凭据、存储和 Seatbelt |
| `app/macos/Sources/Agent/` | 原生右侧面板、工作区控制器和随包资源校验 |
| `app/macos/Sources/Editor/EditorWorkspace.swift` | 修改任务的原生文档独占/恢复 |
| `scripts/codex_runtime.py` | 固定运行资源准备、校验和应用内复制 |
| `tools/CodexProbe/`、`tools/fixtures/codex_provider.py` | 官方 runtime 与本机假服务的无 GUI 探针 |
| `tools/CodexSetup/` | 仅显式运行的无 GUI 项目配置与真实服务验证 |
| `packages/HyCodeWorkspace/Tests/CodexTests.swift` | 核心回归与文件边界断言 |
| `packages/HyCodeWorkspace/Tests/CodexCredentialTests.swift` | 私有临时目录/假值的本地凭据与沙箱边界测试 |
| `packages/HyCodeWorkspace/Tests/CodexTranscriptTests.swift` | 工具生命周期、差异计数/去重、公共摘要、旧历史、预算和滚动几何 |
| `packages/HyCodeWorkspace/Tests/CodexPresentationTests.swift` | 围栏/CRLF、输入高度预算、默认服务作用域与草稿保留 |

官方参考：[app-server](https://developers.openai.com/codex/app-server/)、[自定义供应商及配置范围](https://developers.openai.com/codex/config-advanced/)、[协议配置](https://learn.chatgpt.com/docs/config-file/config-reference)。协议依赖固定版本，部分接口仍是实验性，升级必须重新检查生成 Schema 和后台回归。
