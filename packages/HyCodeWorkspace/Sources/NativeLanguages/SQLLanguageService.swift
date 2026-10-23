import Foundation

/// Offline SQL session/DDL projection. Text here is a bounded protocol overlay;
/// the editor/Rust document remains the sole writable document and undo owner.
public actor SQLLanguageService: CodeLanguageService {
    public nonisolated let events: AsyncStream<JSONValue>
    private let emitter: AsyncStream<JSONValue>.Continuation
    private struct Document: Sendable {
        let text: String
        let version: Int
        let projection: SQLProjection
    }
    private var documents: [String: Document] = [:]
    private var bytes = 0
    private var stopped = false
    private let dialect: SQLDialect
    public init(dialect: SQLDialect) {
        self.dialect = dialect
        let stream = AsyncStream<JSONValue>.makeStream(bufferingPolicy: .bufferingNewest(512))
        events = stream.stream
        emitter = stream.continuation
    }
    public func open(uri: String, text: String, version: Int) throws {
        guard !stopped, documents[uri] != nil || documents.count < 2000,
            bytes - (documents[uri]?.text.utf8.count ?? 0) + text.utf8.count <= 32 * 1024 * 1024
        else { throw LanguageServiceFailure("SQL 会话数量或总量超过限制") }
        let value = try SQLAnalyzer.analyze(text, dialect: dialect)
        bytes -= documents[uri]?.text.utf8.count ?? 0
        bytes += text.utf8.count
        documents[uri] = Document(text: text, version: version, projection: value)
        publish(uri: uri, version: version, diagnostics: value.diagnostics)
    }
    public func change(uri: String, range: LSPRange, text: String, version: Int) throws {
        guard let current = documents[uri], version > current.version else { throw LanguageServiceFailure("SQL 修订过期") }
        let updated = try LSPTextEdits.apply([LSPTextEdit(range: range, newText: text)], to: current.text)
        try open(uri: uri, text: updated, version: version)
    }
    public func close(uri: String) {
        bytes -= documents.removeValue(forKey: uri)?.text.utf8.count ?? 0
        publish(uri: uri, version: nil, diagnostics: [])
    }
    private func publish(uri: String, version: Int?, diagnostics: [LSPDiagnostic]) {
        var params: [String: JSONValue] = ["uri": .string(uri), "diagnostics": .array(diagnostics.map(\.raw))]
        if let version { params["version"] = .number(Double(version)) }
        emitter.yield(.object(["method": .string("textDocument/publishDiagnostics"), "params": .object(params)]))
    }
    public func saved(uri: String) {}
    public func filesChanged(_ changes: [(String, Int)]) {}
    public func diagnose(uri: String) throws {
        guard let doc = documents[uri] else { return }
        publish(uri: uri, version: doc.version, diagnostics: doc.projection.diagnostics)
    }
    private struct Target {
        let name: String
        let quoted: Bool
        let table: String?
        let detail: String
        let location: LSPLocation
    }
    private func targets() -> [Target] {
        var result: [Target] = []
        for (uri, doc) in documents.sorted(by: { $0.key < $1.key }) {
            for table in doc.projection.tables {
                // The first schema projection stores one quote flag per name.
                // Do not fabricate insertion/binding for mixed quoted parts.
                if table.quoted && table.name.contains(".") { continue }
                result.append(
                    Target(
                        name: table.name, quoted: table.quoted, table: nil, detail: "TABLE " + table.name,
                        location: LSPLocation(uri: uri, range: table.range)))
                for column in table.columns {
                    result.append(
                        Target(
                            name: column.name, quoted: column.quoted, table: table.name,
                            detail: table.name + "." + column.name + " " + column.detail,
                            location: LSPLocation(uri: uri, range: column.range)))
                }
                if result.count >= 10_000 { return Array(result.prefix(10_000)) }
            }
        }
        return result
    }
    private func tableIndex(_ all: [Target]) -> [String: [Target]] {
        var result: [String: [Target]] = [:]
        for target in all where target.table == nil {
            let full = target.name.lowercased()
            let last = target.name.split(separator: ".").last.map(String.init)?.lowercased() ?? full
            result[full, default: []].append(target)
            if last != full { result[last, default: []].append(target) }
        }
        return result
    }
    private func matches(_ item: SQLProjection.Identifier, _ target: Target, index: [String: [Target]]) -> Bool {
        var bound: [Target] = []
        for relation in item.tables {
            let candidates = (index[relation.name.lowercased()] ?? []).filter { declaration in
                let expected =
                    relation.name.contains(".")
                    ? declaration.name
                    : declaration.name.split(separator: ".").last.map(String.init) ?? declaration.name
                return relation.name == expected
            }
            guard candidates.count == 1 else { return false }
            bound.append(candidates[0])
        }
        guard !bound.isEmpty else { return false }
        if item.role == "table" {
            return target.table == nil && bound.count == 1 && bound[0].location.id == target.location.id
        }
        guard item.role == "column", let table = target.table, bound.contains(where: { $0.name == table }) else {
            return false
        }
        return item.name == target.name
    }
    private func contains(_ range: LSPRange, _ position: LSPPosition) -> Bool {
        (range.start.line < position.line
            || (range.start.line == position.line && range.start.character <= position.character))
            && (range.end.line > position.line
                || (range.end.line == position.line && range.end.character > position.character))
    }
    public func request(_ method: String, uri: String, position: LSPPosition?, parameters: [String: JSONValue]) throws
        -> JSONValue
    {
        try Task.checkCancellation()
        guard !stopped, let doc = documents[uri] else { throw LanguageServiceFailure("SQL 文档未同步") }
        switch method {
        case "textDocument/formatting":
            guard let formatted = try SQLAnalyzer.analyze(doc.text, dialect: dialect, formatting: true).formatted else {
                throw LanguageServiceFailure("请先修复 SQL 语法再格式化")
            }
            let end = LSPPosition.at(doc.text.utf16.count, in: TextLineIndex(doc.text, unicodeLineSeparators: false))
            return JSONValue([
                ["range": LSPRange(start: LSPPosition(line: 0, character: 0), end: end).json, "newText": formatted]
            ])
        case "textDocument/completion":
            var items = [
                "SELECT", "FROM", "WHERE", "JOIN", "LEFT JOIN", "INNER JOIN", "GROUP BY", "ORDER BY", "HAVING", "LIMIT",
                "INSERT INTO", "UPDATE", "DELETE FROM", "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "PRIMARY KEY",
                "FOREIGN KEY", "NOT NULL", "VALUES", "COUNT", "SUM", "AVG", "DISTINCT", "AS", "AND", "OR", "IS NULL",
            ].map { JSONValue(["label": $0, "kind": 14, "detail": dialect.title + " · 离线关键字"]) }
            var seen = Set<String>()
            for target in targets() where seen.insert(target.name + "|" + target.detail).inserted {
                // Quote identifiers according to the selected dialect so names
                // containing spaces/case-sensitive DDL are valid on insertion.
                let name = target.name
                let inserted: String
                if target.quoted {
                    if dialect == .mysql {
                        inserted = "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
                    } else if dialect == .bigquery {
                        inserted =
                            "`"
                            + name.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "`", with: "\\`") + "`"
                    } else if dialect == .mssql {
                        inserted = "[" + name.replacingOccurrences(of: "]", with: "]]") + "]"
                    } else {
                        inserted = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                    }
                } else {
                    inserted = name
                }
                items.append(
                    JSONValue([
                        "label": name, "insertText": inserted, "kind": target.table == nil ? 7 : 5,
                        "detail": target.detail + " · 项目 DDL",
                    ]))
                if items.count >= 1000 { break }
            }
            return .object(["items": .array(items), "isIncomplete": .bool(false)])
        case "completionItem/resolve": return .object(parameters)
        case "textDocument/documentSymbol":
            return .array(
                doc.projection.tables.map { table in
                    .object([
                        "name": .string(table.name), "kind": .number(5), "range": table.range.json,
                        "selectionRange": table.range.json,
                        "children": .array(
                            table.columns.map {
                                .object([
                                    "name": .string($0.name), "detail": .string($0.detail), "kind": .number(8),
                                    "range": $0.range.json, "selectionRange": $0.range.json,
                                ])
                            }),
                    ])
                })
        case "textDocument/hover", "textDocument/definition", "textDocument/typeDefinition", "textDocument/references":
            guard let position, let item = doc.projection.identifiers.first(where: { contains($0.range, position) })
            else { return .null }
            let known = targets()
            let bindings = tableIndex(known)
            let candidates = known.filter { matches(item, $0, index: bindings) }
            guard candidates.count == 1, let target = candidates.first else { return .null }
            if method == "textDocument/hover" {
                return JSONValue([
                    "contents": [
                        "kind": "markdown",
                        "value": "```sql\n" + target.detail + "\n```\n\n项目 DDL · "
                            + (URL(string: target.location.uri)?.lastPathComponent ?? ""),
                    ], "range": item.range.json,
                ])
            }
            if method == "textDocument/references" {
                var locations: [JSONValue] = []
                let all = Dictionary(grouping: known) {
                    ($0.name.split(separator: ".").last.map(String.init) ?? $0.name).lowercased()
                }
                var visited = 0
                for (otherURI, other) in documents.sorted(by: { $0.key < $1.key }) {
                    for occurrence in other.projection.identifiers {
                        visited += 1
                        if visited > 100_000 { return .array(locations) }
                        if visited % 256 == 0 { try Task.checkCancellation() }
                        guard matches(occurrence, target, index: bindings),
                            (all[occurrence.name.lowercased()] ?? []).filter({
                                matches(occurrence, $0, index: bindings)
                            }).count == 1
                        else { continue }
                        locations.append(JSONValue(["uri": otherURI, "range": occurrence.range.json]))
                        if locations.count >= 2000 { return .array(locations) }
                    }
                }
                return .array(locations)
            }
            return JSONValue([["uri": target.location.uri, "range": target.location.range.json]])
        default: return .null
        }
    }
    public func stop() {
        stopped = true
        documents.removeAll()
        bytes = 0
        emitter.finish()
    }
}
