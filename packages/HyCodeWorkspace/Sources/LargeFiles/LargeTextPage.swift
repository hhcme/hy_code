import Foundation

/// Original-encoding byte positions, excluding BOM. Numbers and find actions
/// in a native page are deliberately local, never invented global line numbers.
public struct LargeTextPage: Decodable, Sendable {
    public let text: String
    public var start: UInt64
    public var end: UInt64
    public var totalBytes: UInt64
    public let encoding: String
    public let hasBOM: Bool
    public let lineEnding: String
    public var canUndo: Bool
    public var canRedo: Bool
    public var remainingBytes: Int
    public var remainingPieces: Int
    enum CodingKeys: String, CodingKey {
        case text, start, end, encoding
        case totalBytes = "total_bytes"
        case hasBOM = "has_bom"
        case lineEnding = "line_ending"
        case canUndo = "can_undo"
        case canRedo = "can_redo"
        case remainingBytes = "remaining_bytes"
        case remainingPieces = "remaining_pieces"
    }
    public static let windowBytes: UInt64 = 65_536
    public var previous: UInt64 { start > Self.windowBytes ? start - Self.windowBytes : 0 }
    public var last: UInt64 { totalBytes > Self.windowBytes ? totalBytes - Self.windowBytes : 0 }
    public var fraction: Double { totalBytes > 0 ? Double(start) / Double(totalBytes) : 0 }
    public func position(fraction: Double) -> UInt64 {
        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return min(last, UInt64(Double(totalBytes) * value))
    }
    public func encodedCount(_ text: String) -> Int { encoding == "utf8" ? text.utf8.count : text.utf16.count * 2 }
}
public struct LargeTextStatus: Decodable, Sendable {
    public let totalBytes: UInt64
    public let canUndo: Bool
    public let canRedo: Bool
    public let remainingBytes: Int
    public let remainingPieces: Int
    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
        case canUndo = "can_undo"
        case canRedo = "can_redo"
        case remainingBytes = "remaining_bytes"
        case remainingPieces = "remaining_pieces"
    }
}
