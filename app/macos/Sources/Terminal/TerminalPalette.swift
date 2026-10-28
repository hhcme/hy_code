import AppKit
import SwiftTerm

@MainActor enum TerminalPalette {
    static func foreground(dark: Bool) -> NSColor {
        let value: UInt32 = dark ? 0xCDD2DC : 0x303642
        return NSColor(
            srgbRed: CGFloat(value >> 16 & 255) / 255,
            green: CGFloat(value >> 8 & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    static func ansi(dark: Bool) -> [SwiftTerm.Color] {
        let colors: [UInt32] =
            dark
            ? [
                0x252931, 0xE88189, 0x94BF8B, 0xD7B676, 0x86A8E7, 0xB99BD8, 0x7DBEC8, 0xCCD1DA,
                0x747D8C, 0xF09AA1, 0xB0D4A4, 0xE9CF99, 0xA7C3F5, 0xD1B8EA, 0x9BD6DC, 0xE9ECF2,
            ]
            : [
                0x303642, 0xB13D4D, 0x3D7044, 0x8A651F, 0x365FAB, 0x8154A3, 0x216F7C, 0xD6D9DF,
                0x68717F, 0xBB4250, 0x437C4C, 0x90691E, 0x3C68B6, 0x885AAC, 0x287786, 0xF1F2F5,
            ]
        return colors.map {
            SwiftTerm.Color(
                red: UInt16($0 >> 16 & 255) * 257,
                green: UInt16($0 >> 8 & 255) * 257, blue: UInt16($0 & 255) * 257)
        }
    }
}
