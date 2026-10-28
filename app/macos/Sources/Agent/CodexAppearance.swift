import AppKit
import SwiftUI

/// Chat surfaces have their own neutral palette. Workbench chrome, editor
/// selection and system appearance continue to use the workbench theme.
enum CodexAppearance {
    static let background = color(light: 0xFFFFFF, dark: 0x181818)
    static let composer = color(light: 0xF0F0F0, dark: 0x303030)
    static let raised = color(light: 0xF5F5F5, dark: 0x262626)
    static let border = color(light: 0xDEDEDE, dark: 0x3B3B3B)
    static let text = color(light: 0x252525, dark: 0xE6E6E6)
    static let secondary = color(light: 0x686868, dark: 0x929292)
    static let muted = color(light: 0x858585, dark: 0x737373)
    static let blue = Color(red: 0.20, green: 0.43, blue: 0.81)
    static let green = color(light: 0x16834B, dark: 0x39B974)
    static let red = color(light: 0xBE3838, dark: 0xEE5252)
    static let permission = color(light: 0xAD531D, dark: 0xE68643)
    static let nativeText = native(light: 0x252525, dark: 0xE6E6E6)
    static let columnWidth: CGFloat = 760
    private static func color(light: UInt32, dark: UInt32) -> Color { Color(nsColor: native(light: light, dark: dark)) }
    private static func native(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}

struct CodexQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }
    private struct Surface: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(
                    (enabled && (hovering || configuration.isPressed)
                        ? CodexAppearance.border.opacity(configuration.isPressed ? 0.8 : 0.5) : .clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle()).onHover { hovering = $0 }
                .opacity(enabled ? 1 : 0.4)
        }
    }
}
