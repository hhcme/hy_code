import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct WorkbenchToolTileTests {
    private let background = CGColor(srgbRed: 0.2, green: 0.25, blue: 0.3, alpha: 1)
    private let foreground = CGColor(srgbRed: 0.9, green: 0.95, blue: 1, alpha: 1)

    private func glyph(white: Bool = false) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(white ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let offset = y * image.bytesPerRow + x * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }

    @Test func previewContainsAnOpaqueBackgroundAndAnExplicitForeground() throws {
        for scale in [1.0, 2, 3] {
            let image = try #require(
                WorkbenchToolTile.render(
                    glyph: try glyph(), glyphSize: CGSize(width: 8, height: 8), background: background,
                    foreground: foreground, scale: scale))
            #expect(image.width == Int(30 * scale) && image.height == Int(30 * scale))
            let inside = try pixel(image, x: Int(5 * scale), y: Int(15 * scale))
            #expect(inside[3] == 255)
            #expect(abs(Int(inside[0]) - 51) <= 1)
            let symbol = try pixel(image, x: Int(15 * scale), y: Int(15 * scale))
            #expect(symbol[3] == 255 && symbol[0] >= 228 && symbol[2] == 255)
            #expect(try pixel(image, x: 0, y: 0)[3] == 0)
        }
    }

    @Test func sourceGlyphColorCannotTurnThePreviewBlack() throws {
        let black = try #require(
            WorkbenchToolTile.render(
                glyph: try glyph(), glyphSize: CGSize(width: 8, height: 8), background: background,
                foreground: foreground, scale: 2))
        let white = try #require(
            WorkbenchToolTile.render(
                glyph: try glyph(white: true), glyphSize: CGSize(width: 8, height: 8), background: background,
                foreground: foreground, scale: 2))
        #expect(black.dataProvider?.data == white.dataProvider?.data)
    }

    @Test func invalidRasterProposalsAreRejectedBeforeAllocation() throws {
        for scale in [0.0, -1, 5, .nan, .infinity] {
            #expect(
                WorkbenchToolTile.render(
                    glyph: try glyph(), glyphSize: CGSize(width: 8, height: 8), background: background,
                    foreground: foreground, scale: scale) == nil)
        }
    }
}
