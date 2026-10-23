# ADR 0011：原生源码与受限 Markdown / HTML 预览

- 状态：接受，2026-10-23
- 范围：Markdown / HTML 同文档源码、左右分屏和只读预览

## 决策

保留 AppKit TextKit/Rust 文档所有权。Rust 使用固定 MIT pulldown-cmark 渲染修订绑定的 Markdown 投影；HTML 沿用源内容。系统 WebKit 仅承载右侧静态预览，NSSplitView 在拖动时直接更新框架，结束才持久化比例。切走释放预览，不启动第二个编辑器或服务端。

原生私有 URL scheme 只供给授权根内受限 CSS/已栅格化图片；CSP、禁用页面脚本、预装 WKContentRuleList 和导航拒绝共同限制页面能力。固定滚动桥使用隔离内容世界，只有有界行号/比例消息，无命令或文件接口。网络规则准备失败则不加载。渲染、文件读取、解码在后台，修订/代次/取消防止旧结果覆盖。

## 取舍与验收

HTML 首批不执行 JavaScript 或开发服务器，不支持远程、data URL、字体和媒体；Markdown 块级源映射与 HTML 比例联动均为近似。原始 SVG 不交给浏览器，复用受限栅格化。资源预算、所有权、来源与验证见[专题](../MARKUP_PREVIEW.md)。后台模型/FFI/ASan/编译与真实 WebKit 窗口分别记录；测试不实例化 WebView。
