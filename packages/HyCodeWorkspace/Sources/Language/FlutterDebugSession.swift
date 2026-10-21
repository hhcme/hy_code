import Foundation

/// One explicit Flutter run/debug session and one owned DAP child process group.
/// No discovery, launch, file write, terminal or device activity occurs at init.
public actor FlutterDebugSession {
    public nonisolated let events: AsyncStream<JSONValue>
    private let emitter: AsyncStream<JSONValue>.Continuation
    private let connection: StdioProtocolConnection
    private var listener: Task<Void, Never>?
    private var configuration: Task<Void, Never>?
    private var stopped = false
    private var started = false
    private var configuring = false
    private var initializeReady = false
    private var initializedReceived = false
    private var launchSent = false
    private var capabilities = JSONValue.null
    private var shutdown: Task<Void, Never>?
    private var breakpoints: [String: [FlutterBreakpoint]] = [:]
    private var resolution = FlutterBreakpointResolution()
    private var resolutionFlush: Task<Void, Never>?
    public init(connection: StdioProtocolConnection = StdioProtocolConnection(wire: .debugAdapter)) {
        self.connection = connection
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingOldest(512))
        events = stream.stream
        emitter = stream.continuation
    }
    public func start(
        executable: URL, arguments: [String], directory: URL, launch: JSONValue,
        breakpoints: [String: [FlutterBreakpoint]]
    ) async throws {
        guard !started && !stopped else { throw CancellationError() }
        started = true
        self.breakpoints = breakpoints
        try await connection.start(executable: executable, arguments: arguments, directory: directory)
        listener = Task { [weak self, connection] in
            for await event in connection.events { await self?.receive(event) }
        }
        do {
            capabilities = try await connection.request(
                "initialize",
                params: JSONValue([
                    "clientID": "hycode", "clientName": "HyCode", "adapterID": "dart",
                    "linesStartAt1": true, "columnsStartAt1": true, "pathFormat": "path",
                    "supportsVariableType": true, "supportsVariablePaging": true,
                    "supportsRunInTerminalRequest": false, "supportsProgressReporting": false,
                ]))
            initializeReady = true
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            _ = try await connection.request("launch", params: launch, timeout: 120) { [weak self] in
                await self?.didSendLaunch()
            }
        } catch {
            await stop()
            throw error
        }
    }
    private func receive(_ event: JSONValue) async {
        guard !stopped else { return }
        if event["event"].string == "initialized" {
            initializedReceived = true
            configureWhenReady()
        }
        if event["event"].string == "breakpoint" {
            resolution.receive(event)
            publishBreakpoints()
            return
        }
        // Normalize owned-transport failure without conflating DAP with LSP.
        let value =
            event["method"].string == "hycode/disconnected"
            ? JSONValue(["type": "event", "event": "hycode/disconnected"]) : event
        if case .dropped = emitter.yield(value) { await stop() }
    }
    private func publishBreakpoints() {
        guard resolutionFlush == nil else { return }
        resolutionFlush = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            await self?.flushBreakpoints()
        }
    }
    private func flushBreakpoints() async {
        resolutionFlush = nil
        if case .dropped = emitter.yield(JSONValue(["event": "hycode/breakpoints", "body": resolution.snapshot])) {
            await stop()
        }
    }
    private func didSendLaunch() {
        launchSent = true
        configureWhenReady()
    }
    private func configureWhenReady() {
        guard initializeReady, initializedReceived, launchSent, !configuring, !stopped else { return }
        configuring = true
        configuration = Task { [weak self] in await self?.configure() }
    }
    private func configure() async {
        do {
            for path in breakpoints.keys.sorted() {
                _ = try await setBreakpoints(path: path, values: breakpoints[path] ?? [])
            }
            let defaults = capabilities["exceptionBreakpointFilters"].array.filter { $0["default"] == .bool(true) }
                .compactMap { $0["filter"].string }
            _ = try await request("setExceptionBreakpoints", JSONValue(["filters": defaults]))
            if capabilities["supportsConfigurationDoneRequest"] == .bool(true) {
                _ = try await request("configurationDone")
            }
        } catch {
            emitter.yield(
                JSONValue(["type": "event", "event": "output", "body": ["output": error.localizedDescription]]))
            await stop()
        }
    }
    public func setBreakpoints(path: String, values: [FlutterBreakpoint]) async throws -> JSONValue {
        guard path.utf8.count <= 8_192, values.count <= 1_000,
            values.allSatisfy({
                $0.line > 0 && $0.line <= 10_000_000 && $0.condition.count <= 4_096 && $0.logMessage.count <= 4_096
            })
        else { throw LanguageServiceFailure("断点数量、位置或表达式超出限制") }
        guard breakpoints.values.reduce(0, { $0 + $1.count }) - (breakpoints[path]?.count ?? 0) + values.count <= 1_000
        else {
            throw LanguageServiceFailure("会话断点总数超出限制")
        }
        breakpoints[path] = values
        let result = try await request(
            "setBreakpoints",
            .object([
                "source": JSONValue(["path": path]), "breakpoints": .array(values.filter(\.enabled).map(\.dap)),
                "sourceModified": .bool(false),
            ]))
        resolution.response(path: path, requested: values, result: result)
        publishBreakpoints()
        return result
    }
    public func request(_ command: String, _ arguments: JSONValue = .object([:]), timeout: Int = 15) async throws
        -> JSONValue
    {
        guard started && !stopped else { throw CancellationError() }
        return try await connection.request(command, params: arguments, timeout: timeout)
    }
    public func stop() async {
        if let shutdown {
            await shutdown.value
            return
        }
        stopped = true
        configuration?.cancel()
        resolutionFlush?.cancel()
        resolutionFlush = nil
        configuration = nil
        listener?.cancel()
        listener = nil
        let connection = connection
        let shutdown = Task {
            _ = try? await connection.request("disconnect", params: JSONValue(["terminateDebuggee": true]), timeout: 2)
            await connection.stop()
        }
        self.shutdown = shutdown
        await shutdown.value
        emitter.yield(JSONValue(["event": "hycode/disconnected"]))
        emitter.finish()
    }
}
