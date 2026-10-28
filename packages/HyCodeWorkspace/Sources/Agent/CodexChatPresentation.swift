import Foundation

/// Pure presentation data. No view, application host, file or network access.
public enum CodexChatPresentation {
    public static let composerMinimumHeight = 46.0
    public static let composerMaximumHeight = 166.0
    public static func composerHeight(_ content: Double) -> Double {
        guard content.isFinite else { return composerMinimumHeight }
        return min(composerMaximumHeight, max(composerMinimumHeight, content))
    }
    public static func modelName(_ value: String) -> String {
        switch value {
        case "deepseek-v4-pro": "DeepSeek V4 Pro"
        case "deepseek-flash": "DeepSeek Flash"
        case "": "选择模型"
        default: value
        }
    }
    public static func effortName(_ value: String) -> String {
        switch value {
        case "none": "关闭思考"
        case "minimal": "极低"
        case "low": "低"
        case "medium": "中"
        case "high": "高"
        case "xhigh": "很高"
        case "max": "最高"
        default: value
        }
    }
    public static func contextName(_ value: Int?) -> String {
        guard let value else { return "自动" }
        if value == 1_048_576 { return "1M" }
        if value > 0, value.isMultiple(of: 1024) { return "\(value / 1024)K" }
        return String(value)
    }
}

public enum CodexChatBlock: Equatable, Sendable {
    case markdown(String)
    case code(language: String, text: String)
}

public enum CodexChatMarkdown {
    /// Fences are structural only at the start of a line. Incomplete streaming
    /// fences remain readable; embedded HTML and images are never executed.
    public static func blocks(_ source: String) -> [CodexChatBlock] {
        let lines = source.components(separatedBy: "\n")
        var result: [CodexChatBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var fence: (character: Character, length: Int, language: String)?
        for line in lines {
            // CR belongs to the original CRLF code content, but not to a
            // delimiter or its language hint.
            let recognition = line.hasSuffix("\r") ? String(line.dropLast()) : line
            let spaces = recognition.prefix(while: { $0 == " " }).count
            let trimmed = recognition.dropFirst(spaces)
            if let active = fence {
                let count = trimmed.prefix(while: { $0 == active.character }).count
                if spaces <= 3, count >= active.length,
                    trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty
                {
                    result.append(
                        .code(
                            language: active.language, text: code.joined(separator: "\n") + (code.isEmpty ? "" : "\n")))
                    code.removeAll(keepingCapacity: true)
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if spaces <= 3, let character = trimmed.first, character == "`" || character == "~" {
                let count = trimmed.prefix(while: { $0 == character }).count
                let hint = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
                if count >= 3, !(character == "`" && hint.contains("`")) {
                    if !prose.isEmpty { result.append(.markdown(prose.joined(separator: "\n"))) }
                    prose.removeAll(keepingCapacity: true)
                    fence = (character, count, String(hint.prefix(80)))
                } else {
                    prose.append(line)
                }
            } else {
                prose.append(line)
            }
            // Hostile or accidental fence storms must not create thousands of
            // native subviews. Preserve the complete original text on fallback.
            if result.count >= 128 { return [.markdown(source)] }
        }
        if let active = fence { result.append(.code(language: active.language, text: code.joined(separator: "\n"))) }
        if !prose.isEmpty { result.append(.markdown(prose.joined(separator: "\n"))) }
        return result.isEmpty ? [.markdown(source)] : result
    }
}
