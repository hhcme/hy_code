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
    public var largePage: LargeTextPage?
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
    private final class LargeHandle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { hycode_large_free(pointer) }
    }
    private var large: LargeHandle?
    private var largeVersion: TextFileIO.Version?
    private var pageStart: UInt64 = 0
    private let root: URL
    private let path: String
    private var handle: Handle?
    private var baseline: TextFileIO.Snapshot?
    private var encoding = "utf8"
    private var hasBOM = false
    public init(root: URL, path: String) {
        self.root = root
        self.path = path
    }

    public func open() throws -> TextDocumentContent {
        try Task.checkCancellation()
        guard handle == nil, large == nil else { throw WorkspaceFailure(code: "already_open", message: "文档已经打开") }
        if try TextFileIO.needsPaging(root: root, path: path) {
            let (owner, version) = try TextFileIO.withLargeFile(root: root, path: path) { fd, version in
                var pointer: OpaquePointer?
                _ = try consume(hycode_large_open(fd, &pointer))
                guard let pointer else { throw WorkspaceFailure(code: "empty_document", message: "大文件内核未创建文档") }
                return (LargeHandle(pointer), version)
            }
            large = owner
            largeVersion = version
            do { return try page(revision: 0, offset: 0) } catch {
                large = nil
                largeVersion = nil
                throw error
            }
        }
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
        encoding = content.encoding
        hasBOM = content.hasBOM
        try Task.checkCancellation()
        return content
    }
    @discardableResult public func replace(expected: UInt64, range: NSRange, text: String) throws -> LargeTextStatus? {
        if let large {
            let bytes = Array(text.utf8)
            let result = bytes.withUnsafeBufferPointer {
                hycode_large_replace(
                    large.pointer, expected, pageStart, range.location, range.length, $0.baseAddress, $0.count)
            }
            return try JSONDecoder().decode(LargeTextStatus.self, from: consume(result))
        }
        guard let handle else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_text_replace(handle.pointer, expected, range.location, range.length, $0.baseAddress, $0.count)
        }
        _ = try consume(result)
        return nil
    }
    /// Only the small document's rebuildable parser/tree. Large documents retain
    /// their current page, source descriptors, pending input and undo history.
    public func trimRebuildableCaches(cancellation: DocumentSaveCancellation? = nil) throws -> Bool {
        defer { withExtendedLifetime(cancellation) {} }
        try cancellation?.check()
        guard let handle else { return false }
        return try JSONDecoder().decode(
            Bool.self, from: consume(hycode_text_trim_cache(handle.pointer, cancellation?.native)))
    }
    public func save(revision: UInt64, cancellation: DocumentSaveCancellation? = nil) throws {
        defer { withExtendedLifetime(cancellation) {} }
        if let large, let version = largeVersion {
            try cancellation?.check()
            largeVersion = try TextFileIO.saveLarge(
                root: root, path: path, expected: version, cancellation: cancellation
            ) { fd in
                _ = try consume(hycode_large_export(large.pointer, revision, fd, cancellation?.native))
            } committed: { fd in
                _ = try consume(hycode_large_saved(large.pointer, revision, fd))
            }
            return
        }
        guard let handle, let baseline else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        try cancellation?.check()
        let data = try consume(hycode_text_bytes(handle.pointer, revision))
        self.baseline = try TextFileIO.save(
            root: root, path: path, expected: baseline, bytes: data, cancellation: cancellation)
    }
    /// Immutable full-buffer projection from the existing Rust owner. Pages are
    /// never exported as a complete file; the FFI rejects stale revisions.
    public func textSnapshot(revision: UInt64) throws -> String {
        try Task.checkCancellation()
        guard large == nil, let handle else {
            throw WorkspaceFailure(code: "not_full_text", message: "分段文档不能作为全文差异输入")
        }
        let bytes = try consume(hycode_text_bytes(handle.pointer, revision))
        let text: String?
        if encoding == "utf16_le" || encoding == "utf16_be" {
            let content = Array(bytes.dropFirst(2))
            let little = encoding == "utf16_le"
            let units = stride(from: 0, to: content.count - 1, by: 2).map { index in
                if little { return UInt16(content[index]) | UInt16(content[index + 1]) << 8 }
                return UInt16(content[index]) << 8 | UInt16(content[index + 1])
            }
            text = String(decoding: units, as: UTF16.self)
        } else {
            // Rust has already validated these UTF-8 bytes. Decoding preserves
            // a literal leading U+FEFF inserted into the body (Foundation's
            // String(data:encoding:) would consume it as another BOM).
            text = String(decoding: hasBOM ? bytes.dropFirst(3) : bytes, as: UTF8.self)
        }
        guard let text else { throw WorkspaceFailure(code: "invalid_text", message: "文本快照无法解码") }
        try Task.checkCancellation()
        return text
    }
    public func syntax(revision: UInt64, range: NSRange) throws -> SyntaxHighlight {
        try Task.checkCancellation()
        if let large {
            let bytes = Array(path.utf8)
            let result = bytes.withUnsafeBufferPointer {
                hycode_large_syntax(
                    large.pointer, revision, $0.baseAddress, $0.count, range.location, NSMaxRange(range))
            }
            return try JSONDecoder().decode(SyntaxHighlight.self, from: consume(result))
        }
        guard let handle else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        let bytes = Array(path.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_text_syntax(handle.pointer, revision, $0.baseAddress, $0.count, range.location, NSMaxRange(range))
        }
        return try JSONDecoder().decode(SyntaxHighlight.self, from: consume(result))
    }
    public func page(revision: UInt64, offset: UInt64, cancellation: DocumentSaveCancellation? = nil) throws
        -> TextDocumentContent
    {
        defer { withExtendedLifetime(cancellation) {} }
        try Task.checkCancellation()
        try cancellation?.check()
        guard let large else { throw WorkspaceFailure(code: "not_large", message: "此文档未使用分段编辑") }
        let value = try JSONDecoder().decode(
            LargeTextPage.self, from: consume(hycode_large_page(large.pointer, revision, offset, cancellation?.native)))
        // Rust has committed its page projection. Returning it must not be
        // cancelled now: the UI must install the matching page before editing.
        return content(value)
    }
    private func content(_ value: LargeTextPage) -> TextDocumentContent {
        pageStart = value.start
        var content = TextDocumentContent(
            text: value.text, encoding: value.encoding, hasBOM: value.hasBOM,
            lineEnding: value.lineEnding, byteCount: value.text.utf8.count)
        content.lineIndex = TextLineIndex(value.text)
        content.largePage = value
        return content
    }
    public func history(revision: UInt64, redo: Bool) throws -> TextDocumentContent {
        guard let large else { throw WorkspaceFailure(code: "not_large", message: "此文档未使用分段编辑") }
        let value = try JSONDecoder().decode(
            LargeTextPage.self, from: consume(hycode_large_history(large.pointer, revision, redo)))
        return content(value)
    }
    public func largeStatus() throws -> LargeTextStatus? {
        guard let large else { return nil }
        return try JSONDecoder().decode(LargeTextStatus.self, from: consume(hycode_large_status(large.pointer)))
    }
    public func find(revision: UInt64, text: String, from: UInt64, cancellation: DocumentSaveCancellation) throws
        -> UInt64?
    {
        try cancellation.check()
        guard let large else { throw WorkspaceFailure(code: "not_large", message: "此文档未使用分段编辑") }
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_large_find(large.pointer, revision, $0.baseAddress, $0.count, from, cancellation.native)
        }
        let value = try JSONDecoder().decode(UInt64?.self, from: consume(result))
        try cancellation.check()
        return value
    }
    private func consume(_ result: HyCodeTextResult) throws -> Data {
        defer {
            hycode_buffer_free(result.value)
            hycode_buffer_free(result.error)
        }
        if let bytes = result.error.data, result.error.len > 0 {
            let error = try JSONDecoder().decode(
                WorkspaceFailure.self, from: Data(bytes: bytes, count: result.error.len))
            if error.code == "cancelled" { throw CancellationError() }
            throw error
        }
        guard let bytes = result.value.data else { return Data() }
        return Data(bytes: bytes, count: result.value.len)
    }
    public func markup(revision: UInt64, markdown: Bool, cancellation: DocumentSaveCancellation? = nil) throws
        -> MarkupPreviewContent
    {
        defer { withExtendedLifetime(cancellation) {} }
        try Task.checkCancellation()
        try cancellation?.check()
        if let large {
            let result = hycode_large_markup(large.pointer, revision, markdown, cancellation?.native)
            let value = try JSONDecoder().decode(MarkupPreviewContent.self, from: consume(result))
            try Task.checkCancellation()
            return value
        }
        guard let handle else { throw WorkspaceFailure(code: "not_open", message: "文档尚未打开") }
        let result = hycode_text_markup_cancellable(handle.pointer, revision, markdown, cancellation?.native)
        let value = try JSONDecoder().decode(MarkupPreviewContent.self, from: consume(result))
        try Task.checkCancellation()
        return value
    }
}
