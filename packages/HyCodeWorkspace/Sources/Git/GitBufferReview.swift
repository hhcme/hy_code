import Foundation

/// A clean editor is not proof that it still matches disk. This binding permits
/// a saved candidate only after the visible formal buffer matches the saved
/// source reviewed in that request. Old documents/revisions cannot re-enable it.
public struct GitBufferReview: Sendable {
    public struct Request: Sendable, Equatable {
        let id: UUID
        let document: UUID
        let revision: UInt64
    }
    private var current: Request?
    private var matched = false
    public init() {}
    public mutating func begin(document: UUID, revision: UInt64) -> Request {
        let request = Request(id: UUID(), document: document, revision: revision)
        current = request
        matched = false
        return request
    }
    public mutating func invalidate() {
        current = nil
        matched = false
    }
    public func accepts(_ request: Request) -> Bool { current == request }
    public mutating func accept(_ request: Request, buffer: String, saved: String, dirty: Bool) {
        guard accepts(request) else { return }
        matched = !dirty && buffer.utf8.elementsEqual(saved.utf8)
    }
    public func canSelect(document: UUID, revision: UInt64, dirty: Bool) -> Bool {
        !dirty && matched && current?.document == document && current?.revision == revision
    }
}
