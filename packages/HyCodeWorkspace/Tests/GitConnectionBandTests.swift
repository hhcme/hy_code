import CoreGraphics
import Foundation
import Testing

@testable import HyCodeWorkspace

struct GitConnectionBandTests {
    @Test func historicalScrollLaneMovesOutsideAndRetilingDoesNotAccumulateOffset() throws {
        let content = CGRect(x: 0, y: 0, width: 400, height: 200)
        let vertical = CGRect(x: 400, y: 0, width: 8, height: 200)
        let horizontal = CGRect(x: 0, y: 200, width: 400, height: 8)
        let first = try #require(GitScrollPlacement(content: content, vertical: vertical, horizontal: horizontal))
        #expect(first.content == CGRect(x: 8, y: 0, width: 400, height: 200))
        #expect(first.vertical == CGRect(x: 0, y: 0, width: 8, height: 200))
        #expect(first.horizontal == CGRect(x: 8, y: 200, width: 400, height: 8))
        #expect(
            GitScrollPlacement(content: first.content, vertical: first.vertical, horizontal: first.horizontal) == first)
        let bridge = try #require(
            GitConnectionBand.bridge(
                leftViewport: first.content,
                rightViewport: CGRect(x: 505, y: 0, width: 400, height: 200)))
        #expect(bridge.minX == 408 && bridge.width == 97)
        #expect(GitScrollPlacement(content: .zero, vertical: vertical, horizontal: nil) == nil)
    }
    @Test func bridgeStartsAtTextViewportAndExcludesHeadersAndHorizontalScrollLanes() throws {
        let left = CGRect(x: 0, y: 28, width: 400, height: 360)
        // 8pt vertical lane + two 48pt gutters + 1pt divider.
        let right = CGRect(x: 505, y: 30, width: 400, height: 356)
        let bridge = try #require(GitConnectionBand.bridge(leftViewport: left, rightViewport: right))
        #expect(bridge == CGRect(x: 400, y: 30, width: 105, height: 356))
        #expect(bridge.contains(CGPoint(x: 404, y: 100)))
        #expect(!bridge.contains(CGPoint(x: 404, y: 29)))
        #expect(!bridge.contains(CGPoint(x: 404, y: 387)))
        #expect(GitConnectionBand.bridge(leftViewport: left, rightViewport: .zero) == nil)
    }

    @Test func rasterHasContinuousEqualColourThroughTheReservedLaneAndNumberRails() throws {
        let bridge = try #require(
            GitConnectionBand.bridge(
                leftViewport: CGRect(x: 0, y: 0, width: 400, height: 200),
                rightViewport: CGRect(x: 505, y: 0, width: 400, height: 200)))
        let band = try #require(GitConnectionBand(bridge: bridge, divider: 456.5, left: 40...62, right: 40...62))
        let pixels = try raster(
            band: band, left: CGRect(x: 0, y: 40, width: 400, height: 22),
            right: CGRect(x: 505, y: 40, width: 400, height: 22))
        let reference = pixel(pixels, x: 200, y: 50)
        // Includes both boundaries, the old 8pt hole, both rails and divider.
        for x in 395...510 { #expect(pixel(pixels, x: x, y: 50) == reference) }
        #expect(pixel(pixels, x: 404, y: 30) != reference)
    }

    @Test func fiveLineDeletionKeepsItsRailThenTapersToTheOppositeAnchor() throws {
        let bridge = CGRect(x: 400, y: 0, width: 105, height: 200)
        let band = try #require(GitConnectionBand(bridge: bridge, divider: 456.5, left: 40...150, right: 40...40))
        #expect(band.bend == 444.5...468.5)
        #expect(band.path.contains(CGPoint(x: 430, y: 140)))
        #expect(!band.path.contains(CGPoint(x: 490, y: 140)))
        #expect(band.path.boundingBoxOfPath == CGRect(x: 400, y: 40, width: 105, height: 110))
        let pixels = try raster(band: band, left: CGRect(x: 0, y: 40, width: 400, height: 110), right: .zero)
        #expect(pixel(pixels, x: 404, y: 100) == pixel(pixels, x: 390, y: 100))
        #expect(pixel(pixels, x: 490, y: 100) == pixel(pixels, x: 490, y: 180))
        let inserted = try #require(GitConnectionBand(bridge: bridge, divider: 456.5, left: 40...40, right: 40...150))
        #expect(!inserted.path.contains(CGPoint(x: 430, y: 140)))
        #expect(inserted.path.contains(CGPoint(x: 490, y: 140)))
    }

    @Test func emptySceneRepaintsItsWholeSurfaceInsteadOfLeavingOldDeletedBlocks() throws {
        let band = try #require(
            GitConnectionBand(
                bridge: CGRect(x: 400, y: 0, width: 105, height: 200),
                divider: 456.5, left: 40...150, right: 40...40))
        let pixels = try raster(band: band, left: .zero, right: .zero, clearScene: true)
        for y in [20, 50, 100, 149, 180] {
            for x in [404, 430, 480, 501] {
                #expect(pixel(pixels, x: x, y: y) == pixel(pixels, x: 200, y: 100))
            }
        }
        #expect(pixel(pixels, x: 400, y: 100) == pixel(pixels, x: 200, y: 100))
        #expect(pixel(pixels, x: 456, y: 100) != pixel(pixels, x: 200, y: 100))
    }

    @Test func fractionalResizeAndClippedCrossingPreserveRealEndpoints() throws {
        let bridge = CGRect(x: 400.5, y: 28, width: 105.5, height: 100)
        let band = try #require(GitConnectionBand(bridge: bridge, divider: 457, left: -80...(-20), right: 180...220))
        #expect(band.isVisible)
        #expect(band.path.boundingBoxOfPath == CGRect(x: 400.5, y: -80, width: 105.5, height: 300))
        let hidden = try #require(GitConnectionBand(bridge: bridge, divider: 457, left: -80...(-20), right: -40...0))
        #expect(!hidden.isVisible)
        let narrow = try #require(
            GitConnectionBand(
                bridge: CGRect(x: 0, y: 0, width: 1, height: 20),
                divider: 0.5, left: 1...10, right: 2...15))
        #expect(narrow.bend == 0...1)
    }

    @Test func unequalReplacementUsesOneBlockColourWithoutChangingLineOrCharacterMetadata() throws {
        let rows = try GitDiffParser.rows("@@ -1,4 +1,2 @@\n-A\n-B\n-C\n+Z\n end\n")
        let comparison = try GitTextComparison.make(left: "A\nB\nC\nend\n", right: "Z\nend\n", rows: rows)
        #expect(comparison.blocks.first?.kind == .changed)
        #expect(comparison.left.lines.prefix(3).allSatisfy { $0.backgroundKind == .changed })
        #expect(comparison.left.lines[1].kind == .removed)
        #expect(comparison.right.lines[0].backgroundKind == .changed)
        #expect(comparison.left.lines[3].backgroundKind == .context)
        #expect(comparison.left.text == "A\nB\nC\nend\n" && comparison.right.text == "Z\nend\n")
        let reverseRows = try GitDiffParser.rows("@@ -1,2 +1,4 @@\n-Z\n+A\n+B\n+C\n end\n")
        let reverse = try GitTextComparison.make(left: "Z\nend\n", right: "A\nB\nC\nend\n", rows: reverseRows)
        #expect(reverse.right.lines.prefix(3).allSatisfy { $0.backgroundKind == .changed })
        #expect(reverse.right.lines[1].kind == .added)
    }

    private func raster(band: GitConnectionBand, left: CGRect, right: CGRect, clearScene: Bool = false) throws
        -> [UInt8]
    {
        var pixels = [UInt8](repeating: 0, count: 905 * 200 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress, width: 905, height: 200,
                    bitsPerComponent: 8, bytesPerRow: 905 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            // Match the runtime parent's flipped view space, and the bitmap's
            // top-to-bottom byte rows, without creating any AppKit view.
            context.translateBy(x: 0, y: 200)
            context.scaleBy(x: 1, y: -1)
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 905, height: 200))
            let colour = CGColor(red: 0.31, green: 0.55, blue: 0.72, alpha: 1)
            context.setFillColor(try #require(colour.copy(alpha: GitConnectionBand.opacity)))
            context.fill(left)
            context.fill(right)
            let scene = GitConnectionScene(divider: 456.5, paints: [GitConnectionPaint(band: band, kind: .changed)])
            let background = CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            let dividerColour = CGColor(gray: 0.5, alpha: 1)
            scene.draw(
                in: context, bounds: band.bridge, background: background,
                dividerColour: dividerColour, colour: { _ in colour })
            if clearScene {
                GitConnectionScene(divider: 456.5, paints: []).draw(
                    in: context, bounds: band.bridge,
                    background: background, dividerColour: dividerColour, colour: { _ in colour })
            }
        }
        return pixels
    }
    private func pixel(_ pixels: [UInt8], x: Int, y: Int) -> [UInt8] {
        Array(pixels[((y * 905 + x) * 4)..<((y * 905 + x) * 4 + 4)])
    }
}
