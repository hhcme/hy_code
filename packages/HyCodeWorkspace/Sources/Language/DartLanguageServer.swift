import Darwin
import Foundation

public actor DartLanguageServer {
    private let connection: LanguageServerConnection
    public nonisolated let events: AsyncStream<JSONValue>
    public init() {
        let connection = LanguageServerConnection()
        self.connection = connection
        events = connection.events
    }
    public func initialize(root: URL, toolchain: DartToolchain, cache: URL) async throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var config: [String: Any] = ["completeFunctionCalls": false, "enableSnippets": false, "showTodos": true]
        if let flutter = toolchain.flutterSDK { config["flutterSdkPath"] = flutter.path }
        try await connection.start(
            executable: toolchain.dart,
            arguments: [
                toolchain.analysisServer.path, "--lsp", "--client-id=hycode", "--client-version=0.1.0",
                "--suppress-analytics", "--cache=\(cache.path)",
            ],
            directory: root, configuration: JSONValue(config))
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
                            "publishDiagnostics": ["versionSupport": true, "relatedInformation": true],
                            "hover": ["contentFormat": ["markdown", "plaintext"]], "definition": ["linkSupport": true],
                            "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
                            "completion": [
                                "completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext"]]
                            ],
                        ],
                    ],
                    "initializationOptions": [
                        "onlyAnalyzeProjectsWithOpenFiles": false, "suggestFromUnimportedLibraries": false,
                    ],
                ]), timeout: 45)
            if let encoding = response["capabilities"]["positionEncoding"].string, encoding != "utf-16" {
                throw LanguageServiceFailure("分析器返回不支持的位置编码：\(encoding)")
            }
            try await connection.notify("initialized", params: JSONValue([:]))
        } catch {
            await connection.stop()
            throw error
        }
    }
    public func open(uri: String, text: String, version: Int) async throws {
        try await connection.notify(
            "textDocument/didOpen",
            params: JSONValue([
                "textDocument": ["uri": uri, "languageId": "dart", "version": version, "text": text]
            ]))
    }
    public func change(uri: String, range: LSPRange, text: String, version: Int) async throws {
        try await connection.notify(
            "textDocument/didChange",
            params: JSONValue([
                "textDocument": ["uri": uri, "version": version],
                "contentChanges": [["range": range.json, "text": text]],
            ]))
    }
    public func close(uri: String) async {
        try? await connection.notify("textDocument/didClose", params: JSONValue(["textDocument": ["uri": uri]]))
    }
    public func saved(uri: String) async {
        try? await connection.notify("textDocument/didSave", params: JSONValue(["textDocument": ["uri": uri]]))
    }
    public func request(_ method: String, uri: String, position: LSPPosition? = nil) async throws -> JSONValue {
        var params: [String: Any] = ["textDocument": ["uri": uri]]
        if let position { params["position"] = position.json }
        if method == "textDocument/references" { params["context"] = ["includeDeclaration": true] }
        if method == "textDocument/formatting" { params["options"] = ["tabSize": 2, "insertSpaces": true] }
        return try await connection.request(method, params: JSONValue(params))
    }
    public func stop() async {
        await connection.stop()
    }
}
