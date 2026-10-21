import AppKit
import SwiftUI

enum WorkbenchAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "深色"
        case .light: "浅色"
        case .system: "跟随系统"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Shared semantic tokens for SwiftUI and AppKit. No global appearance mutation.
enum WorkbenchColors {
    static let canvas = Color(nsColor: nativeCanvas)
    static let panel = Color(nsColor: nativePanel)
    static let chrome = Color(nsColor: nativeChrome)
    static let border = Color(nsColor: nativeBorder)
    static let text = Color(nsColor: nativeText)
    static let secondary = Color(nsColor: nativeSecondary)
    static let muted = Color(nsColor: adaptive(light: 0x73767C, dark: 0x8B8E94))
    static let hover = Color(nsColor: adaptive(light: 0xE9EAEE, dark: 0x26282C))
    static let toolbarHover = Color(nsColor: nativeControlHover)
    static let controlHover = Color(nsColor: nativeControlHover)
    static let controlPressed = Color(nsColor: nativeControlPressed)
    static let selectedHover = Color(nsColor: nativeSelectedHover)
    static let selectedPressed = Color(nsColor: nativeSelectedPressed)
    static let tab = Color(nsColor: adaptive(light: 0xE9EAEE, dark: 0x26282C))
    static let tabBorder = Color(nsColor: adaptive(light: 0xD1D3D9, dark: 0x40434A))
    static let toolSelection = Color(nsColor: nativeToolSelection)
    static let selection = Color(nsColor: nativeSelection)
    static let accent = Color(nsColor: nativeAccent)

    static let nativeCanvas = adaptive(light: 0xFFFFFF, dark: 0x191A1C)
    static let nativePanel = adaptive(light: 0xFFFFFF, dark: 0x191A1C)
    static let nativeChrome = adaptive(light: 0xE9EAEE, dark: 0x26282C)
    static let nativeBorder = adaptive(light: 0xE9EAEE, dark: 0x26282C)
    static let nativeText = adaptive(light: 0x27282E, dark: 0xD1D3D9)
    static let nativeSecondary = adaptive(light: 0x5F6269, dark: 0x9FA2A8)
    static let nativeControlHover = adaptive(light: 0xDADDE4, dark: 0x363940)
    static let nativeControlPressed = adaptive(light: 0xC6CBD5, dark: 0x474B55)
    static let nativeSelectedHover = adaptive(light: 0xBBCFF9, dark: 0x355582)
    static let nativeSelectedPressed = adaptive(light: 0xA7BFEF, dark: 0x41699E)
    static let nativeSelection = adaptive(light: 0xD0DFFE, dark: 0x2A4371)
    static let nativeInactiveSelection = adaptive(light: 0xE9EAEE, dark: 0x33353B)
    static let nativeTreeHover = adaptive(light: 0xF2F3F6, dark: 0x24262B)
    static let nativeToolHover = adaptive(light: 0x4174D6, dark: 0x4B82EE)
    static let nativeToolPressed = adaptive(light: 0x234D9E, dark: 0x285BBF)
    static let nativeToolSelection = adaptive(light: 0x315FBD, dark: 0x3871E1)
    static let nativeAccent = adaptive(light: 0x315FBD, dark: 0x71A1FE)
    static let nativeFolder = adaptive(light: 0x73767C, dark: 0x9FA2A8)
    static let nativeCode = adaptive(light: 0x376B52, dark: 0x83B990)
    static let nativeConfig = adaptive(light: 0x8A6522, dark: 0xD3AD6A)
    static let nativeDocument = adaptive(light: 0x526A9D, dark: 0x8BA8DC)

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }
}

enum WorkbenchMetrics {
    static let headerHeight: CGFloat = 44
    static let stripeWidth: CGFloat = 40
    static let tabHeight: CGFloat = 40
    static let panelHeaderHeight: CGFloat = 36
    static let rowHeight: CGFloat = 24
    static let scrollerWidth: CGFloat = 8
    static let treeOuterInset: CGFloat = 4
    static let statusHeight: CGFloat = 26
    static let islandRadius: CGFloat = 10
}

struct WorkbenchSeparator: View {
    var vertical = false
    @Environment(\.displayScale) private var scale
    var body: some View {
        Rectangle().fill(WorkbenchColors.border)
            .frame(width: vertical ? 1 / scale : nil, height: vertical ? nil : 1 / scale)
            .accessibilityHidden(true)
    }
}

/// Shared fill/focus policy for SwiftUI buttons and native menu anchors.
struct WorkbenchControlSurface: ViewModifier {
    var active = false
    var hovering = false
    var pressed = false
    var focused = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.displayScale) private var scale

    private var fill: Color {
        guard enabled else { return active ? WorkbenchColors.selection : .clear }
        if pressed { return active ? WorkbenchColors.selectedPressed : WorkbenchColors.controlPressed }
        if hovering { return active ? WorkbenchColors.selectedHover : WorkbenchColors.controlHover }
        return active ? WorkbenchColors.selection : .clear
    }
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4).strokeBorder(
                    focused && enabled ? WorkbenchColors.accent : .clear, lineWidth: 1 / scale
                )
                .allowsHitTesting(false)
            }
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
    }
}

struct WorkbenchButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, active: active)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let active: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var focused
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(WorkbenchColors.text)
                .modifier(
                    WorkbenchControlSurface(
                        active: active, hovering: hovering, pressed: configuration.isPressed, focused: focused)
                )
                .background(WorkbenchPointerRegion(enabled: isEnabled))
                .onHover { hovering = isEnabled && $0 }
                .onChange(of: isEnabled) { _, enabled in if !enabled { hovering = false } }
                .onDisappear { hovering = false }
        }
    }
}

struct WorkbenchIconButton: View {
    let title: String
    let symbol: String
    var active = false
    var size: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13))
                .foregroundStyle(active ? WorkbenchColors.accent : WorkbenchColors.text)
                .frame(width: size, height: size)
        }
        .buttonStyle(WorkbenchButtonStyle(active: active))
        .help(title).accessibilityLabel(title)
    }
}
