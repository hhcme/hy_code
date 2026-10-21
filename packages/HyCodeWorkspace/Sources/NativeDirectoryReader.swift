import CHyCodeCore
import Foundation

/// A worker and its cancellation handler both retain the token. The pointer is
/// immutable; its Rust atomic flag is thread-safe. Free happens after both release it.
private final class NativeCancellation: @unchecked Sendable {
    let pointer: OpaquePointer
    init() { pointer = hycode_cancel_new()! }
    func cancel() { hycode_cancel(pointer) }
    deinit { hycode_cancel_free(pointer) }
}

public struct NativeDirectoryReader: Sendable {
    public let rootPath: String
    public init(rootPath: String) { self.rootPath = rootPath }
    public static var abiVersion: UInt32 { hycode_core_abi_version() }

    /// At most two directories are enumerated/decoded at once, on interactive workers.
    /// Cancellation is atomic and does not wait for the worker's serial actor.
    public func list(relativePath: String, includeHidden: Bool) async throws -> DirectorySnapshot {
        guard Self.abiVersion == 1 else {
            throw WorkspaceFailure(code: "unsupported_abi", message: "目录内核接口版本不兼容")
        }
        let cancellation = NativeCancellation()
        return try await withTaskCancellationHandler {
            let result = try await Task.detached(priority: .userInitiated) {
                try await DirectoryWorkerPool.shared.read(
                    rootPath: rootPath, relativePath: relativePath,
                    includeHidden: includeHidden, cancellation: cancellation)
            }.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            cancellation.cancel()
        }
    }
}

/// Bounded parallelism prevents a slow read from blocking every unrelated folder.
/// A shared FIFO assigns the next request to whichever worker becomes free first.
private actor DirectoryWorkerPool {
    static let shared = DirectoryWorkerPool()
    private var idle = [DirectoryWorker(), DirectoryWorker()]
    private var waiters: [CheckedContinuation<DirectoryWorker, Never>] = []
    func read(rootPath: String, relativePath: String, includeHidden: Bool, cancellation: NativeCancellation)
        async throws -> DirectorySnapshot
    {
        let worker = await acquire()
        defer { release(worker) }
        return try await worker.read(
            rootPath: rootPath, relativePath: relativePath, includeHidden: includeHidden, cancellation: cancellation)
    }
    private func acquire() async -> DirectoryWorker {
        if let worker = idle.popLast() { return worker }
        return await withCheckedContinuation { waiters.append($0) }
    }
    private func release(_ worker: DirectoryWorker) {
        if waiters.isEmpty { idle.append(worker) } else { waiters.removeFirst().resume(returning: worker) }
    }
}

private actor DirectoryWorker {

    func read(
        rootPath: String, relativePath: String, includeHidden: Bool,
        cancellation: NativeCancellation
    ) throws -> DirectorySnapshot {
        let root = Array(rootPath.utf8)
        let relative = Array(relativePath.utf8)
        let buffer = root.withUnsafeBufferPointer { rootBytes in
            relative.withUnsafeBufferPointer { relativeBytes in
                hycode_core_list(
                    rootBytes.baseAddress, rootBytes.count,
                    relativeBytes.baseAddress, relativeBytes.count,
                    includeHidden, cancellation.pointer)
            }
        }
        defer { hycode_buffer_free(buffer) }
        guard let bytes = buffer.data, buffer.len > 0 else {
            throw WorkspaceFailure(code: "empty_response", message: "目录服务未返回结果")
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(bytes: bytes, count: buffer.len))
        if let error = envelope.error {
            if error.code == "cancelled" { throw CancellationError() }
            throw error
        }
        guard let snapshot = envelope.snapshot else {
            throw WorkspaceFailure(code: "invalid_response", message: "目录服务响应无效")
        }
        return snapshot
    }

    private struct Envelope: Decodable {
        let snapshot: DirectorySnapshot?
        let error: WorkspaceFailure?
    }
}
