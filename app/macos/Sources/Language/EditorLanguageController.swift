import HyCodeWorkspace

/// Language owners share the native editor interaction, never a second buffer.
@MainActor protocol EditorLanguageController: AnyObject, Sendable {
    var semanticRevision: UInt64 { get }
    var editRevision: UInt64 { get }
    var status: String { get }
    var flutter: FlutterWorkspaceController? { get }
    var diagnostics: [String: [LSPDiagnostic]] { get }
    var diagnosticsLimited: Bool { get }
    var locations: [LSPLocation] { get }
    var symbols: [JSONValue] { get }
    var symbolURI: String { get }
    func opened(_ feature: EditorLanguageFeatures, text: String)
    func changed(uri: String, range: LSPRange, text: String, version: Int)
    func closed(uri: String)
    func saved(uri: String)
    func query(
        _ method: String, feature: EditorLanguageFeatures, position: LSPPosition?,
        parameters: [String: JSONValue]
    ) async throws -> JSONValue
    func showLocations(_ result: [LSPLocation], jumpIfSingle: Bool)
    func showSymbols(_ feature: EditorLanguageFeatures)
    func clearLocations()
    func report(_ error: Error)
    func isSynchronized(_ feature: EditorLanguageFeatures, service: WebLanguage.Service?) -> Bool
    func resolveCompletion(_ item: JSONValue, feature: EditorLanguageFeatures) async throws -> JSONValue
    var supportsWorkspaceEdits: Bool { get }
    func previewWorkspaceEdit(_ edit: JSONValue, feature: EditorLanguageFeatures, revision: Int, title: String)
}

extension EditorLanguageController {
    var editRevision: UInt64 { semanticRevision }
    func isSynchronized(_ feature: EditorLanguageFeatures, service: WebLanguage.Service?) -> Bool { false }
    var flutter: FlutterWorkspaceController? { nil }
    func resolveCompletion(_ item: JSONValue, feature: EditorLanguageFeatures) async throws -> JSONValue { item }
    var supportsWorkspaceEdits: Bool { false }
    func previewWorkspaceEdit(_ edit: JSONValue, feature: EditorLanguageFeatures, revision: Int, title: String) {
        report(LanguageServiceFailure("此语言尚未接入工作区编辑预览"))
    }
    func query(_ method: String, feature: EditorLanguageFeatures, position: LSPPosition? = nil) async throws
        -> JSONValue
    {
        try await query(method, feature: feature, position: position, parameters: [:])
    }
}
