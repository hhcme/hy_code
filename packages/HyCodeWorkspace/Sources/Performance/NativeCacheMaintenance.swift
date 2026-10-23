import CHyCodeCore
import Foundation

/// Shared compiled-query cache; never owns a document, file or language service.
public actor NativeCacheMaintenance {
    public static let shared = NativeCacheMaintenance()
    public func releaseUnusedSyntaxGrammars(
        protecting path: String? = nil, cancellation: DocumentSaveCancellation? = nil
    ) throws -> Int {
        defer { withExtendedLifetime(cancellation) {} }
        try cancellation?.check()
        let name = Array((path ?? "").utf8)
        let result = name.withUnsafeBufferPointer {
            hycode_syntax_trim_cache($0.baseAddress, $0.count, cancellation?.native)
        }
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
        guard let bytes = result.value.data else {
            throw WorkspaceFailure(code: "cache_unavailable", message: "缓存清理响应为空")
        }
        return try JSONDecoder().decode(Int.self, from: Data(bytes: bytes, count: result.value.len))
    }
}
