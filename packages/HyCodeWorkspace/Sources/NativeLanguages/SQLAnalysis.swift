import CHyCodeCore
import Foundation

public enum SQLDialect: String, CaseIterable, Codable, Sendable {
    case generic, postgresql, mysql, sqlite, mssql, duckdb, bigquery, snowflake, ansi
    public var identifier: UInt32 { UInt32(Self.allCases.firstIndex(of: self)!) }
    public var title: String {
        switch self {
        case .generic: "通用 SQL"
        case .postgresql: "PostgreSQL"
        case .mysql: "MySQL"
        case .sqlite: "SQLite"
        case .mssql: "SQL Server"
        case .duckdb: "DuckDB"
        case .bigquery: "BigQuery"
        case .snowflake: "Snowflake"
        case .ansi: "ANSI SQL"
        }
    }
}
public struct SQLProjection: Decodable, Sendable {
    public struct Column: Decodable, Sendable {
        public let name: String
        public let quoted: Bool
        public let detail: String
        public let range: LSPRange
    }
    public struct Table: Decodable, Sendable {
        public let name: String
        public let quoted: Bool
        public let range: LSPRange
        public let columns: [Column]
    }
    public struct Relation: Decodable, Sendable {
        public let name: String
        public let quoted: Bool
    }
    public struct Identifier: Decodable, Sendable {
        public let name: String
        public let quoted: Bool
        public let role: String
        public let tables: [Relation]
        public let range: LSPRange
    }
    public let diagnostics: [LSPDiagnostic]
    public let tables: [Table]
    public let identifiers: [Identifier]
    public let formatted: String?
}
public enum SQLAnalyzer {
    /// Background synchronous projection; no documents, I/O or database access.
    public static func analyze(_ text: String, dialect: SQLDialect, formatting: Bool = false) throws -> SQLProjection {
        try Task.checkCancellation()
        guard text.utf8.count <= 256 * 1024 else { throw LanguageServiceFailure("SQL 离线工具限 256 KiB") }
        let bytes = Array(text.utf8)
        let result = bytes.withUnsafeBufferPointer {
            hycode_sql_analyze($0.baseAddress, $0.count, dialect.identifier, formatting)
        }
        defer {
            hycode_buffer_free(result.value)
            hycode_buffer_free(result.error)
        }
        if let error = result.error.data, result.error.len > 0 {
            throw try JSONDecoder().decode(WorkspaceFailure.self, from: Data(bytes: error, count: result.error.len))
        }
        guard let bytes = result.value.data else { throw LanguageServiceFailure("SQL 分析响应为空") }
        let projection = try JSONDecoder().decode(SQLProjection.self, from: Data(bytes: bytes, count: result.value.len))
        try Task.checkCancellation()
        return projection
    }
}
