import Darwin
import Foundation

/// One trusted workspace and one owned stdio child. It never installs tools,
/// launches an application or accepts reverse workspace edits/terminal requests.
public actor NativeLanguageServer {
    public nonisolated let events: AsyncStream<JSONValue>
    private let emitter: AsyncStream<JSONValue>.Continuation
    private let connection = LanguageServerConnection()
    private var listener: Task<Void, Never>?
    private var capabilities = JSONValue.null
    private var versions: [String: Int] = [:]
    private var sessions: [String: UUID] = [:]
    private var stopped = false
    private var initialized = false
    private var projectReady = false
    private var uris: NativeLanguageURIs?
    public let language: NativeCodeLanguage
    public init(language: NativeCodeLanguage) {
        self.language = language
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingNewest(512))
        events = stream.stream
        emitter = stream.continuation
    }
    public func initialize(
        root: URL, tools: NativeLanguageToolchain, cache: URL, trusted: Bool, triggerFiles: [String] = [],
        isolatedHome: URL? = nil, offline: Bool = false
    ) async throws {
        guard trusted else { throw LanguageServiceFailure("先在语言设置中信任此工作区，允许加载项目模型及构建配置") }
        guard !stopped, !initialized, tools.language == language, language != .sql else { throw CancellationError() }
        if language == .java, try !NativeWorkspacePaths.cacheIsOutsideProject(root: root, cache: cache) {
            throw LanguageServiceFailure("JDT LS 缓存必须位于项目根之外，请打开具体项目目录")
        }
        initialized = true
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let mapping = try NativeLanguageURIs(root: root)
        uris = mapping
        let protocolRoot = mapping.serverRoot
        let executable = tools.executable
        let model = try NativeProjectModel.inspect(language: language, root: root)
        let configuration: JSONValue
        let options: JSONValue
        var arguments: [String]
        var environment: [String: String] = [:]
        if language == .swift {
            arguments = [
                "--bypass-workspace-trust", "--scratch-path", cache.appendingPathComponent("swiftpm").path,
                "--generated-files-path", cache.appendingPathComponent("generated").path,
            ]
            configuration = JSONValue([:])
            // Trusted SwiftPM preparation/indexing enables workspace references.
            // It may compile targets; it never requests an application launch.
            var swiftOptions = JSONValue([
                "backgroundIndexing": true,
                "cancelTextDocumentRequestsOnEditAndClose": true,
                "swiftPM": ["forceResolvedVersions": true, "extraArguments": ["--jobs", "2"]],
            ])
            if model == .buildServer || model == .xcodeBuildServer, case .object(var fields) = swiftOptions {
                fields["defaultWorkspaceType"] = .string("buildServer")
                swiftOptions = .object(fields)
            }
            options = swiftOptions
        } else {
            guard let launcher = tools.launcher, let template = tools.configuration, let home = tools.javaHome else {
                throw LanguageServiceFailure("JDT LS 工具链不完整")
            }
            let config = cache.appendingPathComponent("configuration")
            if !FileManager.default.fileExists(atPath: config.path) {
                try FileManager.default.copyItem(at: template, to: config)
            }
            arguments = [
                "-Djava.awt.headless=true", "-Declipse.application=org.eclipse.jdt.ls.core.id1",
                "-Dosgi.bundles.defaultStartLevel=4",
                "-Declipse.product=org.eclipse.jdt.ls.core.product", "-Dlog.level=ERROR", "-Xms64m", "-Xmx768m",
                "-XX:ActiveProcessorCount=2", "-Dorg.gradle.daemon=false", "--add-modules=ALL-SYSTEM",
                "--add-opens", "java.base/java.util=ALL-UNNAMED", "--add-opens", "java.base/java.lang=ALL-UNNAMED",
                "-jar", launcher.path, "-configuration", config.path, "-data",
                cache.appendingPathComponent("workspace").path,
            ]
            if let isolatedHome { arguments.insert("-Duser.home=" + isolatedHome.path, at: 0) }
            environment["JAVA_HOME"] = home.path
            configuration = JSONValue([
                "java": [
                    "home": home.path, "maxConcurrentBuilds": 1,
                    "autobuild": ["enabled": true], "completion": ["enabled": true],
                    "format": ["enabled": true], "configuration": ["updateBuildConfiguration": "automatic"],
                    "import": [
                        "maven": ["enabled": true, "offline": ["enabled": offline]],
                        "gradle": ["enabled": true, "arguments": ["--max-workers=2"]],
                    ],
                    "maven": ["downloadSources": false], "references": ["includeDecompiledSources": false],
                    "signatureHelp": ["enabled": true], "saveActions": ["organizeImports": false],
                ]
            ])
            options = .object([
                "workspaceFolders": .array([.string(protocolRoot.absoluteString)]),
                "triggerFiles": .array(triggerFiles.prefix(100).map { .string(mapping.toServer($0)) }),
                "settings": configuration,
                "extendedClientCapabilities": JSONValue([
                    "classFileContentsSupport": false, "resolveAdditionalTextEditsSupport": true,
                ]),
            ])
        }
        if let isolatedHome {
            try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
            environment["HOME"] = isolatedHome.path
            environment["CFFIXED_USER_HOME"] = isolatedHome.path
            environment["XDG_CONFIG_HOME"] = isolatedHome.appendingPathComponent("config").path
            environment["GRADLE_USER_HOME"] = isolatedHome.appendingPathComponent("gradle").path
        }
        listener = Task { [weak self, connection] in
            for await event in connection.events { await self?.receive(event) }
        }
        do {
            try await connection.start(
                executable: executable, arguments: arguments, directory: protocolRoot, configuration: configuration,
                environment: environment,
                removingEnvironment: language == .java
                    ? [
                        "CLIENT_PORT", "CLIENT_HOST", "CLIENT_IN_PORT", "CLIENT_OUT_PORT", "PIPE_NAME",
                        "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS",
                    ] : [])
            let result = try await connection.request(
                "initialize",
                params: .object([
                    "processId": .number(Double(getpid())),
                    "clientInfo": JSONValue(["name": "HyCode", "version": "0.1.0"]),
                    "rootUri": .string(protocolRoot.absoluteString),
                    "workspaceFolders": JSONValue([
                        ["uri": protocolRoot.absoluteString, "name": root.lastPathComponent]
                    ]),
                    "capabilities": Self.clientCapabilities, "initializationOptions": options,
                ]), timeout: 90)
            capabilities = result["capabilities"]
            if let encoding = capabilities["positionEncoding"].string, encoding != "utf-16" {
                throw LanguageServiceFailure("服务使用不支持的位置编码：" + encoding)
            }
            let sync = capabilities["textDocumentSync"]["change"].int ?? capabilities["textDocumentSync"].int
            guard sync == nil || sync == 2 else { throw LanguageServiceFailure("服务不支持增量文档同步") }
            try Task.checkCancellation()
            guard !stopped else { throw CancellationError() }
            try await connection.notify("initialized", params: JSONValue([:]))
            try await connection.notify(
                "workspace/didChangeConfiguration", params: .object(["settings": configuration]))
            if language == .java {
                for _ in 0..<1800 {
                    try Task.checkCancellation()
                    guard !stopped else { throw CancellationError() }
                    if projectReady { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard projectReady else { throw LanguageServiceFailure("Java 项目导入未能在 180 秒内就绪") }
            }
        } catch {
            await stop()
            throw error
        }
    }
    public static let clientCapabilities = JSONValue([
        "general": ["positionEncodings": ["utf-16"]],
        "workspace": ["configuration": true, "workspaceFolders": true, "applyEdit": false],
        "textDocument": [
            "synchronization": ["didSave": true],
            "publishDiagnostics": ["versionSupport": true, "relatedInformation": true, "dataSupport": true],
            "hover": ["contentFormat": ["markdown", "plaintext"]], "definition": ["linkSupport": true],
            "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
            "diagnostic": ["dynamicRegistration": false, "relatedDocumentSupport": true],
            "completion": [
                "completionItem": [
                    "snippetSupport": true, "documentationFormat": ["markdown", "plaintext"],
                    "resolveSupport": ["properties": ["additionalTextEdits", "textEdit", "documentation"]],
                ]
            ],
            "codeAction": [
                "codeActionLiteralSupport": [
                    "codeActionKind": ["valueSet": ["quickfix", "source.organizeImports", "refactor"]]
                ], "resolveSupport": ["properties": ["edit"]],
            ],
        ],
        "experimental": ["workspaceTrust": true],
    ])
    private func receive(_ event: JSONValue) {
        guard !stopped else { return }
        if event["method"].string == "language/status", event["params"]["type"].string == "ServiceReady" {
            projectReady = true
        }
        emitter.yield(uris?.project(event, outgoing: false) ?? event)
    }
    public func open(uri: String, text: String, version: Int) async throws {
        guard !stopped, text.utf8.count <= 1_048_576 else { throw LanguageServiceFailure("语义文档超过 1 MiB 或服务已停止") }
        if versions[uri] != nil { await close(uri: uri) }
        try await connection.notify(
            "textDocument/didOpen",
            params: JSONValue([
                "textDocument": [
                    "uri": uris?.toServer(uri) ?? uri, "languageId": language.rawValue, "version": version,
                    "text": text,
                ]
            ]))
        versions[uri] = version
        sessions[uri] = UUID()
    }
    public func change(uri: String, range: LSPRange, text: String, version: Int) async throws {
        guard !stopped, let previous = versions[uri], version > previous else {
            throw LanguageServiceFailure("文档未同步或修订过期")
        }
        try await connection.notify(
            "textDocument/didChange",
            params: JSONValue([
                "textDocument": ["uri": uris?.toServer(uri) ?? uri, "version": version],
                "contentChanges": [["range": range.json, "text": text]],
            ]))
        versions[uri] = version
    }
    public func close(uri: String) async {
        versions[uri] = nil
        sessions[uri] = nil
        try? await connection.notify(
            "textDocument/didClose", params: JSONValue(["textDocument": ["uri": uris?.toServer(uri) ?? uri]]))
    }
    public func saved(uri: String) async {
        try? await connection.notify(
            "textDocument/didSave", params: JSONValue(["textDocument": ["uri": uris?.toServer(uri) ?? uri]]))
    }
    public func diagnose(uri: String) async throws {
        guard capabilities["diagnosticProvider"] != .null, let version = versions[uri], let session = sessions[uri]
        else { return }
        let result = try await connection.request(
            "textDocument/diagnostic", params: JSONValue(["textDocument": ["uri": uris?.toServer(uri) ?? uri]]),
            timeout: 30)
        guard versions[uri] == version, sessions[uri] == session, !stopped else { throw CancellationError() }
        if result["kind"].string == "full" {
            emitter.yield(
                .object([
                    "method": .string("textDocument/publishDiagnostics"),
                    "params": .object([
                        "uri": .string(uri), "version": .number(Double(version)), "diagnostics": result["items"],
                    ]),
                ]))
        }
    }
    public func request(_ method: String, uri: String, position: LSPPosition?, parameters: [String: JSONValue] = [:])
        async throws -> JSONValue
    {
        guard !stopped, versions[uri] != nil else { throw LanguageServiceFailure("文档尚未同步") }
        // JDT's organize command returns a WorkspaceEdit when applyEdit is
        // false. Resolve only our fixed, current-document action; never accept
        // a server supplied arbitrary command or project/directory argument.
        if language == .java, method == "codeAction/resolve",
            parameters["data"]?["hycodeOrganizeJavaImports"] == .bool(true)
        {
            let edit = try await connection.request(
                "workspace/executeCommand",
                params: JSONValue([
                    "command": "java.edit.organizeImports", "arguments": [uris?.toServer(uri) ?? uri],
                ]))
            var action = parameters
            action["edit"] = uris?.project(edit, outgoing: false) ?? edit
            return .object(action)
        }
        if method == "completionItem/resolve" || method == "codeAction/resolve" {
            let value = try await connection.request(
                method, params: uris?.project(.object(parameters), outgoing: true) ?? .object(parameters))
            return uris?.project(value, outgoing: false) ?? value
        }
        var params = parameters
        params["textDocument"] = JSONValue(["uri": uris?.toServer(uri) ?? uri])
        if let position { params["position"] = position.json }
        if method == "textDocument/references" { params["context"] = JSONValue(["includeDeclaration": true]) }
        if method == "textDocument/formatting" { params["options"] = JSONValue(["tabSize": 4, "insertSpaces": true]) }
        let value = try await connection.request(
            method, params: uris?.project(.object(params), outgoing: true) ?? .object(params), timeout: 30)
        if language == .java, method == "textDocument/codeAction" {
            return .array(
                value.array.map { action in
                    guard action["edit"] == .null, action["data"] == .null,
                        action["command"].string == "java.edit.organizeImports"
                            || action["command"]["command"].string == "java.edit.organizeImports",
                        case .object(var fields) = action
                    else { return uris?.project(action, outgoing: false) ?? action }
                    fields["data"] = JSONValue(["hycodeOrganizeJavaImports": true])
                    return .object(fields)
                })
        }
        return uris?.project(value, outgoing: false) ?? value
    }
    public func filesChanged(_ changes: [(String, Int)]) async {
        try? await connection.notify(
            "workspace/didChangeWatchedFiles",
            params: JSONValue([
                "changes": changes.prefix(1000).map { ["uri": uris?.toServer($0.0) ?? $0.0, "type": $0.1] }
            ]))
    }
    public func stop() async {
        stopped = true
        versions.removeAll()
        sessions.removeAll()
        listener?.cancel()
        listener = nil
        await connection.stop()
        emitter.finish()
    }
}
