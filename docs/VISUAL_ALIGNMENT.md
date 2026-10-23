# WebStorm 截图视觉对齐

更新：2026-10-23，build 33。根据用户在本会话提供的 WebStorm Islands Dark 与 HyCode 截图，继续调整原生工作台的尺寸和字形基线。用户原图仅在本机读取和采样，不复制进开源仓库；没有打开、激活、截图或操作 WebStorm/HyCode 窗口。

## 参考与目标

两幅完整截图均为 3840 × 1988 像素。按 2× backing scale 换算为点，采样忽略边缘抗锯齿和覆盖的文字/图标；边界有约半点误差。UI 字号与内边距部分由字形边界和现有原生控件推导，不能由截图准确恢复所有字体指标。只读取了本机参考应用的外观/字体配置，确认 Islands Dark，未读取或复制插件/图标/字体/主题实现。

| 位置 | build 31 | build 32 目标 | 依据 |
| --- | --- | --- | --- |
| 标题区域 | 44 pt | 43 pt | 参考内容起点约 y=86 px |
| 内容区左右壳体 | 未额外留白 | 各 1 pt | 左面板起点约 x=82 px，工具条 40 pt |
| 相邻面板分隔 | 6 pt | 5 pt | 参考连续色带约 10 px |
| 面板标题 | 顶部 40、底部 36 pt | 均为 40 pt | 参考上/下标题高度约 80 px |
| 工具条按钮 | 30 pt，步进 36 pt | 30 pt，步进 40 pt | 色块约 60 px、相邻中心距约 80 px |
| 工具条首末按钮 | 上 4 pt、底部随步进多留白 | 上下均 3 pt | 参考端部色块与面板边界约 6 px；底组独立贴底 |
| 项目树首行 | 无额外顶部留白 | 顶部 5 pt | 参考根行文字相对标题底边的位置 |
| 项目树行背景 | 左右各 12 pt | 左右各 16 pt | 将外缘/滚动槽一起计入，对齐可见行背景；保留轻微圆角 |
| 状态栏 | 26 pt，11 pt 字 | 36 pt，12 pt 字 | 参考内容终点约 y=1916 px，至截图底端 72 px |
| 项目/标签/工具标题 | 部分 12 pt | 13 pt | 统一 UI 文本基线，采用系统字体 |
| 编辑文本 | 13 pt、系统默认行距 | 14 pt、最小 22 pt 行高 | 参考相邻代码行约 44 px；保留字体 fallback 所需高度 |
| 编辑文本内边距 | 14 × 12 pt | 10 × 8 pt | 与行号槽和标签底边共同对齐 |
| 行号 | 11 pt、最小 50 pt 槽 | 12 pt、最小 52 pt 槽 | 与代码行及断点区共同留白 |

保留已匹配的纯色：外框 `#26282C`、内容 `#191A1C`、工具选中色 `#3871E1`、10 pt 面板圆角。参考应用截图中的项目渐变背景不采用，遵守用户要求的纯色背景。保留透明滚动轨道、固定 8 pt 槽/4 pt 滑块、完整文件名与横向滚动，以及整行轻圆角悬浮/选择。

## 实现边界

- [WorkbenchStyleMetrics.swift](../packages/HyCodeWorkspace/Sources/WorkbenchStyleMetrics.swift) 是尺寸与轨道几何的唯一来源；SwiftUI/AppKit 与面板分隔共用，避免按钮、拖放插入线和面板分别使用不同常数。四角显隐动画和分隔指示所有权保持不变。
- 系统交通灯仍是原 NSWindow 按钮，不替换图像、父视图、大小、动作或无障碍。仅通过公开 `standardWindowButton` 和坐标转换调整位置；窗口布局/缩放/退出全屏后重新对齐，全屏期间跳过。真实系统布局时序与点击区域仍待窗口验收。
- 嵌套 NSHostingView 不再采用额外 safe-area 区域；外壳统一安排标题和面板。原生项目树显式裁剪到自身范围，避免其绘制越过标题或岛屿边缘；这不是对旧截图中所有空白原因的运行时证明。
- 编辑字体与段落样式只作用于原生显示投影。初始段落属性在挂接文字增量回调之前设置，不增加第二份正式文本、撤销历史或语义索引。未引入外部字体；系统字体与参考应用字体的字形、抗锯齿和 ligature 不保证一致。
- 不为参考应用尚未接入的功能增加假按钮或假状态。本批不改变项目初始四角显隐，不恢复目录内容标签，也不自动运行项目脚本或服务。

## 验证

[WorkbenchStyleTests.swift](../packages/HyCodeWorkspace/Tests/WorkbenchStyleTests.swift) 在无 GUI 宿主中检查：最小窗口中全部 11 个工具的上下分组不重叠；插入槽与按钮共享位置且标记不越界；系统按钮保留大小、按像素取整并位于头部预留区；壳体留白后中央与底部仍满足既有最小尺寸。既有四角组合、动画反向、缩窗、拖动状态与工具预览像素用例继续运行。

检查、开发包及源码哈希见[build 32 后台记录](evidence/2026-10-23-build32-visual-alignment.json)。AppKit/SwiftUI 只构建，不作为测试宿主。没有真实窗口的逐像素差分、键鼠/VoiceOver/IME 操作或 FPS 测量；不能以静态参数、纯几何测试或构建通过宣称已经完全像素一致。

相关平台接口：[NSWindow 标准按钮](https://developer.apple.com/documentation/appkit/nswindow/standardwindowbutton(_:))、[NSHostingView safeAreaRegions](https://developer.apple.com/documentation/swiftui/nshostingview/safearearegions)。


## build 33 整体覆盖

本轮从框架尺寸扩展到应用已有的各类界面。以下“已接入”表示源码接入和构建范围，不表示真实窗口像素、输入或性能已经验收。系统字体、原生文本编辑和系统复选框保留其平台行为；不复制 JetBrains 实现或插件资源。

| 界面 | 本轮调整 | 状态 |
| --- | --- | --- |
| 外壳、四角、树、编辑器 | 沿用 build 32 共享几何、纯色、轨道/行高与像素取整 | 已接入；窗口未验收 |
| 项目切换 | 512 pt 无箭头弹层；52 pt 项目行；28 pt 操作/分组；分组细线；方向/Tab/Home/End/Enter、Escape | 已接入；键鼠未验收 |
| 欢迎页、文件信息、打开标签、项目概览 | 共用项目行、13 pt 正文、12 pt 次要文本和紧凑留白 | 已接入 |
| 标签、树、停靠图标右键 | 共用菜单宽度、圆角、分组、禁用、勾选与子级；保留原命令和会话守卫 | 已接入 |
| 外观、标签列表、设备、运行配置、作用域菜单 | 同一菜单实现，不进入系统 NSMenu 弹出跟踪 | 已接入 |
| 补全、代码动作、悬浮更多 | 同一菜单；保留版本/选择/修订守卫与命令能力边界 | 已接入；语义协议未新增 |
| 函数参数说明 | 独立可换行/滚动说明面板，长签名不塞入单行菜单 | 已接入 |
| 分析、Pub/Web 依赖工具 | 共用 13 pt 正文、12 pt 输出、28 pt 操作/字段；分区细线与平面底色 | 已接入 |
| 调试、变量、Inspector、测试、问题列表 | 共用分段标签、行文本、字段/操作和次级工具条 | 已接入 |
| 运行配置、断点、修改预览 | 共用 48 pt 标题、平面字段、正文和底部操作；保留校验/事务行为 | 已接入 |
| 编辑设置 | 共用字段/动作与分组；跟随工作台深浅主题，内容在窗口内滚动 | 已接入 |
| 重命名、未保存确认 | 同主题业务 sheet；键盘确认/取消；一次性提交、结束期间禁用；无窗口保守取消 | 已接入；真实焦点与关闭时序未验收 |
| macOS 菜单栏、目录选择、系统权限 | 继续交由 macOS 管理 | 系统界面；不仿制 |
| Git、终端、搜索等尚无内容工具 | 仅已有空面板和共用标题 | 不添加假内容 |

[WorkbenchComponents.swift](../app/macos/Sources/Workbench/WorkbenchComponents.swift) 提供共用动作按钮、字段、分段标签和对话框标题。[WorkbenchPopupSession.swift](../app/macos/Sources/Workbench/WorkbenchPopupSession.swift) 只在用户打开弹层期间持有本应用局部监听器；普通菜单不抢编辑器 first responder，外部点击透传，窗口移动/缩放/关闭/失焦时清理。项目按钮再次点击会关闭当前弹层，延迟关闭带代次检查，避免关闭随后新打开的弹层。业务输入 sheet 可以取得键盘焦点，与非 key 菜单分开管理。

子菜单展开时通过仍存活的弱行视图实时转换屏幕坐标，不复用滚动前的屏幕位置；父菜单滚动时收起子级。宽度 220–360 pt，边缘/负坐标显示器/超高内容按可见屏幕约束；子菜单在右边不足时翻向左侧。新纯几何测试覆盖下拉翻转、行锚点、负坐标、极小屏幕和超限请求。未运行应用、操作窗口、读取剪贴板或截取桌面；没有真实输入、VoiceOver、帧率或逐像素差分结论。

平台接口遵循 Apple 的[局部事件监听与清理](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)、[文本字段样式](https://developer.apple.com/documentation/swiftui/textfieldstyle)与[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)边界。

build 33 全量静默检查 173 Swift / 15 Rust 通过，32 项相关几何/交互用例通过。最终 Release 开发包为 `build/HyCode.app`，0.1.0 / build 33、arm64、最低系统声明 macOS 14；未启动、安装或发布。源码/日志与产物指纹见[build 33 后台记录](evidence/2026-10-23-build33-full-workbench-style.json)。
