import CHyCodeCore
import Foundation

/// May be cancelled from the UI while a document actor is in blocking disk I/O.
/// Cancellation is cooperative until the atomic rename commit point.
public final class DocumentSaveCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    let native = hycode_cancel_new()
    public init() {}
    deinit { hycode_cancel_free(native) }
    public func cancel() {
        lock.withLock {
            cancelled = true
            hycode_cancel(native)
        }
    }
    public func checkCancellation() throws { try check() }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}
