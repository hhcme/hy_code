# HyCode 品牌与应用图标

更新：2026-10-21。用户要求参照 HyHub 建立同系列的 HyCode 标识，并明确图形要能看出代码编辑器用途。

## 标识方向

主视觉为定制的 `</>`：蓝色左右代码括号与朱红色斜线，配浅瓷色圆角底板。厚笔画、适度倾斜、柔和圆角和浅立体感延续系列气质；代码符号与蓝色为 HyCode 的产品区分。不在图标中放小字号产品名、窗口细节或角标。

配色基准为钴蓝 `#1764F6`、朱红 `#FF4A2D`、浅瓷色 `#F8EBD7`。这些是设计方向，生成位图有高光与阴影，非每个像素的精确取色。图标的材质明暗不改变工作台的纯色背景要求。

## 来源与公开边界

以用户明确指定的本地 HyHub 应用图标及图标说明作只读视觉参考；其文档记载图案由 imagegen 生成。HyCode 图形由本次内置 imagegen 重新创作，不复制 HyHub 的连写字母轮廓、原图、私有源码或生成脚本。公开仓库只包含 HyCode 的新源图、自有转换脚本与本页说明，不要求访问 HyHub。本次未修改 HyHub 的任何文件、应用包或数据。

新品牌资源随本项目的 [MIT](../LICENSE) 一同提供；该声明不为参考项目的原图重新授予许可。没有引入第三方图标库、字体轮廓或运行时生成服务。

## 资源和接入

- 唯一图稿：[icon.png](../app/macos/Resources/brand/icon.png)，1024×1024 RGBA PNG，外缘透明。
- 最终设计提示词：[hycode-icon.prompt.txt](branding/hycode-icon.prompt.txt)。图案由内置 imagegen 完成，`sips` 仅导出尺寸，不另行改画。
- [build_icons.sh](../scripts/build_icons.sh) 使用 Apple 自带 `sips` / `iconutil`，从源图生成十个标准图标尺寸，再写入 `.build/icons/HyCode.icns`；转换不联网、不创建应用窗口、不改 Dock 或 Finder。
- [build_macos.sh](../scripts/build_macos.sh) 把 ICNS、同源 `HyCode.png` 放入开发包；[Info.plist](../app/macos/Resources/Info.plist) 通过 `CFBundleIconFile` 引用 ICNS。
- [HyCodeBrandIcon.swift](../app/macos/Sources/Workbench/HyCodeBrandIcon.swift) 用包内 PNG 显示欢迎页与未打开项目时的头部标识；已有项目的徽标仍用于识别具体项目。

## 验证边界

仅做图稿查看、像素/文件检查、后台转换、编译和包内资源核验。真实 Dock、Finder 图标缓存、应用欢迎页及深浅色窗口中的外观仍待验收；不为图标检查启动应用、重启 Dock 或刷新系统缓存。

## 本轮后台结果

build 10 已完成 Release 打包。源 PNG 为 1024×1024 RGBA，四角 alpha 为 0；ICNS 导出十个文件名对应的尺寸均正确，四角透明，1024 px 帧与源图像素一致。包内 PNG 与源图、ICNS 与生成文件分别逐字节相同，Info.plist 图标名与资源名一致；原始记录见[资源核验](evidence/2026-10-21-build10-brand.json)。源图 SHA-256：`5ea867535f2a97ceffda8a59dc099d301cca190496908dc2bbf53e3cd7557244`。

本地像素检查使用已安装的 Pillow 11.3.0，仅为本轮检查工具，不是应用或构建依赖。独立只读复核未发现可确认的 P1/P2；32 项现有 Swift、5 项 Rust 测试和格式/静态检查通过，这些模型测试不验证真实图标显示。没有启动 HyCode、HyHub 或任何 UI 测试宿主，没有刷新系统缓存或公开发布。
