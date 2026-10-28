import Darwin
import Foundation

private actor CodexPipeWriter {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "HyCode.CodexWriter", qos: .utility)
    private var closed = false
    init(_ handle: FileHandle) {
        self.handle = handle
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    func write(_ data: Data) async throws {
        guard !closed else { throw LanguageServiceFailure("Codex 写端已关闭") }
        let handle = handle
        try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try handle.write(contentsOf: data)
                    reply.resume()
                } catch { reply.resume(throwing: error) }
            }
        }
    }
    func close() async {
        closed = true
        let handle = handle
        await withCheckedContinuation { (reply: CheckedContinuation<Void, Never>) in
            queue.async {
                try? handle.close()
                reply.resume()
            }
        }
    }
}

/// JSONL is deliberately separate from LSP/DAP framing. Owns a single child,
/// bounded events and request continuations. No inherited environment or sockets.
public actor CodexJSONLConnection {
    public nonisolated let events: AsyncStream<JSONValue>
    private let emitter: AsyncStream<JSONValue>.Continuation
    private let input = Pipe()
    private var process: OwnedToolProcess?
    private var writer: CodexPipeWriter?
    private var waiting: Task<Int32, Never>?
    private var readers: [Task<Void, Never>] = []
    private var buffer = Data()
    private var nextID = 0
    private var started = false
    private var stopped = false
    private var alive = false
    private var diagnosticBytes = Data()
    private var diagnosticTruncated = false
    private var secrets: [String] = []
    private struct Pending {
        let reply: CheckedContinuation<JSONValue, Error>
        let timer: Task<Void, Never>
    }
    private var pending: [Int: Pending] = [:]
    public init() {
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingOldest(256))
        events = stream.stream
        emitter = stream.continuation
    }
    public func start(executable: URL, arguments: [String], directory: URL, environment: [String: String]) throws {
        guard !started, !stopped else { throw LanguageServiceFailure("Codex 连接已使用或已停止") }
        started = true
        secrets = environment.filter { $0.key.hasSuffix("KEY") || $0.key.hasSuffix("TOKEN") }.map(\.value).filter {
            !$0.isEmpty
        }
        let child = try OwnedToolProcess.launch(
            executable: executable, arguments: arguments, directory: directory, input: input.fileHandleForReading,
            environment: environment, inheritEnvironment: false)
        process = child
        writer = CodexPipeWriter(input.fileHandleForWriting)
        try? input.fileHandleForReading.close()
        alive = true
        waiting = Task.detached(priority: .utility) { await ToolBlockingIO.wait(child) }
        readers.append(
            Task.detached(priority: .utility) { [weak self] in
                defer { try? child.stdout.close() }
                while true {
                    let data = await ToolBlockingIO.read(child.stdout, capacity: 16_384)
                    guard !data.isEmpty else { break }
                    await self?.receive(data)
                }
                await self?.disconnect()
            })
        readers.append(
            Task.detached(priority: .utility) { [weak self] in
                // Retain only a bounded diagnostic tail; redact before exposing it.
                defer { try? child.stderr.close() }
                while true {
                    let data = await ToolBlockingIO.read(child.stderr, capacity: 8_192)
                    guard !data.isEmpty else { break }
                    await self?.diagnostic(data)
                }
            })
    }
    private func diagnostic(_ data: Data) {
        guard !diagnosticTruncated else { return }
        diagnosticBytes.append(data)
        if diagnosticBytes.count > 8_192 {
            diagnosticBytes.removeAll()
            diagnosticTruncated = true
        }
    }
    public func diagnostic() -> String {
        diagnosticTruncated ? "后台诊断超过显示预算" : redacted(String(decoding: diagnosticBytes, as: UTF8.self))
    }
    private func redacted(_ text: String) -> String {
        secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: "[已隐藏密钥]") }
    }
    public func request(_ method: String, params: JSONValue, timeout: Int = 20) async throws -> JSONValue {
        try Task.checkCancellation()
        guard alive, pending.count < 32 else { throw LanguageServiceFailure("Codex 未连接或请求数量超限") }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { reply in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    await self?.expire(id)
                }
                pending[id] = Pending(reply: reply, timer: timer)
                Task { [weak self] in
                    do { try await self?.send(JSONValue(["id": id, "method": method, "params": params])) } catch {
                        await self?.disconnect()
                    }
                }
            }
        } onCancel: {
            Task { await self.stop() }
        }
    }
    public func notify(_ method: String, params: JSONValue = .object([:])) async throws {
        try await send(JSONValue(["method": method, "params": params]))
    }
    public func respond(id: JSONValue, result: JSONValue) async throws {
        try await send(JSONValue(["id": id, "result": result]))
    }
    public func reject(id: JSONValue) async throws {
        try await send(JSONValue(["id": id, "error": ["code": -32601, "message": "Unsupported client request"]]))
    }
    private func send(_ message: JSONValue) async throws {
        guard alive, let writer else { throw LanguageServiceFailure("Codex 连接已断开") }
        var data = try JSONEncoder().encode(message)
        guard data.count <= 1_048_576 else { throw LanguageServiceFailure("Codex 请求超过 1 MiB") }
        data.append(10)
        try await writer.write(data)
    }
    private func receive(_ data: Data) {
        guard alive else { return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            guard end <= 2_097_152 else {
                disconnect()
                return
            }
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            if line.isEmpty { continue }
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: line),
                case .object = message
            else {
                disconnect()
                return
            }
            if message["method"].string == nil, let id = message["id"].int,
                let request = pending.removeValue(forKey: id)
            {
                request.timer.cancel()
                if message["error"] != .null {
                    let detail = redacted(String((message["error"]["message"].string ?? "协议不兼容").prefix(2_048)))
                    request.reply.resume(throwing: LanguageServiceFailure("Codex 拒绝了请求：" + detail))
                } else {
                    request.reply.resume(returning: message["result"])
                }
            } else if case .dropped = emitter.yield(message) {
                disconnect()
                return
            }
        }
        if buffer.count > 2_097_152 { disconnect() }
    }
    private func expire(_ id: Int) {
        if let request = pending.removeValue(forKey: id) {
            request.reply.resume(throwing: LanguageServiceFailure("Codex 协议请求超时"))
            request.timer.cancel()
            disconnect()
        }
    }
    private func disconnect() {
        alive = false
        for request in pending.values {
            request.timer.cancel()
            request.reply.resume(throwing: LanguageServiceFailure("Codex 后台协议已断开"))
        }
        pending.removeAll()
        emitter.finish()
        process?.signal(SIGTERM)
    }
    public func stop() async {
        if stopped {
            _ = await waiting?.value
            return
        }
        stopped = true
        disconnect()
        if let child = process {
            let escalation = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .milliseconds(400))
                child.signal(SIGKILL)
            }
            _ = await waiting?.value
            escalation.cancel()
        }
        await writer?.close()
        for reader in readers { await reader.value }
        try? input.fileHandleForReading.close()
        try? input.fileHandleForWriting.close()
        process = nil
    }
}
