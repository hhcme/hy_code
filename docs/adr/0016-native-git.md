# ADR 0016：原生 Git 工作流与受限外部 Git

- 状态：G1/G2 首批采用；窗口、真实认证、旧系统和大型仓库性能待验证。
- 日期：2026-10-28。
- 关联：[Git 范围与验收](../GIT.md)、[编辑所有权](0003-text-editing.md)、[Codex 互斥](0014-codex-agent.md)、[终端](0015-native-terminal.md)。

## 背景与决策

用户确认参考 WebStorm 的独立提交面板、中央差异标签和底部 Git 日志，实现 HyCode Git。采用系统已安装的 **Git CLI 2.48+**，通过 Swift actor 和固定 argv 调用；本机验证 Git 2.54.0（Apple Git-157），不把本机版本当最低版本兼容性证明。优先固定 Xcode/CommandLineTools 的实际 Git 或 Homebrew Git，不调用可能弹出开发工具安装器的 `/usr/bin/git` shim。不自动安装，不随应用复制 Git。

SwiftUI/AppKit 负责原生界面；无 GUI 的 GitRepository actor 独占仓库操作、候选与进程；MainActor GitWorkspaceController 独占界面状态、草稿和请求代次。Git 不进入 Rust 文本 ABI，也不建立第二份正式编辑文本。build 53 的完整 UTF-8 工作版本差异右侧复用 EditorDocument 持有的同一 NativeTextEditor/Rust owner；原生光标、选区、IME、撤销和保存保持同一所有者。历史/index/统一与省略上下文投影只读；未保存快照在私有 Git home 后台比较且不构造提交候选，精确 UTF-8 正文与已审查磁盘一致后才允许选择。

build 51 根据用户实际截图修正投影层：CLI 补丁头不进入正文，普通文件优先完整上下文，达到输出/行数预算才重试一次紧凑上下文并标明省略；超时/取消不重试。正文、版本头与选择控件共享同一原生分栏几何；变化块导航来自实际增删改连续段。数据输入、索引提交事务及远端策略保持原所有者，视觉修正不赋予正文写入或放宽项目执行权限。

不采用 libgit2/gix：首批直接使用 Git 自身的对象、index、worktree、引用和远端协议行为，避免同时实现新索引/协议语义与原生界面。代价是外部工具可用性和不同安装布局必须独立验证；沙箱、受限配置、超时、输出预算和后续版本兼容属于维护责任。Git 上游许可为 GPL-2.0；HyCode 不链接或分发其二进制/源码，外部 Git 仍由安装来源提供。自有适配代码保持仓库 MIT，见[依赖台账](../DEPENDENCIES.md)。

## 仓库、快照与候选

- 只从授权项目根发现 `.git`，不递归或向祖先静默扩权。普通工作树、Git 管理目录与公共管理目录分开；linked worktree 指向范围外时，用户主动授权该管理目录，授权持有到任务关闭。子目录项目和多仓库管理仍待扩展。
- status 使用 porcelain v2 + NUL，日志/引用/文件列表用固定字段和 NUL；严格解码、校验 OID 和相对路径。Unicode、换行和前导短横线路径按字面 argv 传递。链接只处理自身，不穿越链接读取外部源；文件哈希使用 nofollow/openat 描述符与前后元数据复核。
- 快照包含完整 HEAD、分支、完整 index 哈希、分层状态；候选还包含相关路径的磁盘 SHA-256。勾选不执行 stage；内容变化后候选失效。真实 index 模式另行显示，双层变化在普通选择模式保守阻止。
- 读取、差异、筛选、日志图和文件分组离开 UI 线程。请求 ticket + 仓库代次防止旧任务覆盖新文件、消息或新项目；Amend 的消息请求另绑定 HEAD 和输入修订。

## 提交与索引安装

选择提交不能把未选文件的已暂存内容一并提交，也不能用全仓库 add/reset 暂存再还原。

1. 取得公共管理目录的应用内独占调度与编辑器现有修改所有权，排空在途保存，冻结编辑/自动保存；检查消息、操作状态、HEAD、index 和候选。
2. 用 `O_EXCL` 取得真实 `index.lock`，记住 inode；不删除其他进程的锁。候选 index 在私有目录中从 HEAD/空树或真实 index 建立，使用 `GIT_INDEX_FILE` 进行有限路径操作。
3. 选择模式加入捕获的完整文件，或将已复核的部分候选以 hash-object / update-index 写入替代 index；真实 index 模式直接用该 index。`write-tree` 得到确切提交树。原 index 的未选路径、暂存删除/重命名等通过 NUL `ls-files --stage` 和 `update-index --index-info` 保留；部分选择原来仅暂存的文件保留原 index，使未选块继续暂存；原来仅未暂存的文件将 index 对齐候选提交，使未选块继续留在工作区。新真实 index 在锁文件中完整写入并 fsync。
4. `commit-tree` 创建对象；普通提交父节点为旧 HEAD，Amend 使用原父节点并保留原作者及原时区。签名/hooks/过滤器尚无可信执行流，若仓库要求则拒绝写入，不静默跳过。
5. 再次验证候选、HEAD 和 index，以 `update-ref --no-deref <明确引用> <新OID> <旧OID>` 比较并交换分支；到提交点后的短临界区不被取消打断。核对 symbolic HEAD，随后原子安装已准备的 index。
6. 提交点前失败不改真实 index；引用已更新而 index 无法安装或 HEAD 外部变化时，保留自有准备锁及恢复信息，明确报告新提交/引用和实际状态。不能承诺引用与文件系统 rename 跨资源绝对原子，也不擅自反向改写外部并发更新。

stage/unstage/恢复到 HEAD 同样使用自有 index.lock + alternate index；丢弃未暂存以固定 index 树作为来源。不可普通撤销的丢弃确认绑定先前捕获版本，确认后不重新采样较新正文作为已批准内容。取消或 Git 多文件失败可能留下部分工作树变更，结果要刷新并报告；未跟踪项不执行 clean/delete。

## 进程、配置与认证

每次调用独立私有 HOME/XDG/TMP，不继承整个环境，不读系统/全局 Git 配置。只接受授权本地仓库配置及明确启用的 worktree 配置；配置 BOM/续行归一后拒绝 include/includeIf，拒绝对象 alternates 和不安全路径。读操作禁用 pager、editor、fsmonitor、外部 diff/textconv、自动维护/懒获取及递归子模块；写入前检查 hooks、过滤器、签名、transport/helper/URL 重写等策略，尚无信任机制的外部执行明确失败。

固定 Seatbelt profile 限制实际 runtime、授权项目/管理目录、私有临时目录和用户显式本机 remote；只允许固定 Git/helper/SSH 执行，读取凭据目录和 Keychain 另有 deny。非远端操作禁止网络。进程使用已有 OwnedToolProcess，独立组/nice 优先级、有界 stdout/stderr、超时和取消，TERM 后按需 KILL，等待自有子进程回收。无需 shell 拼接项目文本，不按名称结束其他应用。

远端只接受单一 HTTPS、SSH 或本地 URL，禁止内嵌密码、HTTP、自定义协议和多 URL 歧义。Fetch/Pull/Push 绑定已展示的 literal URL，固定 upload/receive-pack；Push 使用预览 OID 到明确目标分支，不使用随后可变化的源分支。不自动 force、推标签或全部分支。成功后的本地 tracking ref 用旧值比较更新；本地上游配置失败另报，不能否认远端已经成功。Pull 首批仅快进，要求干净工作树，不自动 stash/merge/rebase。

本地 file remote 另有 [GitLocalRemotePolicy](../../packages/HyCodeWorkspace/Sources/Git/GitLocalRemotePolicy.swift)：仅支持普通 bare、标准对象/引用目录、无外部管理布局；配置只接受默认存储字段、objectformat 和明确的 `receive.denyNonFastForwards/denyDeletes`。未知配置、自定义 hooksPath、uploadpack.packObjectsHook、include、alternates 和不安全链接明确拒绝。原生沙箱外检查 hooks 权限/可执行性；除 `.sample` 外的可执行、链接或特殊项停止操作，不运行或默默跳过服务器策略。原因由临时仓库对照确认：`deny process-exec` 会让沙箱内 hook 被判为不可执行，Git 随后可能成功更新引用；不是外层 `-c core.hooksPath` 经 GIT_CONFIG_PARAMETERS 传入接收端。不能以沙箱内 Git 的 hook 发现代替原生预检查，不能通过放开项目执行修复。该保守限制针对本地 remote；真实 SSH/HTTPS 接收端在服务器自己运行，认证与策略另验。

无交互认证：禁止 askpass/credential helper/浏览器，TLS 与 SSH 主机验证保持开启。HTTPS 当前没有应用自管凭据流程；SSH 仅在用户显式远端操作时转发现有 SSH_AUTH_SOCK，并只读现有 known_hosts，禁用私钥/SSH config/密码/Keychain 和自动登记主机。实际认证尚未验证。Git 不使用任何 HyCode/Codex 模型密钥。

## 互斥、资源与关闭

GitScheduler 全局最多两个读取或一个写入，以公共管理目录协调 linked worktree。写操作复用 EditorWorkspace 外部修改所有权；与运行中的 Codex、终端、Pub/package、Flutter 和语义修改互斥，相关未保存输入不能自动保存或覆盖。失败/结束按实际变更重载干净文档、目录与分析状态。项目关闭先停止准入、取消并等待读取/写入/观察器，最后释放授权与缓存。

stdout 8 MiB、stderr 256 KiB；本地 20 s、远端 90 s。status 20,000 项、refs 10,000 项、index 64 MiB；差异输入 8 MiB/20,000 行/单行 16,384 UTF-16 单位；只保留活动差异。部分提交候选为有界不可变数据，单文件 8 MiB / 合计 32 MiB；受限 UTF-8 普通单路径且无内容/编码/换行转换，详见 [Git 范围](../GIT.md)。历史每页 200/缓存 2,000，控制台 100 条且单条 8 KiB。超限显式失败或元数据降级，不能用截断结果提交。流式候选哈希不代表大型仓库性能已验收。

## 验收与未完成事项

临时仓库与本机 bare remote 覆盖选择提交保留未选暂存、双层文件、首次/Amend、删除/重命名、外部锁/过期快照、stage/unstage/丢弃、固定推送预览、拒绝非快进、分支/历史、显式 worktree 授权、配置/链接限制、输出超限和超时回收。纯交互模型覆盖标签身份、消息/勾选请求代次、真实父子图和独立工具。完整检查及开发包证据见[工作台](../WORKBENCH.md)，不可把源码审查等同真实交互。

真实窗口/IME/VoiceOver/滚动/分隔、SSH/HTTPS 与用户身份、大型历史/状态/GB 性能、Git 2.48 和 macOS 14 覆盖仍待验收。G3 同文档差异编辑、工作区块级还原及受限块选择已接入；行标记、Stash、Merge/Rebase/冲突工具未接入；初始化/克隆、Shelf、blame/高级历史、多仓库等见 [Git 分期](../GIT.md)。
