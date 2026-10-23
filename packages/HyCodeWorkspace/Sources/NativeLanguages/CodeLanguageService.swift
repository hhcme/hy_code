import Foundation

public protocol CodeLanguageService: Sendable {
    var events: AsyncStream<JSONValue> { get }
    func open(uri: String, text: String, version: Int) async throws
    func change(uri: String, range: LSPRange, text: String, version: Int) async throws
    func close(uri: String) async
    func saved(uri: String) async
    func diagnose(uri: String) async throws
    func request(_ method: String, uri: String, position: LSPPosition?, parameters: [String: JSONValue]) async throws
        -> JSONValue
    func filesChanged(_ changes: [(String, Int)]) async
    func stop() async
}
extension NativeLanguageServer: CodeLanguageService {}
