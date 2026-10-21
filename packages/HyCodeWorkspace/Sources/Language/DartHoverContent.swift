import Foundation

/// Bounded presentation data, independent of AppKit. Dart currently wraps its
/// signature in a Markdown fence even for some plaintext hover responses.
public struct DartHoverContent: Sendable, Equatable {
    public let signature: String
    public let declaration: String
    public let type: String
    public let documentation: String
    public var isEmpty: Bool { signature.isEmpty && declaration.isEmpty && type.isEmpty && documentation.isEmpty }

    public init(contents: JSONValue) {
        func flatten(_ value: JSONValue, depth: Int = 0) -> String {
            guard depth < 8 else { return "" }
            if let text = value.string { return String(text.prefix(12_000)) }
            if let text = value["value"].string {
                if value["language"].string != nil { return "```dart\n" + String(text.prefix(4_000)) + "\n```" }
                return String(text.prefix(12_000))
            }
            return String(
                value.array.prefix(16).map { flatten($0, depth: depth + 1) }.joined(separator: "\n\n").prefix(12_000))
        }
        var body = flatten(contents).replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var signature = ""
        if body.hasPrefix("```"), let firstBreak = body.firstIndex(of: "\n"),
            let close = body.range(of: "\n```", range: body.index(after: firstBreak)..<body.endIndex)
        {
            signature = String(body[body.index(after: firstBreak)..<close.lowerBound].prefix(4_000))
            body = String(body[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var declaration = ""
        var type = ""
        var docs: [String] = []
        var metadata = true
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if metadata && trimmed.hasPrefix("Declared ") {
                declaration = String(trimmed.prefix(2_000))
                continue
            }
            if metadata && trimmed.hasPrefix("Type: ") {
                type = String(trimmed.dropFirst(6).prefix(2_000))
                continue
            }
            if trimmed == "---" {
                metadata = false
                continue
            }
            if trimmed.hasPrefix("```") { continue }
            if !trimmed.isEmpty { metadata = false }
            docs.append(line)
        }
        self.signature = signature
        self.declaration = declaration
        self.type = type
        documentation = String(
            docs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
    }
}

public enum DartHoverTarget {
    /// Inspect at most 512 UTF-16 units on either side, never copy a document
    /// or treat whitespace/the nearest line as a symbol hit.
    public static func range(at offset: Int, in source: NSString) -> NSRange? {
        guard offset >= 0, offset < source.length else { return nil }
        func scalar(at index: Int) -> Unicode.Scalar? {
            let unit = source.character(at: index)
            if (0xd800...0xdbff).contains(unit), index + 1 < source.length {
                let low = source.character(at: index + 1)
                guard (0xdc00...0xdfff).contains(low) else { return nil }
                return Unicode.Scalar(0x10000 + (UInt32(unit) - 0xd800) * 1024 + UInt32(low) - 0xdc00)
            }
            if (0xdc00...0xdfff).contains(unit), index > 0 {
                let high = source.character(at: index - 1)
                guard (0xd800...0xdbff).contains(high) else { return nil }
                return Unicode.Scalar(0x10000 + (UInt32(high) - 0xd800) * 1024 + UInt32(unit) - 0xdc00)
            }
            return Unicode.Scalar(unit)
        }
        func member(_ index: Int) -> Bool {
            guard let value = scalar(at: index) else { return false }
            return value == "_" || value == "$" || CharacterSet.alphanumerics.contains(value)
                || CharacterSet.nonBaseCharacters.contains(value)
        }
        guard member(offset) else { return nil }
        var start = offset
        var end = offset + 1
        while start > 0 && member(start - 1) && offset - start < 512 { start -= 1 }
        while end < source.length && member(end) && end - start <= 512 { end += 1 }
        guard end - start <= 512, start == 0 || !member(start - 1),
            let first = scalar(at: start), first == "_" || first == "$" || CharacterSet.letters.contains(first)
        else { return nil }
        return NSRange(location: start, length: end - start)
    }
}
