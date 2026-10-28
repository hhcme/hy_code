import Foundation

public struct CodexMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant, command, changes, reasoning, system }
    public let id: UUID
    public var role: Role
    public var text: String
    public var itemID: String?
    public var turnID: String?
    public var phase: String?
    public var activity: CodexActivity?
    public var payloadBytes: Int { text.utf8.count + (activity?.payloadBytes ?? 0) }
    public init(role: Role, text: String, itemID: String? = nil) {
        id = UUID()
        self.role = role
        self.text = text
        self.itemID = itemID
    }
}

public struct CodexConversation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var threadID: String?
    public var providerURL = ""
    public var model: String
    public var effort: String
    public var contextWindow: Int?
    public var tokenUsage: CodexTokenUsage?
    public var mode: CodexAccessMode = .readOnly
    public var draft = ""
    public var messages: [CodexMessage] = []
    public var updatedAt = Date()
    public init(configuration: CodexConfiguration) {
        id = UUID()
        title = "新对话"
        model = configuration.model
        effort = configuration.effort
        contextWindow = configuration.contextWindow
    }
    public mutating func addUserMessage(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.utf8.count <= 65_536, messages.count < 256,
            messages.reduce(text.utf8.count, { $0 + $1.payloadBytes }) <= 1_048_576
        else { throw LanguageServiceFailure("消息为空或超过 64 KiB，或当前对话已达到消息预算，请新建对话") }
        if messages.isEmpty { title = String(text.replacingOccurrences(of: "\n", with: " ").prefix(36)) }
        messages.append(CodexMessage(role: .user, text: text))
        draft = ""
        updatedAt = Date()
        try checkBudget()
    }
    /// Only the owning run may call this after verifying its conversation and
    /// thread identity. Completed items replace streamed projections, not append.
    public mutating func receive(_ event: JSONValue, redacting secret: String? = nil) throws {
        func safe(_ text: String) -> String {
            guard let secret, !secret.isEmpty else { return text }
            return text.replacingOccurrences(of: secret, with: "[已隐藏密钥]")
        }
        let method = event["method"].string ?? ""
        let params = event["params"]
        let turnID = params["turnId"].string
        if method == "thread/started", let id = params["thread"]["id"].string { threadID = id }
        if method == "thread/tokenUsage/updated", let count = params["tokenUsage"]["last"]["totalTokens"].int,
            count >= 0, count <= 1_000_000_000
        {
            let window = params["tokenUsage"]["modelContextWindow"].int
            tokenUsage = CodexTokenUsage(
                lastRequestTokens: count, modelContextWindow: window.flatMap { $0 > 0 ? $0 : nil })
        }
        if method == "turn/started", let id = params["turn"]["id"].string,
            let index = messages.lastIndex(where: { $0.role == .user })
        {
            messages[index].turnID = id
        }
        if method == "item/agentMessage/delta" {
            try update(
                params["itemId"].string, role: .assistant, text: params["delta"].string ?? "", append: true,
                turnID: turnID, transform: safe)
        } else if method == "item/reasoning/summaryTextDelta" {
            // Only the provider's public summary is displayed; raw reasoning
            // content/textDelta is deliberately not collected.
            try update(
                params["itemId"].string, role: .reasoning, text: params["delta"].string ?? "", append: true,
                turnID: turnID, transform: safe)
        } else if method == "item/reasoning/summaryPartAdded", (params["summaryIndex"].int ?? 0) > 0 {
            try update(
                params["itemId"].string, role: .reasoning, text: "\n\n", append: true, turnID: turnID, transform: safe)
        } else if method == "item/commandExecution/outputDelta" {
            try update(
                params["itemId"].string, role: .command, text: params["delta"].string ?? "", append: true,
                turnID: turnID, transform: safe)
        } else if method == "item/started" || method == "item/completed" {
            let item = params["item"]
            let id = item["id"].string
            switch item["type"].string {
            case "agentMessage":
                if let text = item["text"].string, !text.isEmpty {
                    try update(
                        id, role: .assistant, text: text, append: false, turnID: turnID, phase: item["phase"].string,
                        transform: safe)
                }
            case "reasoning":
                let text = item["summary"].array.compactMap(\.string).joined(separator: "\n\n")
                if !text.isEmpty {
                    try update(id, role: .reasoning, text: text, append: false, turnID: turnID, transform: safe)
                }
            case "commandExecution":
                let text = [item["command"].string, item["aggregatedOutput"].string].compactMap { $0 }.joined(
                    separator: "\n")
                var activity = CodexActivity(kind: .command)
                activity.status = item["status"].string ?? (method == "item/completed" ? "completed" : "inProgress")
                activity.command = safe(item["command"].string ?? "")
                guard item["commandActions"].array.count <= 128 else { throw LanguageServiceFailure("命令活动超过展示预算") }
                activity.actions = item["commandActions"].array.map {
                    CodexCommandAction(
                        kind: safe($0["type"].string ?? "unknown"), path: $0["path"].string.map(safe),
                        query: $0["query"].string.map(safe), name: $0["name"].string.map(safe))
                }
                activity.durationMs = item["durationMs"].int.flatMap { $0 >= 0 ? $0 : nil }
                activity.exitCode = item["exitCode"].int
                try update(
                    id, role: .command, text: text, append: false, turnID: turnID, activity: activity, transform: safe)
            case "fileChange":
                guard item["changes"].array.count <= 256 else { throw LanguageServiceFailure("文件变化超过展示预算") }
                var activity = CodexActivity(kind: .files)
                activity.status = item["status"].string ?? (method == "item/completed" ? "completed" : "inProgress")
                activity.files = item["changes"].array.map {
                    CodexFileChange(
                        path: safe($0["path"].string ?? "文件"), kind: safe($0["kind"]["type"].string ?? "update"),
                        diff: safe($0["diff"].string ?? ""))
                }
                let text = activity.files.map(\.path).joined(separator: "\n")
                try update(
                    id, role: .changes, text: text, append: false, turnID: turnID, activity: activity, transform: safe)
            default: break
            }
        } else if method == "turn/diff/updated", let diff = params["diff"].string {
            var activity = CodexActivity(kind: .turnDiff)
            activity.status = "completed"
            try update(
                "diff-" + (params["turnId"].string ?? "turn"), role: .changes, text: diff, append: false,
                turnID: turnID, activity: activity, transform: safe)
        } else if method == "turn/completed", let id = params["turn"]["id"].string {
            var activity = CodexActivity(kind: .turn)
            activity.status = params["turn"]["status"].string
            activity.durationMs = params["turn"]["durationMs"].int.flatMap { $0 >= 0 ? $0 : nil }
            finishPendingActivities(
                activity.status == "interrupted" ? "interrupted" : activity.status == "failed" ? "failed" : "unknown")
            try update(
                "turn-" + id, role: .system, text: "任务结束", append: false, turnID: id, activity: activity,
                transform: safe)
        }
        updatedAt = Date()
    }
    /// Terminal/disconnected runs cannot leave an eternal "in progress" row.
    /// Missing item completions remain unknown rather than claiming success.
    public mutating func finishPendingActivities(_ status: String) {
        var changed = false
        for index in messages.indices where messages[index].activity?.status == "inProgress" {
            messages[index].activity?.status = ["interrupted", "failed"].contains(status) ? status : "unknown"
            changed = true
        }
        if changed { updatedAt = Date() }
    }
    private mutating func update(
        _ id: String?, role: CodexMessage.Role, text: String, append: Bool,
        turnID: String? = nil, phase: String? = nil, activity: CodexActivity? = nil,
        transform: (String) -> String
    ) throws {
        guard let id, !text.isEmpty || activity != nil else { return }
        let total = messages.reduce(0, { $0 + $1.payloadBytes })
        if let index = messages.firstIndex(where: { $0.itemID == id }) {
            let value = transform(append ? messages[index].text + text : text)
            let size = value.utf8.count + ((activity ?? messages[index].activity)?.payloadBytes ?? 0)
            guard size <= 262_144, total - messages[index].payloadBytes + size <= 1_048_576
            else { throw LanguageServiceFailure("单项输出超过 256 KiB 或对话超过 1 MiB，已停止接收") }
            messages[index].text = value
            if let turnID { messages[index].turnID = turnID }
            if let phase { messages[index].phase = phase }
            if let activity { messages[index].activity = activity }
        } else {
            let value = transform(text)
            let size = value.utf8.count + (activity?.payloadBytes ?? 0)
            guard size <= 262_144, total + size <= 1_048_576, messages.count < 256
            else { throw LanguageServiceFailure("当前对话达到输出预算，请新建对话继续") }
            var message = CodexMessage(role: role, text: value, itemID: id)
            message.turnID = turnID
            message.phase = phase
            message.activity = activity
            messages.append(message)
        }
        try checkBudget()
    }
    private func checkBudget() throws {
        guard messages.count <= 256, messages.reduce(0, { $0 + $1.payloadBytes }) <= 1_048_576 else {
            throw LanguageServiceFailure("当前对话输出达到 1 MiB 预算，已停止；请新建对话继续")
        }
    }
}

/// Admission is separate from UI selection: two readers can run concurrently;
/// a writing turn has exclusive project ownership until the process is reaped.
public struct CodexRunAdmission: Sendable {
    private var running: [UUID: CodexAccessMode] = [:]
    public init() {}
    public mutating func begin(_ id: UUID, mode: CodexAccessMode) throws {
        guard running[id] == nil, running.count < 2,
            !running.values.contains(.workspaceWrite), mode != .workspaceWrite || running.isEmpty
        else { throw LanguageServiceFailure("最多并行两个只读对话；修改项目时需等待其他任务结束") }
        running[id] = mode
    }
    public mutating func finish(_ id: UUID) { running[id] = nil }
}
