import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct EditorFeedbackTests {
    @Test func caretHasStrongContrastInBothEditorThemes() {
        func luminance(_ hex: UInt32) -> Double {
            func linear(_ value: UInt32) -> Double {
                let channel = Double(value & 255) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
        }
        for palette in [EditorFeedbackPalette.dark, .light] {
            let caret = luminance(palette.caret)
            for background in [palette.background, palette.currentLine] {
                let backdrop = luminance(background)
                #expect((max(caret, backdrop) + 0.05) / (min(caret, backdrop) + 0.05) >= 7)
            }
        }
    }
    @Test func thinCaretBecomesPixelAlignedAndKeepsNativeLineHeight() {
        let rect = CGRect(x: 14.3, y: 12.2, width: 0.5, height: 15.3)
        for scale in [CGFloat(1), 2, 3] {
            let result = EditorFeedbackGeometry.caret(rect, scale: scale)
            #expect(result.width >= 2)
            #expect(result.minX * scale == (result.minX * scale).rounded())
            #expect(abs(result.minX - rect.minX) <= 0.5 / scale)
            #expect(result.height >= rect.height && result.height - rect.height < 1 / scale)
        }
        #expect(EditorFeedbackGeometry.caret(.zero, scale: 2).isEmpty)
        #expect(EditorFeedbackGeometry.caret(rect, scale: 0).isEmpty)
    }
    @Test func nativeBlinkDamageCoversTheEntireWidenedCaret() {
        for scale in [CGFloat(1), 2, 3] {
            for x in [CGFloat(0), 14.2, 27.7] {
                let native = CGRect(x: x, y: 12.2, width: 0.5, height: 15.3)
                let painted = EditorFeedbackGeometry.caret(native, scale: scale)
                let damage = EditorFeedbackGeometry.damage(native, scale: scale)
                #expect(damage.contains(painted))
                #expect(damage.contains(native))
            }
        }
    }
}

struct ContextMenuInteractionTests {
    @Test func menuWidthFollowsMeasuredContentAndStaysInsideSmallScreens() {
        let compact = ContextMenuMetrics.width(contentWidth: 100, screenWidth: 1_440)
        let longer = ContextMenuMetrics.width(contentWidth: 180, screenWidth: 1_440)
        #expect(compact == 220 && longer > compact && longer < 320)
        #expect(ContextMenuMetrics.width(contentWidth: 1_000, screenWidth: 1_440) == 360)
        #expect(ContextMenuMetrics.width(contentWidth: 180, screenWidth: 190) == 178)
    }
    @Test func keyboardSelectionSkipsDisabledRowsAndSeparatorsAndWraps() {
        var state = ContextMenuSelection(enabled: [false, true, false, true, false])
        #expect(state.index == 1)
        state.move(forward: true)
        #expect(state.index == 3)
        state.move(forward: true)
        #expect(state.index == 1)
        state.move(forward: false)
        #expect(state.index == 3)
        state.select(0)
        #expect(state.index == 3)
        state.edge(last: false)
        #expect(state.index == 1)
        state.edge(last: true)
        #expect(state.index == 3)
    }
    @Test func emptyAndDisabledMenusHaveNoExecutableSelection() {
        for rows in [[], [false, false]] {
            var state = ContextMenuSelection(enabled: rows)
            state.move(forward: true)
            state.move(forward: false)
            state.select(-1)
            state.edge(last: true)
            #expect(state.index == nil)
        }
    }
    @Test func menuPlacementKeepsAllEdgesInsideThePointerScreen() {
        for screen in [
            CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: -1600, y: 250, width: 1600, height: 900),
        ] {
            for point in [
                CGPoint(x: screen.minX + 1, y: screen.minY + 1),
                CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
                CGPoint(x: screen.midX, y: screen.midY),
            ] {
                for size in [CGSize(width: 320, height: 540), CGSize(width: 2000, height: 2000)] {
                    let rect = ContextMenuPlacement.frame(anchor: point, size: size, screen: screen)
                    #expect(screen.contains(rect))
                }
            }
        }
    }
}
