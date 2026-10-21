import CoreText
import Foundation

/// Presentation preparation only. Native directory enumeration and its ABI stay
/// independent of typography. No AppKit, application host or window is needed.
public enum ProjectTreeText {
    public static let nameFontSize = 13.0

    public static func nameWidths(for entries: [WorkspaceEntry]) async throws -> [String: Double] {
        let result = try await ProjectTreeTextWorker.shared.measure(entries)
        try Task.checkCancellation()
        return result
    }
}

/// One background worker bounds font preparation even if many reads finish at
/// once. The caller's cancellation remains attached across the actor hop.
private actor ProjectTreeTextWorker {
    static let shared = ProjectTreeTextWorker()

    func measure(_ entries: [WorkspaceEntry]) throws -> [String: Double] {
        try Task.checkCancellation()
        guard !entries.isEmpty else { return [:] }
        let font =
            CTFontCreateUIFontForLanguage(.system, ProjectTreeText.nameFontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, ProjectTreeText.nameFontSize, nil)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        var result: [String: Double] = [:]
        result.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            if index % 64 == 0 { try Task.checkCancellation() }
            let text = NSAttributedString(string: entry.name, attributes: attributes)
            let line = CTLineCreateWithAttributedString(text)
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            result[entry.relativePath] = max(advance, ink.maxX) - min(0, ink.minX)
        }
        try Task.checkCancellation()
        return result
    }
}
