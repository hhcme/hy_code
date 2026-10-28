import Foundation

/// Half-open ranges in each real source, not in a padded row projection. A
/// deleted side may have five lines while its opposite range is an empty anchor.
public struct GitDiffBlock: Sendable, Equatable, Identifiable {
    public let id: Int
    public let left: Range<Int>
    public let right: Range<Int>
    public var kind: GitDiffRow.Kind { left.isEmpty ? .added : right.isEmpty ? .removed : .changed }

    static func make(_ rows: [GitDiffRow]) -> [Self] {
        var result: [Self] = []
        var left = 0
        var right = 0
        var start: (id: Int, left: Int, right: Int)?
        func flush() {
            if let start {
                result.append(Self(id: start.id, left: start.left..<left, right: start.right..<right))
            }
            start = nil
        }
        for row in rows {
            if row.kind == .note { continue }
            if !row.kind.isChange {
                flush()
                if let number = row.leftNumber { left = number }
                if let number = row.rightNumber { right = number }
                continue
            }
            if start == nil {
                if let number = row.leftNumber { left = number - 1 }
                if let number = row.rightNumber { right = number - 1 }
                start = (row.id, left, right)
            }
            if let number = row.leftNumber { left = number }
            if let number = row.rightNumber { right = number }
        }
        flush()
        return result
    }

    /// Scroll correspondence follows unchanged source and interpolates within
    /// replacements. Pure insertion/deletion collapses to the opposite anchor;
    /// neither source needs fake blank paragraphs.
    public static func map(_ position: Double, fromLeft: Bool, blocks: [Self]) -> Double {
        guard position.isFinite else { return 0 }
        if position < 0 { return position }
        var delta = 0
        for block in blocks {
            let source = fromLeft ? block.left : block.right
            let target = fromLeft ? block.right : block.left
            if position < Double(source.lowerBound) { return position + Double(delta) }
            if !source.isEmpty && position < Double(source.upperBound) {
                let fraction = (position - Double(source.lowerBound)) / Double(source.count)
                return Double(target.lowerBound) + fraction * Double(target.count)
            }
            delta = target.upperBound - source.upperBound
        }
        return position + Double(delta)
    }
}
