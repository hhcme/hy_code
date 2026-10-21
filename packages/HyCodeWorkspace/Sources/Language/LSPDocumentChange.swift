import Foundation

/// Native edits may split a CRLF pair, but LSP cannot address the position
/// between CR and LF. Expand that edge and preserve the unchanged unit so the
/// exact same edit can be expressed using valid protocol line positions.
public struct LSPDocumentChange: Sendable {
    public let range: NSRange
    public let text: String
    public init?(source: NSString, range: NSRange, replacement: String) {
        guard range.location >= 0, range.location <= source.length,
            range.length >= 0, range.length <= source.length - range.location
        else { return nil }
        func splitsCRLF(_ offset: Int) -> Bool {
            offset > 0 && offset < source.length && source.character(at: offset - 1) == 13
                && source.character(at: offset) == 10
        }
        let start = splitsCRLF(range.location)
        let end = splitsCRLF(NSMaxRange(range))
        self.range = NSRange(
            location: range.location - (start ? 1 : 0), length: range.length + (start ? 1 : 0) + (end ? 1 : 0))
        text = start || end ? (start ? "\r" : "") + replacement + (end ? "\n" : "") : replacement
    }
}
