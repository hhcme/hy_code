import CHyCodeCore
import Foundation

/// Disposable immutable syntax projection, independent of disk-save queues.
/// One actor per native editor bounds in-flight parser work. Never owns a text
/// document, file descriptor, semantic service, undo or writable text state.
public actor SyntaxFragmentWorker {
    public init() {}
    public func highlight(text: String, path: String, start: Int) throws -> SyntaxHighlight {
        try Task.checkCancellation()
        guard start >= 0, text.utf16.count <= 65_536 else {
            throw WorkspaceFailure(code: "invalid_range", message: "高亮片段过大")
        }
        let source = Array(text.utf8)
        let name = Array(path.utf8)
        let result = source.withUnsafeBufferPointer { source in
            name.withUnsafeBufferPointer { name in
                hycode_syntax_fragment(source.baseAddress, source.count, name.baseAddress, name.count, start)
            }
        }
        defer {
            hycode_buffer_free(result.value)
            hycode_buffer_free(result.error)
        }
        try Task.checkCancellation()
        if let error = result.error.data, result.error.len > 0 {
            throw try JSONDecoder().decode(WorkspaceFailure.self, from: Data(bytes: error, count: result.error.len))
        }
        guard let bytes = result.value.data else {
            throw WorkspaceFailure(code: "syntax_unavailable", message: "高亮响应为空")
        }
        return try JSONDecoder().decode(SyntaxHighlight.self, from: Data(bytes: bytes, count: result.value.len))
    }
}
