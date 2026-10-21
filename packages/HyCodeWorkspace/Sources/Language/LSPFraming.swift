import Foundation

/// Bounded incremental byte framing; headers and bodies may split anywhere,
/// including within a UTF-8 scalar. Never decode before the complete body arrives.
public struct LSPFraming: Sendable {
    public static let maximumBody = 8 * 1024 * 1024
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [JSONValue] {
        buffer.append(data)
        guard buffer.count <= Self.maximumBody + 65_536 else { throw LanguageServiceFailure("语言服务消息过大") }
        var messages: [JSONValue] = []
        while let split = buffer.range(of: Data([13, 10, 13, 10])) {
            let headerSize = buffer.distance(from: buffer.startIndex, to: split.lowerBound)
            guard headerSize <= 8_192, let header = String(data: buffer.prefix(headerSize), encoding: .ascii) else {
                throw LanguageServiceFailure("语言服务消息头无效")
            }
            let lengths = header.components(separatedBy: "\r\n").compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            guard lengths.count == 1, let count = lengths.first, count > 0, count <= Self.maximumBody else {
                throw LanguageServiceFailure("语言服务 Content-Length 无效")
            }
            let start = headerSize + 4
            guard buffer.count >= start + count else { break }
            let body = Data(buffer.dropFirst(start).prefix(count))
            messages.append(try JSONDecoder().decode(JSONValue.self, from: body))
            buffer = Data(buffer.dropFirst(start + count))
        }
        if buffer.range(of: Data([13, 10, 13, 10])) == nil && buffer.count > 8_192 {
            throw LanguageServiceFailure("语言服务消息头过大")
        }
        return messages
    }
    public static func encode(_ value: JSONValue) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maximumBody else { throw LanguageServiceFailure("语言服务请求过大") }
        var data = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}
