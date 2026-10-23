import Foundation

public enum MarkupFormat: String, Sendable {
    case markdown, html
    public static func detect(_ path: String) -> Self? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": .markdown
        case "html", "htm": .html
        default: nil
        }
    }
}
public enum MarkupPreviewMode: String, CaseIterable, Sendable {
    case source, split, preview
    public var title: String {
        switch self {
        case .source: "源码"
        case .split: "左右预览"
        case .preview: "预览"
        }
    }
}
public struct MarkupPreviewContent: Decodable, Sendable {
    public struct Block: Decodable, Sendable {
        public let line: Int
        public let id: String
    }
    public let html: String
    public let blocks: [Block]
    public let markdown: Bool
}
public enum MarkupPreviewFailure {
    public static func preparation(_ error: Error) -> String {
        let error = error as NSError
        // WebKit puts the compiler reason here, while localizedDescription
        // otherwise only reports WKErrorDomain 6.
        let details =
            [error.helpAnchor, error.localizedFailureReason, error.localizedDescription]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? error.domain
        return "无法准备离线预览：" + String(details.prefix(512))
    }
}
/// Only pure geometry crosses the WebKit/native scroll bridge. No DOM object,
/// script text or file URL can become an editor command through this channel.
public enum MarkupScrollMapping {
    public static func fraction(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
    public static func splitRatio(_ value: Double) -> Double { value.isFinite ? min(0.8, max(0.2, value)) : 0.5 }
    public static func line(_ value: Double?, count: Int) -> Int? {
        guard let value, value.isFinite, value >= 0, value.rounded(.down) == value, value < Double(max(1, count))
        else { return nil }
        return Int(value)
    }
}
