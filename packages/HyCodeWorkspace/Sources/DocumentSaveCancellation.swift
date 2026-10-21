import Foundation

/// May be cancelled from the UI while a document actor is in blocking disk I/O.
/// Cancellation is cooperative until the atomic rename commit point.
public final class DocumentSaveCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}
