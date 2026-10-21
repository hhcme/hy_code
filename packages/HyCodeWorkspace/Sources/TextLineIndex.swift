import Foundation

public struct TextLineChange: Sendable {
    let window: NSRange
    let fragment: String
    let followingLF: Bool
    public init(source text: NSString, range: NSRange, replacement: String) {
        let a = max(0, range.location - 1)
        let b = min(text.length, NSMaxRange(range) + 1)
        window = NSRange(location: a, length: b - a)
        fragment =
            text.substring(with: NSRange(location: a, length: range.location - a))
            + replacement + text.substring(with: NSRange(location: NSMaxRange(range), length: b - NSMaxRange(range)))
        followingLF = b < text.length && text.character(at: b) == 10
    }
}

/// UTF-16 line starts for the native input projection. Initial indexing happens
/// off the UI thread. Edits scan only the replaced fragment and its neighbors;
/// each block holds up to 512 relative offsets. Small edits rebuild only boundary
/// blocks and shift later block bases, rather than visiting every later line.
public struct TextLineIndex: Sendable {
    private struct Block: Sendable {
        var base: Int
        var firstLine: Int
        var offsets: [Int]
    }
    private var blocks = [Block(base: 0, firstLine: 0, offsets: [0])]
    private var unicodeLineSeparators = true
    var allocatedBlockCount: Int { blocks.count }
    public private(set) var count = 1
    public init() {}
    public init(_ text: String, unicodeLineSeparators: Bool = true) {
        self.unicodeLineSeparators = unicodeLineSeparators
        let starts = [0] + Self.breaks(in: Array(text.utf16), followingLF: false, unicode: unicodeLineSeparators)
        blocks = Self.partition(starts)
        reindex()
    }
    public func line(at offset: Int) -> Int {
        let block = blocks[blockIndex(for: offset, byLine: false)]
        return block.firstLine + max(0, Self.upperBound(block.offsets, offset - block.base) - 1)
    }
    public func start(of line: Int) -> Int {
        let line = min(max(0, line), count - 1)
        let block = blocks[blockIndex(for: line, byLine: true)]
        return block.base + block.offsets[line - block.firstLine]
    }
    public mutating func replace(in text: NSString, range: NSRange, with replacement: String) {
        apply(TextLineChange(source: text, range: range, replacement: replacement))
    }
    public mutating func apply(_ change: TextLineChange) {
        let a = change.window.location
        let b = NSMaxRange(change.window)
        let added = Self.breaks(
            in: Array(change.fragment.utf16), followingLF: change.followingLF, unicode: unicodeLineSeparators
        ).map { a + $0 }
        // Include neighbors so repeated edits cannot accumulate one-entry blocks.
        let lower = max(0, blockIndex(for: a, byLine: false) - 1)
        let upper = min(blocks.count - 1, blockIndex(for: b, byLine: false) + 1)
        let delta = change.fragment.utf16.count - change.window.length
        var before: [Int] = []
        var after: [Int] = []
        for block in blocks[lower...upper] {
            if block.base <= a { before += block.offsets.prefix { block.base + $0 <= a }.map { block.base + $0 } }
            if block.base + (block.offsets.last ?? 0) > b {
                after += block.offsets.drop { block.base + $0 <= b }.map { block.base + $0 + delta }
            }
        }
        if upper + 1 < blocks.count { for i in (upper + 1)..<blocks.count { blocks[i].base += delta } }
        blocks.replaceSubrange(lower...upper, with: Self.partition(before + added + after))
        reindex()
    }
    private func blockIndex(for value: Int, byLine: Bool) -> Int {
        var a = 0
        var b = blocks.count
        while a < b {
            let mid = (a + b) / 2
            if (byLine ? blocks[mid].firstLine : blocks[mid].base) <= value { a = mid + 1 } else { b = mid }
        }
        return max(0, a - 1)
    }
    private mutating func reindex() {
        var line = 0
        for i in blocks.indices {
            blocks[i].firstLine = line
            line += blocks[i].offsets.count
        }
        count = line
    }
    private static func partition(_ starts: [Int]) -> [Block] {
        guard !starts.isEmpty else { return [] }
        let blockCount = (starts.count + 511) / 512
        let size = (starts.count + blockCount - 1) / blockCount
        return stride(from: 0, to: starts.count, by: size).map { i in
            let base = starts[i]
            return Block(base: base, firstLine: 0, offsets: starts[i..<min(i + size, starts.count)].map { $0 - base })
        }
    }
    private static func upperBound(_ offsets: [Int], _ value: Int) -> Int {
        var a = 0
        var b = offsets.count
        while a < b {
            let mid = (a + b) / 2
            if offsets[mid] <= value { a = mid + 1 } else { b = mid }
        }
        return a
    }
    private static func breaks(in units: [UInt16], followingLF: Bool, unicode: Bool) -> [Int] {
        var result: [Int] = []
        for (i, unit) in units.enumerated() {
            if unit == 13 {
                if i + 1 < units.count ? units[i + 1] != 10 : !followingLF { result.append(i + 1) }
            } else if unit == 10 || (unicode && (unit == 0x85 || unit == 0x2028 || unit == 0x2029)) {
                result.append(i + 1)
            }
        }
        return result
    }
}
