import Foundation

/// Fair, cancellable admission for a complete multi-command operation. Reads
/// never overlap a writer; at most two independent repositories are read at once.
actor GitScheduler {
    static let shared = GitScheduler()
    private struct Waiter {
        let id: UUID
        let scope: String
        let write: Bool
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var waiting: [Waiter] = []
    private var active: [UUID: (scope: String, write: Bool)] = [:]
    func acquire(scope: String, write: Bool) async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiter(id: id, scope: scope, write: write, continuation: continuation))
                drain()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    func release(_ id: UUID) {
        active[id] = nil
        drain()
    }
    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: index).continuation.resume(throwing: CancellationError())
            drain()
        }
    }
    private func drain() {
        while let first = waiting.first {
            let busy = active.values.contains { $0.write || $0.scope == first.scope }
            guard !busy, first.write ? active.isEmpty : active.count < 2 else { return }
            waiting.removeFirst()
            active[first.id] = (first.scope, first.write)
            first.continuation.resume(returning: first.id)
            if first.write { return }
        }
    }
}
