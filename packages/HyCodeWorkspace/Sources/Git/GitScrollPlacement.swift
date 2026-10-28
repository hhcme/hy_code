import Foundation

/// Move the historical pane's existing native scrollbars to the outer edge.
/// Deriving the occupied area from the union makes repeated tiling idempotent;
/// changing frames never changes the clip's document-space scroll origin.
public struct GitScrollPlacement: Sendable, Equatable {
    public let content: CGRect
    public let vertical: CGRect
    public let horizontal: CGRect?
    public init?(content: CGRect, vertical: CGRect, horizontal: CGRect?) {
        guard !content.isEmpty, !vertical.isEmpty,
            [
                content.minX, content.minY, content.width, content.height,
                vertical.minX, vertical.minY, vertical.width, vertical.height,
            ].allSatisfy(\.isFinite),
            vertical.width <= content.width
        else { return nil }
        let occupied = content.union(vertical)
        self.vertical = CGRect(x: occupied.minX, y: vertical.minY, width: vertical.width, height: vertical.height)
        self.content = CGRect(
            x: occupied.minX + vertical.width, y: content.minY,
            width: content.width, height: content.height)
        self.horizontal = horizontal.map {
            CGRect(x: occupied.minX + vertical.width, y: $0.minY, width: content.width, height: $0.height)
        }
    }
}
