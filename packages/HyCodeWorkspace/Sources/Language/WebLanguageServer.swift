import Darwin
import Foundation

/// One workspace owns lazy language processes. Vue's TypeScript tunnel stays
/// inside this actor; arbitrary workspace commands are never forwarded.
public actor WebLanguageServer {
    public nonisolated let events: AsyncStream<JSONValue>
    let emitter: AsyncStream<JSONValue>.Continuation
    let root: URL
    private let tools: WebToolchain
    private let trace: Bool
    let allowProjectPlugins: Bool
    private var connections: [WebLanguage.Service: LanguageServerConnection] = [:]
    private var startups: [WebLanguage.Service: Task<Void, Error>] = [:]
    private var listeners: [WebLanguage.Service: Task<Void, Never>] = [:]
    var opened: [String: WebLanguage] = [:]
    var stopped = false
    let documentQueue = LSPDocumentQueue()
    var liveURIs = Set<String>()
    var projectFiles: [String: ProjectSourceFile] = [:]
    var backgroundURIs = Set<String>()
    var registeredFiles: [String: ProjectSourceFile] = [:]
    var failedFiles = Set<String>()
    var hasTypeScriptProject = false
    private var bridges: [Int: Task<Void, Never>] = [:]
    public private(set) var bridgeRequests = 0
    public private(set) var bridgeResponses = 0
    public init(root: URL, tools: WebToolchain, trace: Bool = false, allowProjectPlugins: Bool = false) {
        self.root = root
        self.tools = tools
        self.trace = trace
        self.allowProjectPlugins = allowProjectPlugins
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingNewest(512))
        events = stream.stream
        emitter = stream.continuation
    }
    func connection(_ service: WebLanguage.Service) async throws -> LanguageServerConnection {
        guard !stopped else { throw CancellationError() }
        if service == .vue {
            guard allowProjectPlugins else { throw LanguageServiceFailure("Vue 分析可能加载项目插件，请在 Web 分析面板显式信任当前工作区") }
            _ = try await connection(.typescript)
        }
        if let task = startups[service], let connection = connections[service] {
            try await task.value
            return connection
        }
        let connection = LanguageServerConnection()
        connections[service] = connection
        let root = root
        let tools = tools
        let allowProjectPlugins = allowProjectPlugins
        let task = Task {
            let initialization = Self.options(service, tools: tools, allowProjectPlugins: allowProjectPlugins)
            let configuration = Self.configuration
            try await connection.start(
                executable: tools.node,
                arguments: ["--max-old-space-size=512", tools.script(service).path, "--stdio"], directory: root,
                configuration: configuration, environment: tools.environment)
            do {
                let response = try await connection.request(
                    "initialize",
                    params: JSONValue([
                        "processId": Int(getpid()), "clientInfo": ["name": "HyCode", "version": "0.1.0"],
                        "rootUri": root.absoluteString,
                        "workspaceFolders": [["uri": root.absoluteString, "name": root.lastPathComponent]],
                        "capabilities": [
                            "general": ["positionEncodings": ["utf-16"]],
                            "workspace": ["configuration": true, "workspaceFolders": true, "applyEdit": false],
                            "textDocument": [
                                "synchronization": ["didSave": true],
                                "publishDiagnostics": [
                                    "versionSupport": true, "relatedInformation": true, "dataSupport": true,
                                ],
                                "hover": ["contentFormat": ["markdown", "plaintext"]],
                                "definition": ["linkSupport": true],
                                "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
                                "completion": [
                                    "completionItem": [
                                        "snippetSupport": true,
                                        "documentationFormat": ["plaintext"],
                                        "resolveSupport": ["properties": ["additionalTextEdits", "textEdit"]],
                                    ]
                                ],
                                "codeAction": [
                                    "codeActionLiteralSupport": [
                                        "codeActionKind": [
                                            "valueSet": ["quickfix", "source.organizeImports", "refactor"]
                                        ]
                                    ],
                                    "resolveSupport": ["properties": ["edit"]],
                                ],
                            ],
                        ], "initializationOptions": initialization,
                    ]), timeout: 45)
                if let encoding = response["capabilities"]["positionEncoding"].string, encoding != "utf-16" {
                    throw LanguageServiceFailure("Web 服务使用不支持的位置编码：" + encoding)
                }
                try await connection.notify("initialized", params: JSONValue([:]))
                try await connection.notify(
                    "workspace/didChangeConfiguration", params: .object(["settings": configuration]))
            } catch {
                await connection.stop()
                throw error
            }
        }
        startups[service] = task
        listeners[service] = Task { [weak self] in
            for await event in connection.events { await self?.receive(event, service: service) }
        }
        try await task.value
        guard !stopped else { throw CancellationError() }
        return connection
    }
    private static let configuration = JSONValue([
        "typescript": ["format": ["enable": true], "suggest": ["completeFunctionCalls": false]],
        "javascript": ["format": ["enable": true]],
        "implicitProjectConfiguration": ["checkJs": true],
        "html": ["format": ["enable": true], "validate": ["scripts": true, "styles": true]],
        "css": ["validate": true], "scss": ["validate": true], "less": ["validate": true],
        "json": ["validate": ["enable": true], "format": ["enable": true], "schemaDownload": ["enable": false]],
    ])
    private static func options(_ service: WebLanguage.Service, tools: WebToolchain, allowProjectPlugins: Bool)
        -> JSONValue
    {
        if service == .typescript {
            return JSONValue([
                "hostInfo": "HyCode", "disableAutomaticTypingAcquisition": true, "maxTsServerMemory": 512,
                "tsserver": [
                    "path": tools.services.appendingPathComponent("node_modules/typescript/lib/tsserver.js").path,
                    "useSyntaxServer": "never", "logVerbosity": "off",
                ],
                "plugins": allowProjectPlugins
                    ? [
                        [
                            "name": "@vue/typescript-plugin",
                            "location": tools.services.appendingPathComponent("node_modules/@vue/language-server").path,
                            "languages": ["vue"],
                        ]
                    ] : [],
                "preferences": ["includeCompletionsForModuleExports": true, "includeCompletionsWithInsertText": true],
            ])
        }
        if service == .html { return JSONValue(["provideFormatter": true]) }
        if service == .json { return JSONValue(["provideFormatter": true, "handledSchemaProtocols": []]) }
        return JSONValue([:])
    }
    private func receive(_ event: JSONValue, service: WebLanguage.Service) {
        guard !stopped else { return }
        if trace {
            emitter.yield(
                JSONValue([
                    "method": "hycode/serviceEvent",
                    "params": [
                        "service": service.rawValue,
                        "method": event["method"].string ?? "unknown",
                    ],
                ]))
        }
        if service == .vue, event["method"].string == "tsserver/request" {
            let raw = event["params"].array
            // vscode-jsonrpc's string notification overload wraps its single
            // array argument as one positional parameter on the wire.
            let nested = raw.count == 1 && raw[0].array.count == 3
            let values = nested ? raw[0].array : raw
            guard values.count == 3, let id = values[0].int, let command = values[1].string,
                command.count <= 256, bridges[id] == nil
            else { return }
            if bridges.count >= 64 {
                let reply = JSONValue.array([.number(Double(id)), .null])
                Task {
                    try? await connections[.vue]?.notify("tsserver/response", params: nested ? .array([reply]) : reply)
                }
                return
            }
            let payload = values[2]
            bridgeRequests += 1
            bridges[id] = Task { [weak self] in
                await self?.forward(id: id, command: command, payload: payload, nested: nested)
            }
            return
        }
        if case .object(var value) = event {
            value["hycodeService"] = .string(service.rawValue)
            emitter.yield(.object(value))
        }
    }
    private func forward(id: Int, command: String, payload: JSONValue, nested: Bool) async {
        defer { bridges[id] = nil }
        var result = JSONValue.null
        do {
            let ts = try await connection(.typescript)
            let response = try await ts.request(
                "workspace/executeCommand",
                params: .object([
                    "command": .string("typescript.tsserverRequest"),
                    "arguments": .array([
                        .string(command), payload, JSONValue(["isAsync": false, "lowPriority": true]),
                    ]),
                ]))
            result = response["body"]
        } catch {}
        guard !stopped else { return }
        bridgeResponses += 1
        let response = JSONValue.array([.number(Double(id)), result])
        try? await connections[.vue]?.notify("tsserver/response", params: nested ? .array([response]) : response)
    }
    public func open(uri: String, language: WebLanguage, text: String, version: Int) async throws {
        try await documentQueue.run {
            try await self.openLive(uri: uri, language: language, text: text, version: version)
        }
    }
    private func openLive(uri: String, language: WebLanguage, text: String, version: Int) async throws {
        guard !stopped else { throw CancellationError() }
        if backgroundURIs.remove(uri) != nil { await closeDocument(uri: uri) }
        // Native JSON may open before discovery finds a TS project. Keep its
        // service overlay from the start; Swift retains no second text buffer.
        if language == .json && !hasTypeScriptProject {
            _ = try await tsCommand(
                "updateOpen",
                JSONValue([
                    "openFiles": [
                        [
                            "file": URL(string: uri)?.path ?? "", "projectRootPath": root.path, "fileContent": text,
                        ]
                    ]
                ]))
        }
        try await openDocument(uri: uri, language: language, text: text, version: version)
        liveURIs.insert(uri)
    }
    func openDocument(uri: String, language: WebLanguage, text: String, version: Int) async throws {
        let target = try await connection(language.service)
        let params = JSONValue([
            "textDocument": ["uri": uri, "languageId": language.rawValue, "version": version, "text": text]
        ])
        if language == .vue { try await connections[.typescript]?.notify("textDocument/didOpen", params: params) }
        if language == .json && hasTypeScriptProject {
            _ = try await tsCommand(
                "updateOpen",
                JSONValue([
                    "openFiles": [
                        [
                            "file": URL(string: uri)?.path ?? "", "projectRootPath": root.path, "fileContent": text,
                        ]
                    ]
                ]))
        }
        try await target.notify("textDocument/didOpen", params: params)
        opened[uri] = language
    }
    public func change(uri: String, range: LSPRange, text: String, version: Int) async throws {
        try await documentQueue.run {
            try await self.changeDocument(uri: uri, range: range, text: text, version: version)
        }
    }
    private func changeDocument(uri: String, range: LSPRange, text: String, version: Int) async throws {
        guard let language = opened[uri] else { return }
        let params = JSONValue([
            "textDocument": ["uri": uri, "version": version],
            "contentChanges": [["range": range.json, "text": text]],
        ])
        if language == .vue { try await connections[.typescript]?.notify("textDocument/didChange", params: params) }
        if language == .json && connections[.typescript] != nil {
            _ = try await tsCommand(
                "updateOpen",
                JSONValue([
                    "changedFiles": [
                        [
                            "fileName": URL(string: uri)?.path ?? "",
                            "textChanges": [
                                [
                                    "start": ["line": range.start.line + 1, "offset": range.start.character + 1],
                                    "end": ["line": range.end.line + 1, "offset": range.end.character + 1],
                                    "newText": text,
                                ]
                            ],
                        ]
                    ]
                ]))
        }
        try await connections[language.service]?.notify("textDocument/didChange", params: params)
    }
    public func close(uri: String) async {
        try? await documentQueue.run { await self.closeLive(uri: uri) }
    }
    private func closeLive(uri: String) async {
        liveURIs.remove(uri)
        await closeDocument(uri: uri)
        if let file = projectFiles[uri], !stopped {
            try? await registerBackground(file)
        }
    }
    func closeDocument(uri: String) async {
        guard let language = opened.removeValue(forKey: uri) else { return }
        let params = JSONValue(["textDocument": ["uri": uri]])
        if language == .vue { try? await connections[.typescript]?.notify("textDocument/didClose", params: params) }
        if language == .json && connections[.typescript] != nil {
            _ = try? await tsCommand("updateOpen", JSONValue(["closedFiles": [URL(string: uri)?.path ?? ""]]))
        }
        try? await connections[language.service]?.notify("textDocument/didClose", params: params)
    }
    public func saved(uri: String) async {
        guard let language = opened[uri] else { return }
        let params = JSONValue(["textDocument": ["uri": uri]])
        if language == .vue { try? await connections[.typescript]?.notify("textDocument/didSave", params: params) }
        try? await connections[language.service]?.notify("textDocument/didSave", params: params)
    }
    public func request(_ method: String, uri: String, position: LSPPosition?, parameters: [String: JSONValue] = [:])
        async throws -> JSONValue
    {
        guard let language = opened[uri] else { throw LanguageServiceFailure("Web 文档尚未同步") }
        if method == "completionItem/resolve" || method == "codeAction/resolve" {
            let service =
                parameters["hycodeService"]?.string.flatMap(WebLanguage.Service.init(rawValue:)) ?? language.service
            let target = try await connection(service)
            var raw = parameters
            raw["hycodeService"] = nil
            let result = try await target.request(method, params: .object(raw))
            return Self.tag(result, service: service)
        }
        var params = parameters
        if params["textDocument"] == nil { params["textDocument"] = JSONValue(["uri": uri]) }
        if let position { params["position"] = position.json }
        if method == "textDocument/references" { params["context"] = JSONValue(["includeDeclaration": true]) }
        if method == "textDocument/formatting" { params["options"] = JSONValue(["tabSize": 2, "insertSpaces": true]) }
        if language == .vue {
            if method == "textDocument/completion" || method == "textDocument/codeAction" {
                var items: [JSONValue] = []
                var seen = Set<String>()
                for service in [WebLanguage.Service.typescript, .vue] {
                    guard let result = try? await requestOn(service, method, params) else { continue }
                    for item in (result["items"] == .null ? result.array : result["items"].array) {
                        let key =
                            (item["label"].string ?? item["title"].string ?? "") + "|"
                            + (item["insertText"].string ?? "")
                        if case .object(var value) = item, seen.insert(key).inserted {
                            value["hycodeService"] = .string(service.rawValue)
                            items.append(.object(value))
                        }
                    }
                }
                return method == "textDocument/completion"
                    ? .object(["items": .array(items), "isIncomplete": .bool(true)]) : .array(items)
            }
            let first: WebLanguage.Service = method == "textDocument/formatting" ? .vue : .typescript
            let second: WebLanguage.Service = first == .vue ? .typescript : .vue
            if let value = try? await requestOn(first, method, params), value != .null,
                value != .array([]), value != .object([:])
            {
                return value
            }
            return try await requestOn(second, method, params)
        }
        return try await requestOn(language.service, method, params)
    }
    private func requestOn(_ service: WebLanguage.Service, _ method: String, _ params: [String: JSONValue]) async throws
        -> JSONValue
    {
        let target = try await connection(service)
        var params = params
        if method == "textDocument/codeAction", case .object(var context) = params["context"] {
            context["diagnostics"] = .array(
                (context["diagnostics"]?.array ?? []).filter {
                    $0["hycodeService"].string == nil || $0["hycodeService"].string == service.rawValue
                }.map { diagnostic in
                    guard case .object(var value) = diagnostic else { return diagnostic }
                    value["hycodeService"] = nil
                    return .object(value)
                })
            params["context"] = .object(context)
        }
        let value = try await target.request(method, params: .object(params))
        if method == "textDocument/rename" { return Self.tag(value, service: service) }
        if method == "textDocument/codeAction" {
            return .array(value.array.map { Self.tag($0, service: service) })
        }
        if method == "textDocument/completion" {
            let items = (value["items"] == .null ? value.array : value["items"].array).map { item -> JSONValue in
                guard case .object(var object) = item else { return item }
                object["hycodeService"] = .string(service.rawValue)
                return .object(object)
            }
            return .object(["items": .array(items), "isIncomplete": value["isIncomplete"]])
        }
        return value
    }
    private static func tag(_ value: JSONValue, service: WebLanguage.Service) -> JSONValue {
        guard case .object(var fields) = value else { return value }
        fields["hycodeService"] = .string(service.rawValue)
        return .object(fields)
    }
    public func stop() async {
        stopped = true
        for task in startups.values { task.cancel() }
        for task in listeners.values { task.cancel() }
        for task in bridges.values { task.cancel() }
        let tasks = Array(startups.values)
        for connection in connections.values { await connection.stop() }
        for task in tasks { _ = try? await task.value }
        connections.removeAll()
        startups.removeAll()
        listeners.removeAll()
        bridges.removeAll()
        opened.removeAll()
        projectFiles.removeAll()
        liveURIs.removeAll()
        backgroundURIs.removeAll()
        registeredFiles.removeAll()
        failedFiles.removeAll()
        hasTypeScriptProject = false
        emitter.finish()
    }
}
