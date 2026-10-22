import Foundation

public enum ProblemCategory: Int, CaseIterable, Sendable {
    case error = 1
    case warning = 2
    case suggestion = 3
}
public struct WorkspaceProblem: Sendable, Identifiable {
    public let id: String
    public let path: String
    public let target: LSPLocation
    public let message: String
    public let source: String
    public let category: ProblemCategory
}
public struct WorkspaceProblemGroup: Sendable, Identifiable {
    public let path: String
    public let rows: [WorkspaceProblem]
    public var id: String { path }
}
public struct WorkspaceProblemSnapshot: Sendable {
    public let groups: [WorkspaceProblemGroup]
    public let errors: Int
    public let warnings: Int
    public let suggestions: Int
    public let limited: Bool
    public static let empty = Self(groups: [], errors: 0, warnings: 0, suggestions: 0, limited: false)
    /// Sorting, deduplication and filtering stay outside the rendering thread.
    public static func make(
        _ inputs: [String: [String: [LSPDiagnostic]]], root: URL,
        category: ProblemCategory? = nil, limit: Int = 5_000
    ) throws -> Self {
        let root = root.standardizedFileURL.path
        var rows: [WorkspaceProblem] = []
        var seen = Set<String>()
        for language in inputs.keys.sorted() {
            for (uri, values) in (inputs[language] ?? [:]).sorted(by: { $0.key < $1.key }) {
                try Task.checkCancellation()
                guard let url = URL(string: uri), url.isFileURL, url.host == nil || url.host == "localhost",
                    url.standardizedFileURL.path.hasPrefix(root + "/")
                else { continue }
                let path = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
                for value in values {
                    let category: ProblemCategory =
                        value.severity == 1 ? .error : value.severity == 2 ? .warning : .suggestion
                    let source = String((value.raw["source"].string ?? language).prefix(64))
                    let code = value.code?.string ?? value.code?.int.map(String.init) ?? ""
                    let id =
                        uri
                        + "|\(value.range.start.line):\(value.range.start.character):\(value.range.end.line):\(value.range.end.character)|\(category.rawValue)|"
                        + source + "|" + code + "|" + value.message
                    guard seen.insert(id).inserted else { continue }
                    rows.append(
                        WorkspaceProblem(
                            id: id, path: path, target: LSPLocation(uri: uri, range: value.range),
                            message: String(value.message.prefix(16_384)),
                            source: source + (code.isEmpty ? "" : " · " + code), category: category))
                }
            }
        }
        rows.sort { a, b in
            if a.category != b.category { return a.category.rawValue < b.category.rawValue }
            if a.path != b.path { return a.path < b.path }
            if a.target.range.start.line != b.target.range.start.line {
                return a.target.range.start.line < b.target.range.start.line
            }
            if a.target.range.start.character != b.target.range.start.character {
                return a.target.range.start.character < b.target.range.start.character
            }
            return a.id < b.id
        }
        let limited = rows.count > limit
        rows = Array(rows.prefix(max(0, limit)))
        let errors = rows.filter { $0.category == .error }.count
        let warnings = rows.filter { $0.category == .warning }.count
        let suggestions = rows.count - errors - warnings
        let grouped = Dictionary(grouping: rows.filter { category == nil || $0.category == category }, by: \.path)
        let groups = grouped.keys.sorted().map { WorkspaceProblemGroup(path: $0, rows: grouped[$0] ?? []) }
        return Self(groups: groups, errors: errors, warnings: warnings, suggestions: suggestions, limited: limited)
    }
}
