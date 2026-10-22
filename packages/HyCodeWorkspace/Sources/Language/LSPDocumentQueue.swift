import Foundation

/// Orders background disk registrations and native buffer overlays on one wire.
/// Never holds an editor lock or MainActor while waiting for a service.
actor LSPDocumentQueue {
    private var tail: Task<Void, Error>?
    func run(_ action: @escaping @Sendable () async throws -> Void) async throws {
        let previous = tail
        let task = Task {
            _ = try? await previous?.value
            try Task.checkCancellation()
            try await action()
        }
        tail = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
