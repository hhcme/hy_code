import CHyCodeCore
import Foundation

public struct TextDocumentContent: Decodable, Sendable {
    public let text: String
    public let encoding: String
    public let hasBOM: Bool
    public let lineEnding: String
    public let byteCount: Int
    public var lineIndex = TextLineIndex()
    public var protocolLineIndex = TextLineIndex()
    enum CodingKeys: String, CodingKey {
        case text, encoding
        case hasBOM = "has_bom"
        case lineEnding = "line_ending"
        case byteCount = "byte_count"
    }
}

/// Single serial owner for a Rust document, its disk baseline and all blocking
/// file coordination. The app retains workspace access until queued calls finish.
public actor NativeTextDocument {
    private final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { hycode_text_free(pointer) }
    }
    private let root: URL
    private let path: String
    private var handle: Handle?
    private var baseline: TextFileIO.Snapshot?
    public init(root: URL, path: String) {
        self.root = root
        self.path = path
    }

    public func open() throws -> TextDocumentContent {
        guard handle == nil else { throw WorkspaceFailure(code: "already_open", message: "文档已经打开") }
        let snapshot = try TextFileIO.read(root: root, path: path)
        var pointer: OpaquePointer?
        let result = snapshot.bytes.withUnsafeBytes { bytes in
            hycode_text_open(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &pointer)
        }
        let data = try consume(result)
        guard let pointer else { throw WorkspaceFailure(code: "empty_document", message: "文本内核未创建文档") }
        let owner = Handle(pointer)
        var content = try JSONDecoder().decode(TextDocumentContent.self, from: data)
        content.lineIndex = TextLineIndex(content.text)
        content.protocolLineIndex = TextLineIndex(content.text, unicodeLineSeparators: false)
        handle = owner
        baseline = snapshot
        return content
    }
    public func replace(expected: UInt64, range: NSRange, text: String) throws {
        guard let handle else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_text_replace(handle.pointer, expected, range.location, range.length, $0.baseAddress, $0.count)
        }
        _ = try consume(result)
    }
    public func save(revision: UInt64, cancellation: DocumentSaveCancellation? = nil) throws {
        guard let handle, let baseline else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        try cancellation?.check()
        let data = try consume(hycode_text_bytes(handle.pointer, revision))
        self.baseline = try TextFileIO.save(
            root: root, path: path, expected: baseline, bytes: data, cancellation: cancellation)
    }
    public func syntax(revision: UInt64, range: NSRange) throws -> SyntaxHighlight {
        try Task.checkCancellation()
        guard let handle else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        let bytes = Array(path.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_text_syntax(handle.pointer, revision, $0.baseAddress, $0.count, range.location, NSMaxRange(range))
        }
        return try JSONDecoder().decode(SyntaxHighlight.self, from: consume(result))
    }
    private func consume(_ result: HyCodeTextResult) throws -> Data {
        defer {
            hycode_buffer_free(result.value)
            hycode_buffer_free(result.error)
        }
        if let bytes = result.error.data, result.error.len > 0 {
            throw try JSONDecoder().decode(WorkspaceFailure.self, from: Data(bytes: bytes, count: result.error.len))
        }
        guard let bytes = result.value.data else { return Data() }
        return Data(bytes: bytes, count: result.value.len)
    }
}
