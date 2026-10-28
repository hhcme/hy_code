import CoreGraphics
import Foundation

/// Geometry in the common flipped parent space. The viewport edges, not gutter
/// frames, include a reserved scrollbar lane in the bridge. Outer shoulders keep
/// the source colour through each number rail; only the centre lane bends.
public struct GitConnectionBand: Sendable, Equatable {
    public static let opacity: CGFloat = 0.18
    public let bridge: CGRect
    public let left: ClosedRange<CGFloat>
    public let right: ClosedRange<CGFloat>
    public let bend: ClosedRange<CGFloat>

    public static func bridge(leftViewport: CGRect, rightViewport: CGRect) -> CGRect? {
        let values = [
            leftViewport.minX, leftViewport.maxX, leftViewport.minY, leftViewport.maxY,
            rightViewport.minX, rightViewport.maxX, rightViewport.minY, rightViewport.maxY,
        ]
        guard values.allSatisfy(\.isFinite), !leftViewport.isEmpty, !rightViewport.isEmpty,
            rightViewport.minX > leftViewport.maxX
        else { return nil }
        let top = max(leftViewport.minY, rightViewport.minY)
        let bottom = min(leftViewport.maxY, rightViewport.maxY)
        guard bottom > top else { return nil }
        return CGRect(
            x: leftViewport.maxX, y: top, width: rightViewport.minX - leftViewport.maxX,
            height: bottom - top)
    }

    public init?(bridge: CGRect, divider: CGFloat, left: ClosedRange<CGFloat>, right: ClosedRange<CGFloat>) {
        guard
            [
                bridge.minX, bridge.maxX, bridge.minY, bridge.maxY, divider,
                left.lowerBound, left.upperBound, right.lowerBound, right.upperBound,
            ].allSatisfy(\.isFinite),
            !bridge.isEmpty
        else { return nil }
        self.bridge = bridge
        self.left = left
        self.right = right
        let centre = min(bridge.maxX, max(bridge.minX, divider))
        bend = max(bridge.minX, centre - 12)...min(bridge.maxX, centre + 12)
    }

    public var isVisible: Bool {
        max(left.upperBound, right.upperBound) >= bridge.minY
            && min(left.lowerBound, right.lowerBound) <= bridge.maxY
    }

    public var path: CGPath {
        let path = CGMutablePath()
        edge(path, from: left.lowerBound, to: right.lowerBound, reverse: false)
        path.addLine(to: CGPoint(x: bridge.maxX, y: right.upperBound))
        edge(path, from: right.upperBound, to: left.upperBound, reverse: true, move: false)
        path.closeSubpath()
        return path
    }
    public var edges: CGPath {
        let path = CGMutablePath()
        edge(path, from: left.lowerBound, to: right.lowerBound, reverse: false)
        edge(path, from: left.upperBound, to: right.upperBound, reverse: false)
        return path
    }
    /// Repaint the known panel base beneath the band, including the 1pt
    /// divider, before applying its tint. Background/scrollbar/rail opacity
    /// cannot accumulate or introduce a vertical colour break inside a hunk.
    public func draw(in context: CGContext, background: CGColor, colour: CGColor) {
        guard let fill = colour.copy(alpha: Self.opacity), let stroke = colour.copy(alpha: 0.32) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: bridge)
        let body = path
        context.addPath(body)
        context.setFillColor(background)
        context.fillPath()
        context.addPath(body)
        context.setFillColor(fill)
        context.fillPath()
        context.addPath(edges)
        context.setStrokeColor(stroke)
        context.setLineWidth(0.5)
        context.strokePath()
    }
    private func edge(_ path: CGMutablePath, from a: CGFloat, to b: CGFloat, reverse: Bool, move: Bool = true) {
        let x0 = reverse ? bridge.maxX : bridge.minX
        let x1 = reverse ? bend.upperBound : bend.lowerBound
        let x2 = reverse ? bend.lowerBound : bend.upperBound
        let x3 = reverse ? bridge.minX : bridge.maxX
        let start = CGPoint(x: x0, y: a)
        if move { path.move(to: start) } else { path.addLine(to: start) }
        path.addLine(to: CGPoint(x: x1, y: a))
        let middle = (bend.lowerBound + bend.upperBound) / 2
        path.addCurve(
            to: CGPoint(x: x2, y: b), control1: CGPoint(x: middle, y: a),
            control2: CGPoint(x: middle, y: b))
        path.addLine(to: CGPoint(x: x3, y: b))
    }
}
