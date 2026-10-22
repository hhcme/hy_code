import Darwin
import Foundation

public struct DeveloperToolResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let truncated: Bool
}
/// Explicit user-invoked SDK commands only. No shell interpolation, detached
/// terminals or global process killing. One process per owner, bounded capture.
public actor DeveloperToolTask {
    private var process: OwnedToolProcess?
    private var waiting: Task<Int32, Never>?
    private var stdout = Data()
    private var stderr = Data()
    private var truncated = false
    private var cancelled = false
    public init() {}
    public func run(
        executable: URL, arguments: [String], directory: URL, environment: [String: String] = [:],
        standardOutput: (@Sendable (String) async -> Void)? = nil,
        output: @escaping @Sendable (String) async -> Void
    ) async throws -> DeveloperToolResult {
        guard !cancelled else { throw CancellationError() }
        try Task.checkCancellation()
        guard process == nil else { throw LanguageServiceFailure("已有工具任务正在运行") }
        stdout = Data()
        stderr = Data()
        truncated = false
        let child = try OwnedToolProcess.launch(
            executable: executable, arguments: arguments, directory: directory,
            environment: environment)
        process = child
        let readers = [(child.stdout, false), (child.stderr, true)].map { handle, isError in
            Task.detached(priority: .utility) { [weak self] in
                defer { try? handle.close() }
                var decoder = UTF8OutputDecoder()
                while true {
                    let data = await ToolBlockingIO.read(handle, capacity: 8192)
                    guard !data.isEmpty else { break }
                    await self?.capture(data, error: isError)
                    let text = decoder.append(data)
                    if !isError, !text.isEmpty { await standardOutput?(text) }
                    if !text.isEmpty { await output(text) }
                }
                let suffix = decoder.finish()
                if !isError, !suffix.isEmpty { await standardOutput?(suffix) }
                if !suffix.isEmpty { await output(suffix) }
            }
        }
        let waiting = Task.detached(priority: .utility) { await ToolBlockingIO.wait(child) }
        self.waiting = waiting
        let status = await withTaskCancellationHandler {
            await waiting.value
        } onCancel: {
            Task { await self.cancel() }
        }
        for reader in readers { await reader.value }
        process = nil
        self.waiting = nil
        return DeveloperToolResult(
            exitCode: status, stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self), truncated: truncated)
    }
    private func capture(_ data: Data, error: Bool) {
        let available = max(0, 1_048_576 - (error ? stderr.count : stdout.count))
        if error { stderr.append(data.prefix(available)) } else { stdout.append(data.prefix(available)) }
        if data.count > available { truncated = true }
    }
    public func cancel() {
        cancelled = true
        guard let child = process else { return }
        child.signal(SIGINT)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(3))
            child.signal(SIGTERM)
            try? await Task.sleep(for: .seconds(2))
            child.signal(SIGKILL)
        }
    }
    public func stop() async {
        cancel()
        _ = await waiting?.value
    }
}
