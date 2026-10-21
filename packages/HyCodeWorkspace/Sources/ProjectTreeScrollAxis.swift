import Foundation

/// Native scroller values and document offsets share this finite, clamped range.
/// No view, file access or platform scroll implementation is owned here.
public struct ProjectTreeScrollAxis: Sendable {
    public let viewport: Double
    public let extent: Double
    public init(viewport: Double, extent: Double) {
        self.viewport = viewport.isFinite ? max(0, viewport) : 0
        self.extent = extent.isFinite ? max(0, extent) : 0
    }
    public var maximumOffset: Double { max(0, extent - viewport) }
    public var knobProportion: Double { extent > 0 ? min(1, viewport / extent) : 1 }
    public func normalized(_ offset: Double) -> Double {
        maximumOffset > 0 ? clamp(offset) / maximumOffset : 0
    }
    public func offset(for value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value)) * maximumOffset
    }
    public func clamp(_ offset: Double) -> Double {
        offset.isFinite ? min(maximumOffset, max(0, offset)) : 0
    }
}
