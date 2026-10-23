# 视频只读预览

更新：2026-10-23，build 35。用户确认简单预览即可。本批支持项目树单击本地视频进入独立只读标签，提供播放/暂停、进度与音量；没有视频编辑、导出或自动保存。

## 当前交互

- 打开后加载首帧并保持暂停，用户点击播放按钮或画布后才开始播放。
- 画面自动等比例适应内容区，保留黑色留白；工具条、按钮、文字、加载与错误区域沿用工作台样式。
- 底部显示当前时间/总时长，拖动进度可定位；拖动期间暂停，完成最后一次定位后按原播放意图决定是否继续。
- 音量滑块、静音开关；画布取得键盘焦点后，空格播放/暂停，左右方向键前后跳转五秒。播放结束停在末尾，再按播放从头开始。
- 切换标签、关闭、切换/关闭项目时暂停并卸载播放器；非活动标签只保留进度、音量等小型查看状态，重新进入仍保持暂停。
- 显示源画面尺寸、文件大小与只读状态。加载/编码/文件变化失败原位报错并可重新载入，不回退到文本编辑。

## 格式

本批路由 `.mp4`、`.mov`、`.m4v`（忽略后缀大小写），由 AVFoundation 检查实际可播放性、视频轨道、保护状态、时长与尺寸。后缀只用于选择预览入口，不能保证某种容器内所有编码均可播放。

后台自有小样本验证 MOV/JPEG、MP4/H.264、M4V/H.264 的元数据及一帧图像解码；样本均无音轨。其他编码、字幕/多音轨切换、HDR、旋转素材、旧系统及真实音频尚未验收。MKV、WebM、AVI、网络流和播放列表没有纳入当前路由，不分发 FFmpeg 或其他第三方解码器。

## 源码与所有权

- [VideoPreviewDocument.swift](../app/macos/Sources/Video/VideoPreviewDocument.swift)：MainActor 独占活动播放器、加载/seek 代次、KVO/时间/结束观察器以及查看状态；图片/视频由 `EditorWorkspace` 分开拥有，不建立文本文档和撤销历史。
- [VideoPreviewPanel.swift](../app/macos/Sources/Video/VideoPreviewPanel.swift)：工作台控件与 AppKit `AVPlayerLayer`；画面由原生播放层呈现，不逐帧生成 SwiftUI 图像，也不在进度更新时重建播放器。
- [VideoPreviewState.swift](../packages/HyCodeWorkspace/Sources/Video/VideoPreviewState.swift)：一项在途 seek，加一个可覆盖的最新目标；时间格式与后缀路由为纯模型。
- [VideoPreviewFile.swift](../packages/HyCodeWorkspace/Sources/Video/VideoPreviewFile.swift)：后台逐层 `openat/O_NOFOLLOW` 打开授权根内普通文件；拒绝穿越、符号链接和特殊文件，固定描述符，`pread` 前后检查身份/大小/时间，不重新解析原路径、不整文件读入内存。访问租约随最后一个文件句柄拥有者释放。
- [VideoPreviewResource.swift](../packages/HyCodeWorkspace/Sources/Video/VideoPreviewResource.swift)：AVFoundation 只得到私有 scheme 的随机 URL，utility 串行 delegate 只服务该精确 URL；外部引用采用 `forbidAll`，不开放网络/其他文件解析。取消可在每个小块之间插入，待处理请求结束后释放描述符。

元数据采用异步 `load`。切换与重载取消旧任务，metadata/KVO/time/seek 等返回后均核对 active/generation；清理先暂停、注销观察器、取消 seek 和卸载 item，再取消资源。同步系统读取或解码无法强制中断，取消为协作式，不宣称硬超时。

## 预算与验证

只接受非空、不超过 64 GiB 的普通文件；最多八个资源请求，每块最多 256 KiB，多个块之间重新进入串行队列。源画面边长不超过 8192，像素面积不超过 36 MP，时长必须有限且大于零。播放器仅提示优先预缓冲两秒；这些是本项目请求/输入边界，不是系统解码器总内存或 CPU 的硬上限。

播放进度以 250 ms 周期合并到界面，视频画面更新不经过此观察器。非活动标签不保留播放器、缓冲、时间观察器或音频播放。没有常驻帧计时器，没有新增 Rust ABI 或 Cargo/npm/Swift 外部包；AVFoundation、CoreMedia、CoreVideo 属于 Apple 平台依赖。

[视频测试](../packages/HyCodeWorkspace/Tests/VideoPreviewTests.swift) 只运行无 GUI 模型、临时普通/特殊/稀疏文件、安全分段读取、取消/租约释放及小型无音轨编码/元数据/单帧检查。测试不创建 `AVPlayer`、`AVPlayerLayer`、AppKit 窗口或应用宿主，不执行音频播放。真实播放器、首帧显示、鼠标/键盘/VoiceOver、拖动响应、后台音频与 FPS 仍未窗口验证；源码审查和离屏单帧不能替代这些验收。

全量 196 项 Swift（37 组）与 19 项 Rust 静默检查通过；新增 10 项视频测试另通过 Swift ASan。Rust 静态库及 Apple 系统框架未插桩。Release 本地包 build 35 已生成且未启动，详见[后台证据](evidence/2026-10-23-build35-video-preview.json)。

设计依据：[AVPlayer 与自定义播放层](https://developer.apple.com/documentation/avfoundation/avplayer)、[异步媒体加载](https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously)、[资源加载 delegate](https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate)、[合并视频跳转](https://developer.apple.com/library/archive/qa/qa1820/_index.html)。
