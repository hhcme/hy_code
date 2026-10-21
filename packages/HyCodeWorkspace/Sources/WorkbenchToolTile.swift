import CoreGraphics

/// Small, eagerly rasterized tool tile. No NSImage template interpretation, view
/// capture or window server is involved; the supplied glyph contributes alpha only.
public enum WorkbenchToolTile {
    public static func render(
        glyph: CGImage, glyphSize: CGSize, background: CGColor, foreground: CGColor,
        scale: Double
    ) -> CGImage? {
        guard scale.isFinite, (1...4).contains(scale), glyphSize.width.isFinite,
            glyphSize.height.isFinite, glyphSize.width > 0, glyphSize.height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let pixels = Int((30 * scale).rounded())
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.addPath(
            CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: 30, height: 30), cornerWidth: 6, cornerHeight: 6, transform: nil)
        )
        context.setFillColor(background)
        context.fillPath()
        let fit = min(1, 22 / glyphSize.width, 22 / glyphSize.height)
        let width = glyphSize.width * fit
        let height = glyphSize.height * fit
        let frame = CGRect(
            x: ((30 - width) / 2 * scale).rounded() / scale,
            y: ((30 - height) / 2 * scale).rounded() / scale,
            width: width, height: height)
        context.saveGState()
        context.clip(to: frame, mask: glyph)
        context.setFillColor(foreground)
        context.fill(frame)
        context.restoreGState()
        return context.makeImage()
    }
}
