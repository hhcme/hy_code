import Foundation

public struct CodexTranscriptEntry: Equatable, Identifiable, Sendable {
    public let messages: [CodexMessage]
    public var id: UUID { messages[0].id }
    public var isActivity: Bool { messages[0].role == .command || messages[0].role == .changes }
    public static func project(_ messages: [CodexMessage]) -> [Self] {
        var result: [Self] = []
        var tools: [CodexMessage] = []
        func flush() {
            if !tools.isEmpty {
                result.append(Self(messages: tools))
                tools.removeAll(keepingCapacity: true)
            }
        }
        for message in messages {
            // Aggregate diffs are used by the change review, never displayed a
            // second time as another tool activity in the transcript.
            if message.activity?.kind == .turnDiff { continue }
            if message.role == .command || message.role == .changes {
                if let previous = tools.last, previous.turnID != message.turnID { flush() }
                tools.append(message)
            } else {
                flush()
                result.append(Self(messages: [message]))
            }
        }
        flush()
        return result
    }
    public var title: String {
        var edits = false
        var reads = false
        var searches = false
        var commands = false
        for message in messages {
            if message.role == .changes { edits = true }
            if message.role == .command {
                let actions = message.activity?.actions ?? []
                reads = reads || actions.contains { ["read", "listFiles"].contains($0.kind) }
                searches = searches || actions.contains { $0.kind == "search" }
                commands =
                    commands || actions.isEmpty
                    || actions.contains { !["read", "listFiles", "search"].contains($0.kind) }
            }
        }
        return [
            (edits ? "编辑了文件" : nil), (reads ? "读取了文件" : nil), (searches ? "搜索了代码" : nil), (commands ? "运行了命令" : nil),
        ]
        .compactMap { $0 }.joined(separator: "、")
    }
}

public struct CodexChangeSummary: Equatable, Sendable {
    public var files: [CodexFileChange]
    public var fileCount: Int
    public var limited: Bool { fileCount > files.count }
    public var added: Int { files.reduce(0) { $0 + $1.added } }
    public var removed: Int { files.reduce(0) { $0 + $1.removed } }
    public init(messages: [CodexMessage]) {
        let start = messages.lastIndex(where: { $0.role == .user }) ?? 0
        let turn = messages.dropFirst(start)
        if let diff = turn.last(where: { $0.activity?.kind == .turnDiff }) {
            let parsed = CodexUnifiedDiff.parse(diff.text)
            files = parsed.files
            fileCount = parsed.fileCount
            return
        }
        var changes: [CodexFileChange] = []
        var seen: Set<String> = []
        var indexes: [String: Int] = [:]
        for message in turn where message.activity?.kind == .files && message.activity?.status == "completed" {
            for file in message.activity?.files ?? [] {
                if let index = indexes[file.path] {
                    // Without a server aggregate, retain all reported patches
                    // in order. A later turn/diff replaces this projection.
                    changes[index] = CodexFileChange(
                        path: file.path, kind: file.kind, diff: changes[index].diff + "\n" + file.diff)
                } else if changes.count < 256 {
                    indexes[file.path] = changes.count
                    changes.append(file)
                }
                seen.insert(file.path)
            }
        }
        files = changes
        fileCount = seen.count
    }
}

extension CodexChatPresentation {
    public static func duration(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        if seconds < 60 { return "\(seconds)秒" }
        if seconds < 3600 { return "\(seconds / 60)分钟\(seconds % 60)秒" }
        return "\(seconds / 3600)小时\((seconds % 3600) / 60)分钟"
    }
    public static func activityTitle(_ message: CodexMessage) -> String {
        guard let activity = message.activity else { return message.role == .changes ? "文件更改" : "运行了命令" }
        let active = activity.status == "inProgress"
        let failed = ["failed", "declined", "interrupted"].contains(activity.status ?? "")
        if activity.kind == .command {
            if let action = activity.actions.first, activity.actions.count == 1 {
                let name = action.name ?? action.path.map { ($0 as NSString).lastPathComponent } ?? "项目"
                if !failed && !active && activity.status != "completed" {
                    return
                        (action.kind == "read"
                        ? "读取状态未知 "
                        : action.kind == "listFiles" ? "列出状态未知 " : action.kind == "search" ? "搜索状态未知 " : "执行状态未知 ")
                        + name
                }
                if action.kind == "read" { return (failed ? "读取失败 " : active ? "正在读取 " : "已读取 ") + name }
                if action.kind == "listFiles" { return (failed ? "列出失败 " : active ? "正在列出 " : "已列出 ") + name }
                if action.kind == "search" {
                    return (failed ? "搜索失败 " : active ? "正在搜索 " : "已搜索 ") + (action.query ?? name)
                }
            }
            let prefix: String
            if failed {
                prefix = "执行失败 "
            } else if active {
                prefix = "正在运行 "
            } else if activity.status != "completed" {
                prefix = "执行状态未知 "
            } else if let duration = activity.durationMs, duration >= 1000 {
                prefix = "已在\(self.duration(duration))内运行 "
            } else {
                prefix = "已运行 "
            }
            return prefix + (activity.command ?? message.text.components(separatedBy: "\n").first ?? "命令")
        }
        return failed ? "文件修改失败" : active ? "正在编辑文件" : activity.status == "completed" ? "已编辑文件" : "文件修改状态未知"
    }
    public static func nearBottom(documentHeight: Double, viewportBottom: Double) -> Bool {
        documentHeight.isFinite && viewportBottom.isFinite && documentHeight - viewportBottom <= 4
    }
}
