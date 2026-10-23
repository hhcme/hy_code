# 图片只读预览

更新：2026-10-23，build 34。用户要求图片可直接预览、缩放，暂不编辑；首版仍仅 macOS / Apple Silicon。图片与文本按文件后缀分开进入对应会话，不把 PNG 等二进制交给 Rust 文本解码，也不为图片建立自动保存、撤销或语义缓冲。

## 使用

- 项目树单击图片进入临时标签，双击或固定后持续保留；标签、面包屑和文件右键沿用工作台规则。
- 默认适应窗口，大图缩小，小图不放大；工具条提供放大、缩小、比例预设、适应窗口和 100%。100% 指一个源图像素对应一个逻辑点，Retina 实际屏幕像素比例由系统处理。
- 拖动图片平移；触控板捏合或 ⌘/Control 滚轮以指针为中心缩放；普通滚轮与细滚动条平移。放大上限 1600%，键盘预设为 5%–1600%，适应模式可更小。
- 图片菜单提供 ⌘= / ⌘− 放大缩小、⌥⌘0 适应、⌥⌘1 原始尺寸；保留工具窗口已有的 ⌘0 / ⌘1。图片获取焦点后，方向键平移，双击画布回到 100%。
- 可切换透明棋盘、浅色或深色背景，棋盘只出现在图片范围；工作台保持纯色。显示源尺寸、格式、只读状态和文件大小。
- 切换标签保留缩放与滚动位置，释放非活动图片的像素。重新激活时后台重新解码；重试/重新载入不会修改原文件。暂不监听图片磁盘变化自动重载。

## 格式与范围

| 格式 | 实现 / 样本范围 |
| --- | --- |
| PNG、JPEG、GIF、TIFF、BMP | ImageIO；生成样本解码、透明度、方向和多帧首帧检查 |
| WebP | ImageIO；自有 3 × 2 无损透明样本检查 |
| JPEG 2000、ICO、ICNS、HEIC、AVIF | 当前系统生成样本解码；ICO/ICNS 在最多 128 个候选中选择最大可用表示 |
| APNG、PSD、TGA、EXR、HDR、PNM、DDS、KTX、JPEG XL、部分相机 RAW 等 | 按后缀路由，实际解码取决于安装系统的 ImageIO；尚未逐项样本验证，不等于全部可用 |
| SVG | 固定 resvg/usvg 0.48.1；本地自包含路径、形状与文字，先栅格化为最长边 2048 px 预览再缩放。文字按需在后台一次发现并缓存系统字体；真实字体效果尚未验收 |

GIF、APNG、WebP、TIFF 等多帧/多页内容本版只显示首帧，并明确提示；没有播放或逐页编辑。SVG 不执行脚本，也不读取其资源路径或网络地址。本批明确拒绝 `image`、`foreignObject`、`use`、`filter`、`mask`、`pattern`、`clipPath`、`marker`、`tref` 和外部 href；复杂 SVG 显示原位错误，不把缺失部分伪装成完整结果。SVGZ 尚未接入。

ImageIO 的格式支持随系统变化；当前样本环境 macOS 27.0.1，部署声明仍为 macOS 14，旧系统和 RAW 不保证与本机一致。实际类型以内容识别为准，例如 JPEG 后缀中的 PNG 仍按 PNG 解码。损坏、不完整或超限文件显示错误与重试，不回退成可编辑二进制文本。

## 所有权与预算

[ImagePreviewDocument.swift](../app/macos/Sources/Preview/ImagePreviewDocument.swift) 独占标签的查看状态和加载代次；[ImagePreviewLoader](../packages/HyCodeWorkspace/Sources/Preview/ImagePreviewDecoder.swift) 的共享串行 actor 执行阻塞读取和解码，任务为 utility 优先级。关闭、切走和重载会取消旧任务，返回结果前再次检查活动状态与代次；访问权限由原有 `WorkspaceAccess` 保活到在途调用结束。

[PreviewFileIO.swift](../packages/HyCodeWorkspace/Sources/Preview/PreviewFileIO.swift) 用目录描述符和 `openat/O_NOFOLLOW` 逐层读取已授权目录中的普通文件；拒绝路径穿越、符号链接和特殊文件，读取前后核对身份/大小/时间。只读图片可读取普通硬链接，不引入写入能力。文件上限 64 MiB、源边长 65535、源像素 160 MP，位图缩采样最长边 4096 并转为立即解码的 sRGB RGBA8。单个投影上限约 64 MiB；这不是整个解码器或应用的硬内存上限，系统框架还有临时开销。

SVG 上限 2 MiB、XML 4096 节点/128 层、路径属性合计 128 KiB、文字/style 合计 2 KiB；在转换前拒绝可扩展引用与复杂效果，转换后再次限制 8192 渲染节点、100000 路径段及累计 8 MP 隔离图层面积。避免仅限制输出位图却允许嵌套透明组或滤镜累积大量中间表面。

[image_ffi.rs](../crates/hycode-core/src/image_ffi.rs) 的新增 C ABI 借用 UTF-8 SVG，返回预乘 RGBA8 和元数据；Swift 复制后配对释放像素/错误缓冲，panic 不穿过 ABI。同步 ImageIO/resvg 调用期间不能强制中断，取消在阶段边界生效，不宣称硬超时。原文件始终不写入；图片也拒绝语言服务的文本修改预览。

[ImagePreviewViewport.swift](../app/macos/Sources/Preview/ImagePreviewViewport.swift) 只在固定视口画布绘制解码后的像素。巨大缩放尺寸只用于无内容图层的滚动几何，不分配同等大小的绘图 backing；透明滚动条固定占位且没有右下交汇方框。缩放和平移没有磁盘读取、重解码、全文扫描或常驻帧计时器；工具条状态合并到后续主线程更新。

## 验证

新增 [Swift 图片/几何测试](../packages/HyCodeWorkspace/Tests/ImagePreviewTests.swift) 检查生成格式、WebP、方向、透明度、降采样、SVG 桥接、损坏数据、取消、安全读取、指针锚点和窗口右下边缘缩放；Rust 检查像素/错误缓冲、无效参数，以及嵌套透明组、滤镜和扩展引用的拒绝。测试不创建 NSApplication、窗口或读取用户图片；源截图仅作为需求，不作为测试输入。

本批全量 186 项 Swift（34 组）和 19 项 Rust 静默检查通过；新增图片 13 项 Swift（2 组）另通过 ASan，Rust 静态库未插桩。Release 本地包 build 34 已生成且未启动；完整记录见[后台证据](evidence/2026-10-23-build34-image-preview.json)。

依赖版本、许可和通知见[依赖台账](DEPENDENCIES.md)、[完整第三方通知](../THIRD_PARTY_NOTICES.md)与[图片新增 crate 台账](../third_party/image-preview-crates.json)，由 `python3 scripts/check_image_dependencies.py` 验证并随本地包保留。原生窗口、捏合/键鼠、屏幕绘制方向、VoiceOver、FPS 和大图性能仍未执行真实验收；后台几何和像素断言不能替代这些检查。

接口来源：[ImageIO 图像源](https://developer.apple.com/documentation/imageio/cgimagesource)、[平台支持类型](https://developer.apple.com/documentation/imageio/cgimagesourcecopytypeidentifiers())、[resvg 上游](https://github.com/linebender/resvg/tree/v0.48.1)。
