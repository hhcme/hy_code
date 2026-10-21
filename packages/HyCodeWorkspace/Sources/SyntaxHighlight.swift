import Foundation

public struct SyntaxHighlight: Decodable, Sendable {
    public struct Span: Decodable, Sendable {
        public let start: Int
        public let length: Int
        public let style: String
        public var range: NSRange { NSRange(location: start, length: length) }
    }
    public let language: String
    public let status: String
    public let start: Int
    public let length: Int
    public let spans: [Span]
}
