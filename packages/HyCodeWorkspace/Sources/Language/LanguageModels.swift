import Foundation

public struct LSPPosition: Codable, Sendable, Hashable {
    public let line: Int
    public let character: Int
    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
    public var json: JSONValue { JSONValue(["line": line, "character": character]) }
    public static func at(_ offset: Int, in index: TextLineIndex) -> Self {
        let line = index.line(at: offset)
        return Self(line: line, character: max(0, offset - index.start(of: line)))
    }
    public func offset(in index: TextLineIndex, source: NSString) -> Int? {
        guard line >= 0, line < index.count, character >= 0 else { return nil }
        let start = index.start(of: line)
        var end = line + 1 < index.count ? index.start(of: line + 1) : source.length
        while end > start && [10, 13].contains(source.character(at: end - 1)) { end -= 1 }
        guard character <= end - start else { return nil }
        let result = start + character
        if result < source.length && (0xdc00...0xdfff).contains(source.character(at: result)) { return nil }
        return result
    }
}
public struct LSPRange: Codable, Sendable, Hashable {
    public let start: LSPPosition
    public let end: LSPPosition
    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
    public var json: JSONValue {
        JSONValue([
            "start": ["line": start.line, "character": start.character],
            "end": ["line": end.line, "character": end.character],
        ])
    }
    public func range(in index: TextLineIndex, source: NSString) -> NSRange? {
        guard let a = start.offset(in: index, source: source), let b = end.offset(in: index, source: source), b >= a
        else { return nil }
        return NSRange(location: a, length: b - a)
    }
}
public struct LSPDiagnostic: Decodable, Sendable, Identifiable {
    public let range: LSPRange
    public let severity: Int?
    public let message: String
    public let code: JSONValue?
    /// Preserve opaque provider data for a subsequent codeAction request.
    public let raw: JSONValue
    public init(from decoder: any Decoder) throws {
        raw = try JSONValue(from: decoder)
        range = try raw["range"].decode(LSPRange.self)
        message = try raw["message"].decode(String.self)
        severity = raw["severity"].int
        code = raw["code"] == .null ? nil : raw["code"]
    }
    public var id: String { "\(range.start.line):\(range.start.character):\(message)" }
}
public struct LSPLocation: Codable, Sendable, Identifiable {
    public let uri: String
    public let range: LSPRange
    public var id: String { "\(uri):\(range.start.line):\(range.start.character)" }
    public init(uri: String, range: LSPRange) {
        self.uri = uri
        self.range = range
    }
    public static func locations(_ result: JSONValue) throws -> [Self] {
        let values = result.array.isEmpty && result["uri"].string != nil ? [result] : result.array
        return try values.prefix(2_000).map { value in
            if let uri = value["targetUri"].string {
                return Self(uri: uri, range: try value["targetSelectionRange"].decode(LSPRange.self))
            }
            return try value.decode(Self.self)
        }
    }
}
