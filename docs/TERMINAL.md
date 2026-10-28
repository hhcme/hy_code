# 本地交互终端

2026-10-28 / 首批终端实现为 build 48、集成开发包为 build 49；本轮样式与输入候选为 build 52，各批证据分别保留。Git 集成见 [Git 专题](GIT.md)。用户确认先做可用版本，界面使用 HyCode 自有风格。当前接入真实本地 PTY、原生终端显示、多标签/递归分屏与基础工作台集成；后台检查、真实窗口、性能和正式分发分别验收。

## 交互范围

- 点击“终端”工具或使用 ⌘0 展开；第一次显式打开才创建 Shell。打开项目、恢复工作区、构造隐藏面板和后台诊断不会启动 Shell。
- 默认位于左下，可沿用工具跨角移动、收起与尺寸调整。原生标题、紧凑标签、自有菜单、提示和设置共用工作台配色、悬停反馈与字体。终端正文使用 AppKit 视图，不把工作台改为 WebView。
- 新建、切换、重命名和关闭标签；向右/向下递归分屏，各分屏独立拥有 Shell、屏幕、滚动历史和输入。最多 8 个会话，每标签最多 4 个分屏。
- 按用户截图反馈移除标签底部蓝色强调条与正文上方整行蓝点/目录/运行状态。选中标签只使用工作台中性背景；目录/状态移到标签悬停说明，“关闭当前分屏”移到终端操作菜单，退出状态在正文角落轻量提示。
- ANSI 16 色改为 HyCode 深/浅两套柔和配色，前景、选区与光标随界面主题更新；应用自己的 true color 按输出显示。新 zsh 会话仅给未定制的系统默认提示符增加目录/用户颜色，保留自定义提示符。终端采用已有 `WorkbenchScroller`：固定 8 pt 透明槽、4 pt 圆角滑块，隐藏 SwiftTerm 内建滚动条，不随系统自动隐藏设置改变正文宽度。
- 新标签从项目根启动；项目树右键“在终端中打开”，目录使用自身、文件使用所在目录。分屏继承当前分屏已报告的目录，没有 OSC 7 报告时使用启动目录，不注入项目脚本或伪称实时目录已同步。
- 默认使用环境中的系统 Shell，缺少时在后台读取当前账户的默认 Shell，查询失败才使用 `/bin/zsh`；可在终端设置指定绝对可执行路径与登录 Shell 开关。参数按 argv 传入，不把 Shell 路径拼成命令。Shell 自己读取其用户配置；HyCode 不修改配置文件。
- 字号可调 10–24，正文保留最近 2000 行。支持 ANSI/256/真彩色、Unicode、原生输入法、选择/复制/粘贴与标准终端按键；Vim/tmux/交互式 AI CLI 的真实交互仍待窗口验证。
- 终端内 ⌘F 打开自有查找条，Enter/上下按钮在输出中查找；⌘K 清除滚动历史，不向进程发送清屏命令。Escape 和 Ctrl 组合键继续由终端处理，不抢占 TUI 的按键。
- 文件拖入插入单引号转义后的路径，不追加回车；多行粘贴显示工作台确认，限制 256 KiB，过滤可注入终端控制序列的控制字符，并保留 bracketed paste。
- 点击终端识别的本地文件/目录链接可打开项目文件并按行列定位，目录定位工作台。只接受当前授权根内存在的路径；后台规范化并拒绝远程 file host、越根和符号链接逃逸。链接不是新增授权。网页链接与外部项目入口尚未接入。

## 生命周期与修改所有权

收起工具、切换标签和分屏布局保留会话及终端屏幕。隐藏视图不保留键盘焦点。Shell 退出显示退出码并保留输出，可关闭后新建会话。

关闭活动分屏/标签、切项目、关闭项目、关窗口和退出应用先使用自有工作台提示确认结束 Shell；取消保留会话。项目/窗口关闭仍经过现有未保存文档保护，然后等待所有终端回收，不通过销毁视图代替进程退出。

人工终端读取和修改磁盘文件，不直接修改原生缓冲或撤销；未保存输入不会成为命令的隐式输入，磁盘改写仍受保存指纹/冲突保护。终端是当前用户启动的本地 Shell，不将项目根目录宣称为操作系统沙箱。

人工命令的写入意图无法可靠推断，因此活动终端会话阻止内置 Codex 获取修改租约；Codex 只读对话可继续。当前 Git 集成也将写操作与活动终端会话互斥，Git 写入期间不新建终端。Codex 忙碌或文档关闭/修改预览期间不新建终端。终端不获得内置 Agent 的权限或应用私有运行配置，不传递 `HYCODE_CODEX*` 凭据变量；用户自行执行的系统 CLI 保持其自身配置。

应用重启恢复标签/目录、跨重启保活、命令分块/耗时/退出码、完整动态 CLI 语义/分支/历史补全、SSH 和远程环境尚未实现。现有 Flutter/DAP/package scripts 继续独立拥有结构化任务，不迁到人工终端。

## 输入候选

2026-10-28 用户确认采用输入时弹出的命令、子命令和路径候选，Tab 接受；交互参考 [WebStorm 的终端补全](https://www.jetbrains.com/help/webstorm/terminal-emulator.html)。首批为新建本地 zsh 会话，终端设置默认开启；其他 Shell 继续使用自身 Tab 补全。已有会话需要关闭后新建才能加载集成。

- 输入暂停 120 ms 后在光标附近显示自有圆角候选列表，含类型图标与简短说明；上下键选择，Tab 只插入，Esc 收起，Ctrl+Space 显式请求。Enter 保持提交当前命令的含义。
- 常用命令、Git/Flutter/Dart/Node 包工具/Cargo/Swift 的部分子命令与参数来自自有固定离线元数据，不执行命令探测、加载插件、读取历史或调用模型。它不代表已安装命令全集或任意 CLI 的完整语义。
- 例如 `flu` → `flutter`、`git ch` → `checkout`、`flutter pub g` → `get`、`flutter build ma` → `macos`；`cd ` 只列目录，其他参数位置可以列项目文件。路径每次最多读取当前授权根内一个目录的前 512 项，最多展示 40 个结果；文件名含空格、引号或 Shell 元字符按当前引用上下文转义。枚举使用逐层 `openat(O_NOFOLLOW)` 与 `fstatat`，防止检查后目录被替换成符号链接；不列符号链接或特殊文件，也不自动扩大授权范围。
- 仅在 zsh ZLE 报告正在编辑单条命令、光标位于行尾、终端持有焦点且未在备用屏时展示。多行、管道、重定向、展开式与行中编辑交给 Shell 自己处理。命令开始、输入法组合、滚动历史、失焦、隐藏与关闭会撤销候选，其他程序的 Ctrl+Space/Tab 保持原输入。

每个显式新建会话在私有临时目录中生成固定 zsh 启动中继，按原顺序载入用户本来会读取的配置；保留 ZDOTDIR 的 set/export 属性和原目录，不改写配置文件。通过保留既有 hook 的 ZLE 机制报告编辑/结束状态；有界 OSC 7777 使用每会话随机 token 校验，命令行以 Shell 报告为准。

接受动作当场占据既有有序输入队列，在后台写入单个私有请求并触发固定 ZLE widget；Shell 再比较完整原输入和光标后追加后缀，确认消费的 UUID 经状态报告返回后才允许下一次接受。过期候选不修改输入，后续 Enter 排在接受之后；接受动作本身不发送回车。请求文件消费后清空，进程退出后删除临时目录。此文件仅用于短暂输入传递，不是历史或输出日志。真实用户配置、交互程序、输入法和实际候选窗口仍待人工验收。

## 实现与预算

| 文件 | 职责 |
| --- | --- |
| `app/macos/Sources/Terminal/TerminalWorkspaceController.swift` | 唯一项目终端/标签/分屏会话所有者，显式启动、关闭确认与跳转 |
| `app/macos/Sources/Terminal/TerminalPaneSession.swift` | 单分屏屏幕、输入队列、输出消费、目录提示与视图生命周期 |
| `app/macos/Sources/Terminal/HyCodeTerminalView.swift` | AppKit 终端主题、焦点、查找快捷键、自有菜单、粘贴与拖入 |
| `app/macos/Sources/Terminal/TerminalPanel.swift` | 自有工具标题、标签、递归分屏、搜索和设置 |
| `app/macos/Sources/Terminal/TerminalPalette.swift`、`TerminalViewport.swift` | 深浅默认调色板、固定槽和共享细滚动条 |
| `app/macos/Sources/Terminal/TerminalCompletionOverlay.swift` | 光标附近自有候选列表与插入/选择提示 |
| `packages/HyCodeWorkspace/Sources/Terminal/TerminalCompletion.swift`、`TerminalCommandCatalog.swift` | 可独立测试的命令词解析、转义、固定元数据和受限目录枚举 |
| `packages/HyCodeWorkspace/Sources/Terminal/TerminalShellIntegration.swift` | 会话私有 zsh 中继、ZLE 状态与带确认的有序插入 |
| `packages/HyCodeWorkspace/Sources/Terminal/` | 无应用宿主的配置、拓扑、授权根链接解析与 PTY I/O 所有者 |
| `bindings/CHyCodeTerminal/` | 窄 C 进程/尺寸/信号适配，显式 FD 与 wait 所有权 |
| `tools/TerminalHost/main.c` | 新进程中 setsid/控制终端/前台进程组，再 exec 目标 Shell |
| `tools/TerminalProbe/main.swift` | 固定临时样本的 headless 模拟器/真实 PTY/阻塞输入探针，可独立用 ASan 运行 |

采用固定 SwiftTerm 1.20.0（MIT），只使用终端模拟和 AppKit 嵌入；自有 PTY 适配不调用上游 `LocalProcess`，避免在已有 Swift 多线程进程中 fork 后继续执行 Swift。`posix_spawn` 建立 FD 与工作目录，随包 C helper 在全新进程获得 controlling tty，再直接 exec，不创建应用宿主或外部终端窗口。

每个 `TerminalProcess` 私有 utility 队列串行拥有非阻塞 PTY、Dispatch read/write/process sources、输入和退出等待者。每次最多投递 32 KiB 输出，消费者完成后才继续读取，使用内核背压；单次 UI 消费后让出至少 8 ms，不丢弃活跃输出或按字节建立无界 MainActor 任务。视图/模拟器仍在主线程工作；其真实延迟尚未测量，不能据有界投递宣称解析已全部离开 UI 线程。

原生输入排队上限 256 KiB，键盘/协议回复沿同一顺序提交；超过预算明确提示。尺寸限制 2–500 列、2–300 行。进入模拟器前在 utility 队列执行有状态过滤：OSC 白名单且最多 8 KiB（包含有 token 校验的自有 7777 报告）、CSI 最多 256 字节、普通 ESC intermediate 最多 16 字节，拒绝可能无界展开的计数操作；分片 UTF-8 不作为 C1 控制字节。DCS/APC/SOS/PM、图像、剪贴板/文件传输与其他 Shell 集成载荷不透传，嵌套 ESC/C1 不能绕过预算。未结束控制字符串只保留固定状态，不能在上游持续积累。终端图像协议、DCS 透传与相关扩展不在当前支持范围；底层 Kitty 缓存还限制为 8 MiB，不报告 Sixel。普通 UTF-8 在后台按完整标量组装，当前 Unicode 字素簇最多 32 个标量，过长组合以替换符显示并提示；多个旗帜、分解韩文和常见 emoji 不合并计数。这些是分项预算，不是终端总 RSS 的绝对上限；上游永久复杂字符缓存的长期回收仍属后续性能项。

关闭在后台枚举同 session 成员，核对会话身份与进程起始时间，向所有所属组的成员及未回收 leader 发送 HUP，再按时升级 TERM/KILL；普通后台 job 也在清理范围，leader 保持可等待至清理完成，避免延迟信号命中复用 leader PID。Darwin 的退出事件可能早于进程可回收，使用 WNOHANG 和 20 ms 重试，不在 I/O 队列阻塞等待；显式停止另在 1.25 秒独立推进 FD 关闭。wait 与 FD 关闭有独立清理责任；取消 Dispatch source 后在 cancel handler 释放描述符。主动 setsid 脱离会话、守护化并改变会话身份的子任务不能承诺全部回收，不对其他应用或全局同名进程发信号。

依赖版本、来源和原始许可哈希见[机器台账](../third_party/terminal-dependencies.json)、[第三方通知](../THIRD_PARTY_NOTICES.md)。SwiftPM 同时锁定上游 CLI 的 ArgumentParser，但它不链接进 HyCode。资源 bundle 与 helper 由 `build_macos.sh` 一并打包；不从本机其他终端/IDE 提取组件。

## 验证约束

通用测试仅用生成临时路径、固定非登录 `/bin/sh -c`、禁用全局启动且 HOME/配置均生成的固定 zsh、随包 C helper、真实无界面 PTY 和 headless SwiftTerm 内核；不创建 `NSApplication`、`TerminalView`、窗口，不读取用户 Shell 配置、使用剪贴板、发声音或执行用户项目命令。

测试覆盖拓扑折叠/上限、环境与参数、授权根/符号链接、分片 Unicode/ANSI/备用屏、旗帜/分解韩文/长组合、CRLF 多行粘贴策略、控制序列预算与注入绕过、controlling tty、初始尺寸/resize、有序输入、Ctrl+C、忽略信号的强制关闭、同 session 独立后台组回收和关闭后拒绝启动/输入。终端 UI、IME、焦点、真实 TUI、目录报告、粘贴弹层、用户 Shell 环境和帧率保留为未验证；不得通过启动应用补齐本批证据。完整规则见[开发约定](DEVELOPMENT.md)。

2026-10-28 后台结果：`check_native.sh` 完整通过 37 项 Rust、310 项 Swift（51 个 suite）及 4 项 Node 测试，并通过格式、Clippy、C 头/原生适配、固定依赖、离线规则编译与文档检查。终端另在源文件 SHA-256 一致的独立包通过 20 项测试、同组 20 项 AddressSanitizer 测试和 3 项使用随包 helper 的 ASan 静默探针；Clang 静态分析与只读独立复核也已完成。测试曾复现阻塞输入下的退出回收死锁，改为非阻塞 wait 与独立 FD 关闭期限后正常/ASan 回归均通过。

Release 配置的 arm64 本地开发包已构建，带 C helper、SwiftTerm 资源 bundle 与依赖台账。终端功能批次为 build 48，当时并行 Git 集成共享包为 0.1.0 / build 49；此记录保持对应包内版本和文件哈希，后续包以各批次证据为准。应用未启动、安装、正式签名或发布。完整后台日志、源文件与产物哈希、并行改动说明和验证限制见[本批证据](evidence/2026-10-28-build49-terminal.json)；这些结果不表示真实窗口或终端性能已验收。

## build 52 样式与输入候选验证

整仓静默检查通过 37 项 Rust、328 项 Swift（53 个 suite）和 4 项 Node；其中新增 13 项候选/生成配置/ZLE 真实 PTY 用例。终端 33 项测试在源文件 SHA-256 一致的独立包再次通过 AddressSanitizer，覆盖原有进程生命周期与本轮插入、引用、越根、过期状态、同 PID 内建 read、立即 Enter、自定义配置顺序和 ZDOTDIR 未导出属性。最后的 AppKit 焦点/快捷键适配通过 Release 编译与独立源码复核。

0.1.0 / build 52 已构建为 arm64 本地开发包，未启动、安装或正式签名/发布；窗口、滚动手感、弹层位置、IME 与真实 TUI 仍未验收。产物/源码与日志哈希见[本轮证据](evidence/2026-10-28-build52-terminal-style.json)。

提交范围另从共享工作区拆成只含终端的独立源码快照，保留并行 Git 功能未提交改动。该快照通过 301 项 Swift（51 组）、文档/固定依赖/格式检查和 Release 产品编译；没有覆盖当前集成开发包或启动应用。独立快照源码树与日志哈希也记录于上述证据，与先前含并行 Git 的 328 项集成检查分开计数。

## 独立静默探针

`swift build --jobs 2 --product HyCodeTerminalProbe` 编译纯 CLI。随后可显式运行 `swift run --skip-build HyCodeTerminalProbe build/HyCode.app/Contents/MacOS/HyCodeTerminalHost`，仅创建自有临时 HOME 和固定非登录 Shell，完成模拟器、PTY 输入/尺寸及阻塞输入退出三项检查；它不会打开应用。固定 helper 路径必须指向本项目构建产物，不把任意外部可执行文件当作测试替身。
