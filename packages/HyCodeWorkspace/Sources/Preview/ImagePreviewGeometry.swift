import CoreGraphics

public struct ImagePreviewLayout: Equatable, Sendable {
    public let extent: CGSize
    public let image: CGRect
    public init(pixels: CGSize, viewport: CGSize, scale: CGFloat) {
        let size = CGSize(width: max(1, pixels.width) * scale, height: max(1, pixels.height) * scale)
        extent = CGSize(width: max(viewport.width, size.width + 32), height: max(viewport.height, size.height + 32))
        image = CGRect(
            x: (extent.width - size.width) / 2, y: (extent.height - size.height) / 2,
            width: size.width, height: size.height)
    }
    public func clamp(origin: CGPoint, viewport: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, origin.x), max(0, extent.width - viewport.width)),
            y: min(max(0, origin.y), max(0, extent.height - viewport.height)))
    }
    public func preservingAnchor(
        from old: Self, origin: CGPoint, anchor: CGPoint, viewport: CGSize, newAnchor: CGPoint? = nil
    ) -> CGPoint {
        let x = min(1, max(0, (origin.x + anchor.x - old.image.minX) / old.image.width))
        let y = min(1, max(0, (origin.y + anchor.y - old.image.minY) / old.image.height))
        let destination = newAnchor ?? anchor
        return clamp(
            origin: CGPoint(
                x: image.minX + x * image.width - destination.x,
                y: image.minY + y * image.height - destination.y), viewport: viewport)
    }
}
public struct ImagePreviewZoom: Sendable {
    public private(set) var fits = true
    private var requested: CGFloat = 1
    public init() {}
    public static let presets: [CGFloat] = [0.05, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 8, 16]
    public static func clamp(_ scale: CGFloat) -> CGFloat {
        scale.isFinite ? min(16, max(1 / 4096, scale)) : 1
    }
    public func factor(pixels: CGSize, viewport: CGSize) -> CGFloat {
        guard fits else { return requested }
        return Self.clamp(
            min(
                1,
                min(
                    max(1, viewport.width - 32) / max(1, pixels.width),
                    max(1, viewport.height - 32) / max(1, pixels.height))))
    }
    public mutating func fit() { fits = true }
    public mutating func set(_ scale: CGFloat) {
        fits = false
        requested = Self.clamp(scale)
    }
}
