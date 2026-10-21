import CoreGraphics
import Testing

@testable import HyCodeWorkspace

struct EditorGutterDrawingTests {
    private func canvas() throws -> CGContext {
        let context = try #require(
            CGContext(
                data: nil, width: 180, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 100))
        return context
    }
    private func pixel(_ context: CGContext, x: Int, y: Int) throws -> [UInt8] {
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        // Bitmap rows are top-down; drawing coordinates have their origin below.
        let row = context.height - 1 - y
        return Array(UnsafeBufferPointer(start: bytes + row * context.bytesPerRow + x * 4, count: 4))
    }

    @Test func oversizedDirtyRectCannotCoverEditorOrAdjacentHeaders() throws {
        let context = try canvas()
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 60, y: 20, width: 100, height: 50))
        let gutter = CGRect(x: 10, y: 10, width: 30, height: 80)
        let oversized = CGRect(x: -200, y: -200, width: 1000, height: 1000)
        EditorGutterDrawing.draw(in: context, bounds: gutter, dirtyRect: oversized) { clipped in
            #expect(clipped == gutter)
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            // Even an accidentally oversized label/background stays in the gutter.
            context.fill(oversized)
        }
        #expect(try pixel(context, x: 20, y: 30) == [0, 0, 0, 255])
        #expect(try pixel(context, x: 100, y: 30) == [255, 0, 0, 255])
        #expect(try pixel(context, x: 0, y: 30) == [255, 255, 255, 255])
        #expect(try pixel(context, x: 20, y: 0) == [255, 255, 255, 255])
        #expect(try pixel(context, x: 20, y: 95) == [255, 255, 255, 255])
        // The gutter must not leave its clip active for later native text drawing.
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 100, y: 30, width: 1, height: 1))
        #expect(try pixel(context, x: 100, y: 30) == [0, 255, 0, 255])
    }

    @Test func partialRepaintTouchesOnlyTheGutterIntersection() throws {
        let context = try canvas()
        EditorGutterDrawing.draw(
            in: context, bounds: CGRect(x: 10, y: 10, width: 30, height: 80),
            dirtyRect: CGRect(x: 0, y: 40, width: 100, height: 10)
        ) { clipped in
            #expect(clipped == CGRect(x: 10, y: 40, width: 30, height: 10))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(clipped)
        }
        #expect(try pixel(context, x: 20, y: 45) == [0, 0, 0, 255])
        #expect(try pixel(context, x: 20, y: 30) == [255, 255, 255, 255])
        #expect(try pixel(context, x: 50, y: 45) == [255, 255, 255, 255])
    }

    @Test func invalidEmptyOrUnrelatedDamageDoesNotDraw() throws {
        let context = try canvas()
        let gutter = CGRect(x: 10, y: 10, width: 30, height: 80)
        var calls = 0
        for dirty in [
            CGRect.zero, CGRect(x: 60, y: 0, width: 30, height: 80), CGRect.null,
            CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
        ] {
            EditorGutterDrawing.draw(in: context, bounds: gutter, dirtyRect: dirty) { _ in calls += 1 }
        }
        #expect(calls == 0)
        #expect(try pixel(context, x: 20, y: 30) == [255, 255, 255, 255])
        EditorGutterDrawing.draw(in: context, bounds: gutter, dirtyRect: .infinite) { clipped in
            #expect(clipped == gutter)
            calls += 1
        }
        #expect(calls == 1)
    }
}
