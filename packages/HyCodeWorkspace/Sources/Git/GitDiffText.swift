import AppKit
import CoreText
import Foundation

/// Read-only diff presentation metrics, prepared by the repository actor.
/// Measuring glyph advances keeps CJK, emoji and tabs horizontally reachable.
public enum GitDiffText {
    public static let fontSize = 14.0
    public static var fontName: String { NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName }

    static func widths(_ rows: [GitDiffRow]) throws -> (left: Double, right: Double) {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            .paragraphStyle: NSParagraphStyle.default,
        ]
        var cache: [String: Double] = [:]
        func measure(_ text: String?) -> Double {
            guard let text, !text.isEmpty else { return 0 }
            if let value = cache[text] { return value }
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let width = ceil(max(advance, ink.maxX) - min(0, ink.minX))
            if cache.count < 1024 { cache[text] = width }
            return width
        }
        var left = 0.0
        var right = 0.0
        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            left = max(left, measure(row.left))
            right = max(right, measure(row.right))
        }
        try Task.checkCancellation()
        return (left, right)
    }
}
