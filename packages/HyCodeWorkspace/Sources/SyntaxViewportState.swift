import Foundation

/// Main-actor-owned scheduling and coverage metadata; contains no source text.
/// Scroll events join the existing worker instead of cancelling its result.
public struct SyntaxViewportState {
    public static let maximumWindow = 65_536
    public static let maximumCachedWindows = 8
    public private(set) var worker: UUID?
    private var windows: [NSRange] = []

    public init() {}

    public mutating func beginUpdates() -> UUID? {
        guard worker == nil else { return nil }
        let ticket = UUID()
        worker = ticket
        return ticket
    }
    public func accepts(_ ticket: UUID) -> Bool { worker == ticket }
    public mutating func finish(_ ticket: UUID) {
        if accepts(ticket) { worker = nil }
    }
    public mutating func cancel() { worker = nil }
    public mutating func reset() -> [NSRange] {
        cancel()
        let removed = windows
        windows.removeAll()
        return removed
    }

    public mutating func covers(_ visible: NSRange) -> Bool {
        guard valid(visible) else { return false }
        // Touch intersecting windows for LRU eviction, preserving capture colors.
        let touched = windows.filter { NSIntersectionRange($0, visible).length > 0 }
        windows.removeAll { NSIntersectionRange($0, visible).length > 0 }
        windows.append(contentsOf: touched)
        return subtract(visible, coveredBy: windows).isEmpty
    }

    /// A failed old viewport must not consume the final scroll event. Retry only
    /// a changed, still-unpainted viewport, never spin on the same failed range.
    public mutating func needsUpdate(after failed: NSRange, latest: NSRange) -> Bool {
        valid(latest) && latest != failed && !covers(latest)
    }

    /// Returns only evicted parts that no retained window still covers. Clearing
    /// a whole overlapping eviction would erase freshly painted neighboring text.
    public mutating func record(_ range: NSRange) -> [NSRange] {
        guard valid(range), range.length <= Self.maximumWindow else { return [] }
        windows.removeAll { $0.location >= range.location && NSMaxRange($0) <= NSMaxRange(range) }
        windows.append(range)
        var removed: [NSRange] = []
        while windows.count > Self.maximumCachedWindows {
            let evicted = windows.removeFirst()
            removed.append(contentsOf: subtract(evicted, coveredBy: windows))
        }
        return removed
    }

    /// One viewport of read-ahead on both sides, capped at 4K UTF-16 per side.
    /// Align to Unicode scalar boundaries without copying/scanning the document.
    public static func requestRange(for visible: NSRange, source: NSString) -> NSRange? {
        guard visible.location >= 0, visible.length > 0, visible.location <= source.length,
            visible.length <= source.length - visible.location, visible.length <= maximumWindow
        else { return nil }
        let margin = min(4_096, max(1_024, visible.length), (maximumWindow - visible.length) / 2)
        var start = max(0, visible.location - margin)
        var end = NSMaxRange(visible) + min(margin, source.length - NSMaxRange(visible))
        if start < source.length && isLowSurrogate(source.character(at: start)) { start += 1 }
        if end < source.length && isLowSurrogate(source.character(at: end)) { end -= 1 }
        guard start <= visible.location, end >= NSMaxRange(visible) else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool { unit >= 0xdc00 && unit <= 0xdfff }
    private func valid(_ range: NSRange) -> Bool {
        range.location >= 0 && range.length > 0 && range.location <= Int.max - range.length
    }
    private func subtract(_ range: NSRange, coveredBy coverage: [NSRange]) -> [NSRange] {
        var pieces = [range]
        for cover in coverage {
            pieces = pieces.flatMap { part -> [NSRange] in
                let intersection = NSIntersectionRange(part, cover)
                guard intersection.length > 0 else { return [part] }
                var rest: [NSRange] = []
                if part.location < intersection.location {
                    rest.append(NSRange(location: part.location, length: intersection.location - part.location))
                }
                if NSMaxRange(part) > NSMaxRange(intersection) {
                    rest.append(
                        NSRange(location: NSMaxRange(intersection), length: NSMaxRange(part) - NSMaxRange(intersection))
                    )
                }
                return rest
            }
        }
        return pieces
    }
}
