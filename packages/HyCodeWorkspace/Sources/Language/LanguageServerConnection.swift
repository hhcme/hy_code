import Darwin
import Foundation

private actor LanguageServerWriter {
    let handle: FileHandle
    private let queue = DispatchQueue(label: "HyCode.LanguageWriter", qos: .utility)
    private var closed = false
    init(_ handle: FileHandle) {
        self.handle = handle
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    func write(_ data: Data) async throws {
        guard !closed else { throw LanguageServiceFailure("语言服务写端已关闭") }
        let handle = handle
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try handle.write(contentsOf: data)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func close() async {
        closed = true
        let handle = handle
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                try? handle.close()
                continuation.resume()
            }
        }
    }
}

/// Owns one stdio child and every request continuation. Blocking reads run on
/// utility workers; all framing, writes, replies and shutdown are actor-serial.
public enum StdioProtocol: Sendable { case languageServer, debugAdapter }

public actor StdioProtocolConnection {
    public nonisolated let events: AsyncStream<JSONValue>
    private let emitter: AsyncStream<JSONValue>.Continuation
    private var process: OwnedToolProcess?
    private var exitWait: Task<Int32, Never>?
    private let input = Pipe()
    private var framing = LSPFraming()
    private var nextID = 0
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [Int: Pending] = [:]
    private var readers: [Task<Void, Never>] = []
    private var alive = false
    private var started = false
    private var terminating = false
    private var writer: LanguageServerWriter?
    private var configuration = JSONValue.null
    private var schemaRoot: URL?
    // Keep failed/missing dependencies as well: a full rescan must invalidate
    // the upstream cache after creation, deletion or watcher overflow.
    private var schemaURIs = Set<String>()
    private let wire: StdioProtocol
    public init(wire: StdioProtocol = .languageServer) {
        self.wire = wire
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingNewest(512))
        events = stream.stream
        emitter = stream.continuation
    }
    public func start(
        executable: URL, arguments: [String], directory: URL, configuration: JSONValue = .null,
        environment: [String: String] = [:], schemaRoot: URL? = nil
    ) throws {
        guard !started else { throw LanguageServiceFailure("此连接不能重复启动，请创建新连接") }
        started = true
        writer = LanguageServerWriter(input.fileHandleForWriting)
        self.configuration = configuration
        self.schemaRoot = schemaRoot
        let child = try OwnedToolProcess.launch(
            executable: executable, arguments: arguments, directory: directory, input: input.fileHandleForReading,
            environment: environment.merging(["DASH__IDE_NAME": "HyCode", "DASH__IDE_VERSION": "0.1.0"]) { _, new in new
            })
        process = child
        try? input.fileHandleForReading.close()
        alive = true
        let stdout = child.stdout
        let stderr = child.stderr
        exitWait = Task.detached(priority: .utility) { [weak self] in
            let status = await ToolBlockingIO.wait(child)
            await self?.disconnected()
            return status
        }
        readers.append(
            Task.detached(priority: .utility) { [weak self] in
                defer { try? stdout.close() }
                while true {
                    let data = await ToolBlockingIO.read(stdout, capacity: 65_536)
                    guard !data.isEmpty else { break }
                    await self?.receive(data)
                }
                await self?.disconnected()
            })
        // Drain stderr to prevent pipe backpressure. Protocol errors are exposed
        // by requests/exit; stderr is never retained without a bounded log owner.
        readers.append(
            Task.detached(priority: .utility) { [weak self] in
                defer { try? stderr.close() }
                while true {
                    let data = await ToolBlockingIO.read(stderr, capacity: 16_384)
                    guard !data.isEmpty else { break }
                    await self?.stderrMessage(String(decoding: data, as: UTF8.self))
                }
            })
    }
    private func stderrMessage(_ text: String) {
        let message =
            wire == .languageServer
            ? JSONValue(["method": "hycode/stderr", "params": ["message": String(text.prefix(4_096))]])
            : JSONValue([
                "type": "event", "event": "output",
                "body": ["category": "stderr", "output": String(text.prefix(4_096))],
            ])
        if case .dropped = emitter.yield(message), wire == .debugAdapter { disconnected() }
    }
    public func request(
        _ method: String, params: JSONValue, timeout: Int = 15,
        onSent: (@Sendable () async -> Void)? = nil
    ) async throws -> JSONValue {
        try Task.checkCancellation()
        guard alive, pending.count < 128 else { throw LanguageServiceFailure("语言服务未连接或请求过多") }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    await self?.expire(id)
                }
                pending[id] = Pending(continuation: continuation, timeout: timer)
                Task { [weak self] in await self?.sendRequest(id, method: method, params: params, onSent: onSent) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func sendRequest(
        _ id: Int, method: String, params: JSONValue, onSent: (@Sendable () async -> Void)?
    ) async {
        guard pending[id] != nil else { return }
        do {
            let message =
                wire == .languageServer
                ? JSONValue(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
                : JSONValue(["seq": id, "type": "request", "command": method, "arguments": params])
            try await write(message)
            await onSent?()
        } catch {
            if let request = pending.removeValue(forKey: id) {
                request.timeout.cancel()
                request.continuation.resume(throwing: error)
            }
        }
    }
    func invalidateSchemaDependencies(changed: Set<String>?) async {
        let paths = changed.map { Set($0.compactMap { URL(string: $0)?.path }) }
        let changes = schemaURIs.filter { uri in
            guard let paths else { return true }
            return URL(string: uri).map { paths.contains($0.path) } == true
        }.sorted().map { JSONValue(["uri": $0, "type": 2]) }
        guard !changes.isEmpty else { return }
        try? await notify("workspace/didChangeWatchedFiles", params: .object(["changes": .array(changes)]))
    }
    public func notify(_ method: String, params: JSONValue) async throws {
        guard alive, wire == .languageServer else { throw LanguageServiceFailure("语言服务已断开或不支持通知") }
        try await write(JSONValue(["jsonrpc": "2.0", "method": method, "params": params]))
    }
    private func write(_ message: JSONValue) async throws {
        guard alive, let writer else { throw LanguageServiceFailure("语言服务已断开") }
        try await writer.write(LSPFraming.encode(message))
    }
    private func receive(_ data: Data) async {
        guard alive else { return }
        do {
            for message in try framing.append(data) {
                if wire == .debugAdapter {
                    try await receiveDAP(message)
                    continue
                }
                if let method = message["method"].string {
                    if message["id"] != .null {
                        try await respond(to: message, method: method)
                    } else {
                        emitter.yield(message)
                    }
                } else if let id = message["id"].int, let request = pending.removeValue(forKey: id) {
                    request.timeout.cancel()
                    let continuation = request.continuation
                    if message["error"] != .null {
                        continuation.resume(
                            throwing: LanguageServiceFailure(message["error"]["message"].string ?? "语言服务请求失败"))
                    } else {
                        continuation.resume(returning: message["result"])
                    }
                }
            }
        } catch {
            disconnected()
            terminate()
        }
    }
    private func receiveDAP(_ message: JSONValue) async throws {
        switch message["type"].string {
        case "event":
            let event: JSONValue
            if message["event"].string == "output" {
                event = JSONValue([
                    "type": "event", "event": "output",
                    "body": [
                        "category": String((message["body"]["category"].string ?? "console").prefix(64)),
                        "output": String((message["body"]["output"].string ?? "").prefix(16_384)),
                    ],
                ])
            } else {
                guard try JSONEncoder().encode(message).count <= 65_536 else { throw LanguageServiceFailure("调试事件过大") }
                event = message
            }
            if case .dropped = emitter.yield(event) {
                throw LanguageServiceFailure("调试事件积压，已断开以防状态错乱")
            }
        case "response":
            guard let id = message["request_seq"].int, let request = pending.removeValue(forKey: id) else { return }
            request.timeout.cancel()
            if message["success"] == .bool(true) {
                request.continuation.resume(returning: message["body"])
            } else {
                request.continuation.resume(
                    throwing: LanguageServiceFailure(
                        message["message"].string ?? message["body"]["error"]["format"].string ?? "调试请求失败"))
            }
        case "request":
            // Never let an adapter spawn a terminal or debugger through a reverse
            // request. Launching is exclusively the explicit owned process path.
            nextID += 1
            try await write(
                JSONValue([
                    "seq": nextID, "type": "response", "request_seq": message["seq"],
                    "command": message["command"], "success": false, "message": "Unsupported client request",
                ]))
        default: throw LanguageServiceFailure("调试协议消息无效")
        }
    }
    private func respond(to message: JSONValue, method: String) async throws {
        let result: JSONValue
        switch method {
        case "workspace/configuration":
            result = .array(
                message["params"]["items"].array.map { item in
                    let section = item["section"].string ?? ""
                    if section.isEmpty { return configuration }
                    if section == "dart", configuration["dart"] == .null { return configuration }
                    return section.split(separator: ".").reduce(configuration) { $0[String($1)] }
                })
        case "hycode/schemaContent":
            do {
                guard let root = schemaRoot else {
                    throw LanguageServiceFailure("Schema 读取未启用")
                }
                let uri = try ConfigurationSchemas.requestURI(message["params"])
                _ = try ConfigurationSchemas.relativePath(uri, root: root)
                guard schemaURIs.contains(uri) || schemaURIs.count < 500 else {
                    throw LanguageServiceFailure("项目 Schema 依赖数量超限（500）")
                }
                schemaURIs.insert(uri)
                result = .string(try await ConfigurationSchemas.readLocal(uri, root: root))
            } catch {
                try await write(
                    JSONValue([
                        "jsonrpc": "2.0", "id": message["id"],
                        "error": ["code": -32602, "message": String(error.localizedDescription.prefix(2000))],
                    ]))
                return
            }
        case "client/registerCapability", "client/unregisterCapability", "window/workDoneProgress/create":
            result = .null
        case "workspace/applyEdit": result = JSONValue(["applied": false, "failureReason": "请使用编辑器中的显式编辑入口"])
        case "window/showMessageRequest": result = .null
        default:
            try await write(
                JSONValue([
                    "jsonrpc": "2.0", "id": message["id"],
                    "error": ["code": -32601, "message": "Unsupported client request"],
                ]))
            return
        }
        // JSONValue embedded in Any dictionaries must stay a JSONValue, rather
        // than passing through the Foundation conversion initializer again.
        try await write(.object(["jsonrpc": .string("2.0"), "id": message["id"], "result": result]))
    }
    private func expire(_ id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(throwing: LanguageServiceFailure("语言服务请求超时"))
        if wire == .languageServer { Task { try? await notify("$/cancelRequest", params: JSONValue(["id": id])) } }
    }
    private func cancel(_ id: Int) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(throwing: CancellationError())
        if wire == .languageServer { Task { try? await notify("$/cancelRequest", params: JSONValue(["id": id])) } }
    }
    private func disconnected() {
        guard alive else { return }
        alive = false
        terminate()
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.timeout.cancel()
            request.continuation.resume(throwing: LanguageServiceFailure("语言服务已退出，可重新启动"))
        }
        emitter.yield(JSONValue(["method": "hycode/disconnected"]))
        emitter.finish()
    }
    public func stop() async {
        started = true
        disconnected()
        terminate()
        _ = await exitWait?.value
        for reader in readers { await reader.value }
        readers.removeAll()
        await writer?.close()
        process = nil
        exitWait = nil
    }
    private func terminate() {
        guard !terminating, let child = process else { return }
        terminating = true
        child.signal(SIGTERM)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            child.signal(SIGKILL)
        }
    }
}

/// Source-compatible name for the language-service policy of the owned transport.
public typealias LanguageServerConnection = StdioProtocolConnection
