import Foundation

public struct LSPTextEdit: Decodable, Sendable {
    public let range: LSPRange
    public let newText: String
    public init(range: LSPRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}
public enum LSPTextEdits {
    public static func completionOffset(primary: LSPTextEdit, additional: [LSPTextEdit], text: String) throws -> Int {
        let source = text as NSString
        let index = TextLineIndex(text, unicodeLineSeparators: false)
        guard let main = primary.range.range(in: index, source: source) else { throw LanguageServiceFailure("补全位置无效") }
        var offset = main.location + primary.newText.utf16.count
        for edit in additional {
            guard let range = edit.range.range(in: index, source: source) else {
                throw LanguageServiceFailure("导入位置无效")
            }
            if range.location < main.location { offset += edit.newText.utf16.count - range.length }
        }
        return offset
    }
    /// Validate all edits against one immutable revision before constructing a
    /// replacement. The native editor applies it as one undoable user edit.
    public static func apply(_ edits: [LSPTextEdit], to text: String) throws -> String {
        guard edits.count <= 5_000 else { throw LanguageServiceFailure("编辑结果过多") }
        let source = text as NSString
        let index = TextLineIndex(text, unicodeLineSeparators: false)
        let mapped = try edits.map { edit -> (NSRange, String) in
            guard let range = edit.range.range(in: index, source: source) else {
                throw LanguageServiceFailure("分析器编辑范围无效")
            }
            return (range, edit.newText)
        }.sorted { $0.0.location > $1.0.location }
        var boundary = source.length
        var lastStart: Int?
        let result = NSMutableString(string: text)
        for (range, replacement) in mapped {
            guard NSMaxRange(range) <= boundary, lastStart != range.location else {
                throw LanguageServiceFailure("分析器编辑范围重叠")
            }
            result.replaceCharacters(in: range, with: replacement)
            boundary = range.location
            lastStart = range.location
        }
        guard result.length <= 8 * 1024 * 1024 else { throw LanguageServiceFailure("编辑结果过大") }
        return result as String
    }
}
