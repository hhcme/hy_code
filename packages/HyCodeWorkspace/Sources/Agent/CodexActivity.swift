import Foundation

/// A bounded, persisted projection of public app-server tool metadata. It does
/// not interpret commands, read files, or grant any execution capability.
public struct CodexCommandAction: Codable, Equatable, Sendable {
    public var kind: String
    public var path: String?
    public var query: String?
    public var name: String?
    public init(kind: String, path: String? = nil, query: String? = nil, name: String? = nil) {
        self.kind = kind
        self.path = path
        self.query = query
        self.name = name
    }
    var payloadBytes: Int {
        kind.utf8.count + (path?.utf8.count ?? 0) + (query?.utf8.count ?? 0) + (name?.utf8.count ?? 0)
    }
}

public struct CodexFileChange: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public let kind: String
    public let diff: String
    public let added: Int
    public let removed: Int
    public var id: String { path }
    public init(path: String, kind: String = "update", diff: String) {
        self.path = path
        self.kind = kind
        self.diff = diff
        let statistics = CodexDiffStatistics(diff)
        added = statistics.added
        removed = statistics.removed
    }
    private enum CodingKeys: String, CodingKey { case path, kind, diff }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try values.decode(String.self, forKey: .path), kind: try values.decode(String.self, forKey: .kind),
            diff: try values.decode(String.self, forKey: .diff))
    }
    var payloadBytes: Int { path.utf8.count + kind.utf8.count + diff.utf8.count }
}

public struct CodexActivity: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case command, files, turnDiff, turn }
    public var kind: Kind
    public var status: String?
    public var command: String?
    public var actions: [CodexCommandAction] = []
    public var files: [CodexFileChange] = []
    public var durationMs: Int?
    public var exitCode: Int?
    public init(kind: Kind) { self.kind = kind }
    var payloadBytes: Int {
        // Accepted output must remain saveable when inProgress becomes a
        // longer terminal status. Reserve the same 16 bytes for known states.
        (status.map { max(16, $0.utf8.count) } ?? 0) + (command?.utf8.count ?? 0)
            + actions.reduce(0) { $0 + $1.payloadBytes } + files.reduce(0) { $0 + $1.payloadBytes }
    }
}

/// Counts changed lines only inside unified-diff hunks; file headers and hunk
/// coordinates are never counted as content. Binary/rename-only diffs yield 0.
public struct CodexDiffStatistics: Equatable, Sendable {
    public private(set) var added = 0
    public private(set) var removed = 0
    public init(_ diff: String) {
        var oldRemaining = 0
        var newRemaining = 0
        func count(_ range: Substring) -> Int? {
            let values = range.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
            guard values.count <= 2, let start = values.first.flatMap({ Int($0) }), start >= 0 else { return nil }
            guard values.count == 2 else { return 1 }
            return Int(values[1]).flatMap { $0 >= 0 ? $0 : nil }
        }
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                oldRemaining = 0
                newRemaining = 0
            }
            if line.hasPrefix("@@ ") {
                let ranges = line.split(separator: " ")
                oldRemaining = ranges.count >= 4 && ranges[1].hasPrefix("-") ? count(ranges[1]) ?? 0 : 0
                newRemaining = ranges.count >= 4 && ranges[2].hasPrefix("+") ? count(ranges[2]) ?? 0 : 0
                continue
            }
            guard oldRemaining > 0 || newRemaining > 0 else { continue }
            if line.hasPrefix("+"), newRemaining > 0 {
                added += 1
                newRemaining -= 1
            } else if line.hasPrefix("-"), oldRemaining > 0 {
                removed += 1
                oldRemaining -= 1
            } else if line.hasPrefix(" ") {
                oldRemaining = max(0, oldRemaining - 1)
                newRemaining = max(0, newRemaining - 1)
            }
        }
    }
}

public struct CodexParsedDiff: Equatable, Sendable {
    public let files: [CodexFileChange]
    public let fileCount: Int
    public var limited: Bool { fileCount > files.count }
}

public enum CodexUnifiedDiff {
    /// Parsing is restricted to captured protocol text. Paths are display data,
    /// never filesystem authority. Quoted paths remain quoted when ambiguous.
    public static func files(_ text: String) -> [CodexFileChange] {
        parse(text).files
    }
    public static func parse(_ text: String) -> CodexParsedDiff {
        var result: [CodexFileChange] = []
        var fileCount = 0
        var lines: [String] = []
        var path: String?
        var previous: String?
        var kind = "update"
        var hunk = false
        func filePath(_ raw: Substring) -> String? {
            let value = String(raw.split(separator: "\t", maxSplits: 1).first ?? raw)
            guard value != "/dev/null", !value.isEmpty else { return nil }
            return value.hasPrefix("a/") || value.hasPrefix("b/") ? String(value.dropFirst(2)) : value
        }
        func flush() {
            if let name = path ?? previous, !name.isEmpty {
                fileCount += 1
                if result.count < 256 {
                    result.append(CodexFileChange(path: name, kind: kind, diff: lines.joined(separator: "\n")))
                }
            }
            lines.removeAll(keepingCapacity: true)
            path = nil
            previous = nil
            kind = "update"
            hunk = false
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") {
                flush()
                if let range = line.range(of: " b/") { path = String(line[range.upperBound...]) }
            }
            lines.append(line)
            if line.hasPrefix("@@ ") { hunk = true }
            if !hunk {
                if line.hasPrefix("--- ") {
                    previous = filePath(line.dropFirst(4))
                    if previous == nil { kind = "add" }
                }
                if line.hasPrefix("+++ ") {
                    path = filePath(line.dropFirst(4))
                    if path == nil { kind = "delete" }
                }
                if line.hasPrefix("rename to ") { path = String(line.dropFirst(10)) }
            }
        }
        flush()
        return CodexParsedDiff(files: result, fileCount: fileCount)
    }
}

public struct CodexTokenUsage: Codable, Equatable, Sendable {
    public var lastRequestTokens: Int
    public var modelContextWindow: Int?
    public init(lastRequestTokens: Int, modelContextWindow: Int?) {
        self.lastRequestTokens = lastRequestTokens
        self.modelContextWindow = modelContextWindow
    }
}
