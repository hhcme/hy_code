# ADR 0003：Rust 文本修订与 macOS 原生输入/保存

- 状态：已采用基础实现；后台验证见[编辑说明](../EDITING.md)，窗口未验证
- 日期：2026-10-21
- 范围：单击文本文件进入编辑、可关闭的默认自动保存

## 决策

1. Rust TextDocument 拥有完整文本、编码、BOM 与修订。首个有界原型使用 String 与局部 UTF-16 索引提示，不新增 Rope/语法依赖；8 MiB 是当前资源边界，不是性能承诺。
2. AppKit TextKit 1 / NSTextView 承担原生输入、IME、布局及每文档 UndoManager。它是当前唯一撤销历史；Rust 不另外维护和重放撤销。
3. NSTextStorage 原语捕获准确增量，UI 采用乐观输入投影，后台串行发送 UTF-16 替换及预期修订；错误保留投影并禁止错误状态继续保存。引用：[Apple NSTextStorage](https://developer.apple.com/documentation/appkit/nstextstorage)。
4. 文档句柄和字节通过追加 C ABI 接口传递，独占串行使用且明确释放，不改变原目录 ABI。保存只为对应修订编码一次全文，不在每次键入复制全文到 Rust。
5. 平台文件协调/描述符操作放在同一后台文档 actor，Rust 不创建窗口或直接持有系统授权。沿用工作区 access lease；原生文件权限、元数据和文件协调属于 macOS 适配层。引用：[Apple 文件协调](https://developer.apple.com/documentation/foundation/nsfilecoordinator)。
6. 自动保存默认开启，约 800 ms 防抖，组合态暂停；设置关闭后保留手动保存。所有关闭入口共用保护和排空，不让迟到保存与丢弃/重开交错。

## 限制

当前为基础纯文本编辑，尚无正式 Rope、跨文件事务、崩溃草稿、高亮、行号、多光标、文件监听或 LSP。原生 IME/Undo/焦点、窗口代理转发、旧系统与实际性能未运行 GUI 验证。

安全落位使用同目录临时文件、元数据保留及 rename，提交前检查字节、身份与版本。协调/锁定不提供对不参与协调的任意外部写入的原子 compare-and-swap 保证；完整规则与验证边界见[编辑说明](../EDITING.md)。未来编辑内核变化应保持单一文本/撤销所有者和修订契约，不能让两套历史独立修改同一文档。
