import CoreGraphics
import Foundation

public struct GitConnectionPaint: Sendable, Equatable {
    public let band: GitConnectionBand
    public let kind: GitDiffRow.Kind
    public init(band: GitConnectionBand, kind: GitDiffRow.Kind) {
        self.band = band
        self.kind = kind
    }
}

/// A prepared scene, independent of view layout. The dedicated native canvas
/// and headless raster tests call exactly the same full-surface drawing path.
public struct GitConnectionScene: Sendable, Equatable {
    public let divider: CGFloat
    public let paints: [GitConnectionPaint]
    public static let empty = Self(divider: 0, paints: [])
    public init(divider: CGFloat, paints: [GitConnectionPaint]) {
        self.divider = divider
        self.paints = paints
    }
    public func draw(
        in context: CGContext, bounds: CGRect, background: CGColor, dividerColour: CGColor,
        colour: (GitDiffRow.Kind) -> CGColor?
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bounds)
        // The native canvas is opaque, including when there are no bands.
        // Repainting its whole base clears old paths after scroll/reload.
        context.setFillColor(background)
        context.fill(bounds)
        context.setFillColor(dividerColour)
        context.fill(CGRect(x: divider - 0.5, y: bounds.minY, width: 1, height: bounds.height))
        for paint in paints {
            guard let value = colour(paint.kind) else { continue }
            paint.band.draw(in: context, background: background, colour: value)
        }
    }
}
