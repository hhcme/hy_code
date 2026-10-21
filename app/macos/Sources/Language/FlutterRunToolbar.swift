import HyCodeWorkspace
import SwiftUI

/// Narrow windows move secondary actions into the configuration menu.
struct FlutterRunToolbar: View {
    @Bindable var controller: FlutterWorkspaceController
    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
            controls(compact: true)
            controls(compact: true, iconOnly: true)
        }
    }
    private func controls(compact: Bool, iconOnly: Bool = false) -> some View {
        HStack(spacing: 3) {
            WorkbenchMenuButton(title: "选择运行设备", items: deviceItems) {
                HStack(spacing: 5) {
                    Image(systemName: deviceSymbol).foregroundStyle(WorkbenchColors.accent)
                    if !iconOnly { Text(deviceName).lineLimit(1).frame(maxWidth: compact ? 80 : 140) }
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.padding(.horizontal, 6).frame(height: 28)
            }.disabled(!controller.canRunTool).help(deviceName)
            WorkbenchMenuButton(title: "运行配置与 Flutter 工具", items: configurationItems) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(WorkbenchColors.accent)
                    if !iconOnly {
                        Text(URL(fileURLWithPath: controller.launch.program).lastPathComponent)
                            .lineLimit(1).frame(maxWidth: compact ? 80 : 120)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.padding(.horizontal, 6).frame(height: 28)
            }
            FlutterActionButton(title: "运行 Flutter ⌃R", symbol: "play.fill", color: .green) {
                controller.start(debug: false)
            }.disabled(!controller.canStart)
            FlutterActionButton(title: "调试 Flutter ⌃D", symbol: "ladybug", color: .green) {
                controller.start(debug: true)
            }.disabled(!controller.canStart || controller.launch.mode != .debug)
            if !compact {
                FlutterActionButton(title: "热重载 ⌘\\", symbol: "bolt.fill", color: .yellow) {
                    controller.control("hotReload")
                }.disabled(!controller.canReload)
                FlutterActionButton(title: "热重启 ⇧⌘\\", symbol: "arrow.clockwise", color: .green) {
                    controller.control("hotRestart")
                }.disabled(!controller.canReload)
            }
            FlutterActionButton(title: "停止会话或任务 ⌃.", symbol: "stop.fill", color: .red) { controller.stop() }
                .disabled(!controller.active && !controller.commandRunning)
        }.font(.system(size: 12)).fixedSize(horizontal: true, vertical: false)
    }
    private var deviceName: String {
        controller.devices.first { $0.id == controller.launch.deviceID }?.name
            ?? (controller.launch.deviceID.isEmpty ? "选择设备" : controller.launch.deviceID)
    }
    private var deviceSymbol: String {
        let platform = controller.devices.first { $0.id == controller.launch.deviceID }?.platform ?? ""
        if platform.hasPrefix("ios") || platform.hasPrefix("android") { return "iphone" }
        if platform.hasPrefix("web") { return "globe" }
        return "desktopcomputer"
    }
    private var deviceItems: [WorkbenchMenuItem] {
        var items = controller.devices.map { device in
            WorkbenchMenuItem(
                title: device.name + " · " + device.platform,
                checked: controller.launch.deviceID == device.id
            ) { controller.launch.deviceID = device.id }
        }
        if items.isEmpty { items.append(WorkbenchMenuItem(title: "尚未发现设备", enabled: false)) }
        items += [
            .separator,
            WorkbenchMenuItem(title: "刷新设备", enabled: controller.canRunTool) {
                controller.runCommand("devices")
            },
        ]
        return items
    }
    private var configurationItems: [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(
                title: controller.launch.program + " · " + controller.launch.mode.rawValue,
                enabled: false, checked: true),
            WorkbenchMenuItem(title: "编辑配置…", enabled: controller.canEditConfiguration) {
                controller.dialog = .configuration
            }, .separator,
            WorkbenchMenuItem(title: "热重载 ⌘\\", enabled: controller.canReload) { controller.control("hotReload") },
            WorkbenchMenuItem(title: "热重启 ⇧⌘\\", enabled: controller.canReload) { controller.control("hotRestart") },
            WorkbenchMenuItem(title: "查看断点…") { controller.dialog = .breakpoints }, .separator,
            WorkbenchMenuItem(
                title: "构建",
                children: ["macos", "ios", "apk", "appbundle", "web"].map { target in
                    WorkbenchMenuItem(title: target, enabled: controller.canStart) {
                        controller.buildTarget = target
                        controller.runCommand("build")
                    }
                }),
            WorkbenchMenuItem(title: "运行测试", enabled: controller.canStart) { controller.runCommand("test") },
            WorkbenchMenuItem(title: "Flutter Doctor", enabled: controller.canRunTool) {
                controller.runCommand("doctor")
            },
        ]
    }
}

struct FlutterActionButton: View {
    let title: String
    let symbol: String
    var color = WorkbenchColors.text
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(color).frame(width: 26, height: 26)
        }.buttonStyle(WorkbenchButtonStyle()).help(title).accessibilityLabel(title)
    }
}
