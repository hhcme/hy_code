import Foundation

/// One active turn owns one app-server process. Disk-backed official thread
/// history supports resumption; idle chats retain no child process or credentials.
public actor CodexAgentRun {
    private let connection = CodexJSONLConnection()
    private var approvals: [String: JSONValue] = [:]
    private var cancelled = false
    private var activeThread: String?
    private var activeTurn: String?
    private var completed = false
    private var shutdown: Task<Void, Never>?
    public init() {}

    public func run(
        executable: URL, root: URL, home: URL, configuration: CodexConfiguration,
        apiKey: String, conversation: CodexConversation,
        onEvent: @escaping @Sendable (JSONValue) async throws -> Void
    ) async throws -> String {
        do {
            guard !cancelled else { throw CancellationError() }
            try CodexModelCatalog.prepare(home: home, configuration: configuration)
            try await connection.start(
                executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: CodexSandbox.arguments(
                    executable: executable, root: root, home: home, mode: conversation.mode,
                    runtimeArguments: configuration.arguments(home: home)), directory: root,
                environment: configuration.environment(home: home, apiKey: apiKey))
            _ = try await connection.request(
                "initialize",
                params: JSONValue([
                    "clientInfo": ["name": "hycode", "title": "HyCode", "version": "0.1.0"],
                    "capabilities": ["experimentalApi": true],
                ]))
            try await connection.notify("initialized")
            let effective = try await connection.request("config/read", params: JSONValue(["includeLayers": false]))
            let config = effective["config"]
            guard config["model_provider"].string == "hycode",
                config["model_providers"]["hycode"]["base_url"].string == configuration.baseURL,
                config["model_reasoning_effort"].string == configuration.effort,
                configuration.contextWindow == nil || config["model_context_window"].int == configuration.contextWindow,
                config["mcp_servers"] == .null || config["mcp_servers"] == .object([:]),
                config["notify"] == .null,
                config["hooks"] == .null || config["hooks"] == .object([:])
            else { throw LanguageServiceFailure("运行时加载了非 HyCode 服务商或额外工具配置，已停止以避免混用环境") }
            let approvalPolicy: JSONValue =
                conversation.mode == .readOnly
                ? .string("never")
                : JSONValue([
                    "granular": [
                        "sandbox_approval": false, "rules": true, "mcp_elicitations": false,
                        "request_permissions": false, "skill_approval": false,
                    ]
                ])
            var params: [String: Any] = [
                "cwd": root.path, "model": conversation.model, "modelProvider": "hycode",
                "approvalPolicy": approvalPolicy, "approvalsReviewer": "user",
                "sandbox": "read-only",
            ]
            let method: String
            if let thread = conversation.threadID {
                params["threadId"] = thread
                method = "thread/resume"
            } else {
                method = "thread/start"
            }
            let thread = try await connection.request(method, params: JSONValue(params))
            guard let threadID = thread["thread"]["id"].string else {
                throw LanguageServiceFailure("Codex 未返回会话身份")
            }
            activeThread = threadID
            try await onEvent(JSONValue(["method": "thread/started", "params": ["thread": ["id": threadID]]]))
            guard !cancelled else { throw CancellationError() }
            let prompt = conversation.messages.last(where: { $0.role == .user })?.text ?? ""
            // The outer Seatbelt already owns the filesystem boundary. macOS
            // refuses a second sandbox_apply inside that sandbox. Tell Codex to
            // use the host sandbox rather than silently failing every tool call.
            let policy = JSONValue(["type": "externalSandbox", "networkAccess": "enabled"])
            let started = try await connection.request(
                "turn/start",
                params: JSONValue([
                    "threadId": .string(threadID), "model": .string(conversation.model),
                    "effort": .string(conversation.effort), "sandboxPolicy": policy,
                    "input": JSONValue([["type": "text", "text": prompt]]),
                ]))
            guard let turnID = started["turn"]["id"].string else { throw LanguageServiceFailure("Codex 未返回任务身份") }
            activeTurn = turnID
            for await event in connection.events {
                try Task.checkCancellation()
                let values = event["params"]
                if event["method"].string == "serverRequest/resolved" {
                    if let key = try? Self.requestKey(values["requestId"]) { approvals[key] = nil }
                }
                if let id = values["threadId"].string, id != threadID { continue }
                if let id = values["turnId"].string, id != turnID { continue }
                if event["id"] != .null, let method = event["method"].string {
                    if ["item/commandExecution/requestApproval", "item/fileChange/requestApproval"].contains(method),
                        conversation.mode == .workspaceWrite, approvals.count < 16
                    {
                        let id = event["id"]
                        let key = try Self.requestKey(id)
                        approvals[key] = id
                        try await onEvent(event)
                    } else {
                        try await connection.reject(id: event["id"])
                    }
                } else {
                    try await onEvent(event)
                }
                if event["method"].string == "turn/completed", values["turn"]["id"].string == turnID {
                    completed = true
                    let status = values["turn"]["status"].string
                    await connection.stop()
                    if status == "interrupted" || cancelled { throw CancellationError() }
                    guard status == "completed" else {
                        throw LanguageServiceFailure("Codex 任务失败，请检查服务商兼容性、模型权限或余额")
                    }
                    return threadID
                }
            }
            throw LanguageServiceFailure("Codex 在任务完成前断开，历史已保留，可重新发送继续")
        } catch {
            approvals.removeAll()
            await connection.stop()
            if cancelled || Task.isCancelled { throw CancellationError() }
            let diagnostic = await connection.diagnostic()
            throw LanguageServiceFailure(error.localizedDescription + (diagnostic.isEmpty ? "" : "\n" + diagnostic))
        }
    }
    public func answer(_ id: JSONValue, accept: Bool) async throws {
        let key = try Self.requestKey(id)
        guard !cancelled, let value = approvals.removeValue(forKey: key) else {
            throw LanguageServiceFailure("该审批已失效")
        }
        try await connection.respond(id: value, result: JSONValue(["decision": accept ? "accept" : "decline"]))
    }
    public func stop() async {
        if let shutdown {
            await shutdown.value
            return
        }
        cancelled = true
        approvals.removeAll()
        let task = Task { [weak self] in await self?.finishStopping() }
        let shutdown = Task<Void, Never> { _ = await task.value }
        self.shutdown = shutdown
        await shutdown.value
    }
    private func finishStopping() async {
        if !completed, let thread = activeThread, let turn = activeTurn {
            _ = try? await connection.request(
                "turn/interrupt", params: JSONValue(["threadId": thread, "turnId": turn]), timeout: 2)
            for _ in 0..<20 {
                if completed { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        await connection.stop()
    }
    private static func requestKey(_ id: JSONValue) throws -> String {
        guard id.string != nil || id.int != nil else { throw LanguageServiceFailure("Codex 审批身份无效") }
        return String(decoding: try JSONEncoder().encode(id), as: UTF8.self)
    }
}
