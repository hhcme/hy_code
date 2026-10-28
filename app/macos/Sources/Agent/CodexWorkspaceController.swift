import Foundation
import HyCodeWorkspace
import Observation

@MainActor @Observable
final class CodexWorkspaceController {
    struct Approval: Identifiable {
        let id = UUID()
        let requestID: JSONValue
        let title: String
        let detail: String
    }
    private(set) var state = CodexProjectState()
    private(set) var statuses: [UUID: String] = [:]
    private(set) var conversationErrors: [UUID: String] = [:]
    private(set) var approvals: [UUID: [Approval]] = [:]
    private(set) var loading = false
    private(set) var ready = false
    private(set) var hasKey = false
    private(set) var credentialIssue: String?
    private(set) var configuring = false
    var error: String?
    var showingSettings = false
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var storage: CodexStore?
    @ObservationIgnored private let credentials = CodexCredentials()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var admission = CodexRunAdmission()
    @ObservationIgnored private var runs: [UUID: CodexAgentRun] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var persistence: Task<Void, Never>?
    @ObservationIgnored var prepareWrite: (UUID) async -> Bool = { _ in false }
    @ObservationIgnored var finishWrite: (UUID) -> Void = { _ in }
    @ObservationIgnored var executionAllowed: () -> Bool = { true }
    var projectOpen: Bool { access != nil }
    var busy: Bool { !runs.isEmpty }
    var active: CodexConversation? { state.conversations.first { $0.id == state.selectedID } }
    func running(_ id: UUID) -> Bool { runs[id] != nil }
    func select(_ id: UUID) {
        state.selectedID = id
        persist()
    }

    func configure(access: WorkspaceAccess?) {
        generation = UUID()
        persistence?.cancel()
        self.access = access
        state = CodexProjectState()
        statuses.removeAll()
        conversationErrors.removeAll()
        approvals.removeAll()
        ready = false
        hasKey = false
        credentialIssue = nil
        error = nil
        storage = nil
        guard let access else {
            loading = false
            return
        }
        loading = true
        let ticket = generation
        let storage = CodexStore(directory: CodexStore.projectDirectory(root: access.url))
        self.storage = storage
        Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                var state = try await storage.load()
                if let defaults = try? await CodexStore(directory: CodexStore.defaultsDirectory)
                    .configurationSnapshot(),
                    state.inheritConfiguration(defaults)
                {
                    try await storage.save(state)
                }
                var hasKey = false
                var credentialIssue: String?
                do {
                    hasKey =
                        try await self?.credentials.read(state.configuration.credentialAccount(root: access.url)) != nil
                } catch { credentialIssue = error.localizedDescription }
                guard let self, self.generation == ticket else { return }
                self.state = state
                self.hasKey = hasKey
                self.credentialIssue = credentialIssue
                self.loading = false
                self.ready = true
            } catch {
                guard let self, self.generation == ticket else { return }
                self.loading = false
                self.error = error.localizedDescription
            }
        }
    }
    func retryLoading() { configure(access: access) }
    func newConversation() {
        guard ready, !configuring else { return }
        guard state.conversations.count < 24 else {
            error = "最多保留 24 个对话，请先删除不再需要的对话"
            return
        }
        let value = CodexConversation(configuration: state.configuration)
        state.conversations.insert(value, at: 0)
        state.selectedID = value.id
        persist()
    }
    func rename(_ id: UUID, title: String) {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state.conversations[index].title = String(value.prefix(100))
        persist()
    }
    func delete(_ id: UUID) {
        guard !running(id) else {
            error = "请先停止该对话的任务"
            return
        }
        state.conversations.removeAll { $0.id == id }
        if state.selectedID == id { state.selectedID = state.conversations.first?.id }
        statuses[id] = nil
        conversationErrors[id] = nil
        if let storage {
            Task {
                do { try await storage.deleteRuntime(id) } catch { self.error = error.localizedDescription }
            }
        }
        persist()
    }
    func update(_ id: UUID, _ edit: (inout CodexConversation) -> Void) {
        guard let index = state.conversations.firstIndex(where: { $0.id == id }) else { return }
        var next = state
        edit(&next.conversations[index])
        do {
            try next.validate()
            state = next
            persist()
        } catch { conversationErrors[id] = error.localizedDescription }
    }
    func applySettings(_ configuration: CodexConfiguration, key: String, makeDefault: Bool = false) async -> Bool {
        guard ready, !busy, !configuring, let access else { return false }
        configuring = true
        defer { configuring = false }
        let ticket = generation
        do {
            var value = try configuration.validated()
            // A rebuilt unsigned application may no longer own the previous
            // item's ACL. Replacement credentials use a fresh item.
            value.credentialID = key.isEmpty ? state.configuration.credentialID : UUID()
            value.credentialScope =
                key.isEmpty ? state.configuration.credentialScope : (makeDefault ? .application : .project)
            if makeDefault, value.credentialScope != .application {
                throw LanguageServiceFailure("将服务设为 HyCode 默认值时，请重新填写密钥以创建独立的应用凭据")
            }
            let account = value.credentialAccount(root: access.url)
            if key.isEmpty {
                guard value.baseURL == state.configuration.baseURL, try await credentials.read(account) != nil else {
                    throw LanguageServiceFailure("请为当前服务地址填写 API Key")
                }
            } else {
                guard key.utf8.count <= 16_384, !key.contains("\0") else { throw LanguageServiceFailure("API Key 无效") }
                try await credentials.write(key, account: account)
            }
            guard generation == ticket else { return false }
            if makeDefault {
                try await CodexStore(directory: CodexStore.defaultsDirectory).stageConfiguration(value)
                guard generation == ticket else { return false }
            }
            state.configuration = value
            hasKey = true
            credentialIssue = nil
            error = nil
            persist()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func send(_ id: UUID) {
        guard ready, !configuring, !running(id), let access, let storage,
            let index = state.conversations.firstIndex(where: { $0.id == id })
        else { return }
        do {
            guard executionAllowed() else { throw LanguageServiceFailure("其他项目工具正在执行，请等待结束后发送") }
            var config = try state.configuration.validated()
            var conversation = state.conversations[index]
            guard conversation.providerURL.isEmpty || conversation.providerURL == config.baseURL else {
                throw LanguageServiceFailure("该对话属于原来的服务商，请为新的服务地址新建对话")
            }
            conversation.providerURL = config.baseURL
            config.model = conversation.model.isEmpty ? config.model : conversation.model
            config.effort = conversation.effort
            config.contextWindow = conversation.contextWindow
            config = try config.validated()
            conversation.model = config.model
            try conversation.addUserMessage(conversation.draft)
            try admission.begin(id, mode: conversation.mode)
            state.conversations[index] = conversation
            let run = CodexAgentRun()
            runs[id] = run
            statuses[id] = "正在连接"
            conversationErrors[id] = nil
            error = nil
            let ticket = generation
            tasks[id] = Task { [weak self, access] in
                guard let self else { return }
                var writing = false
                defer { withExtendedLifetime(access) {} }
                do {
                    if conversation.mode == .workspaceWrite {
                        writing = await self.prepareWrite(id)
                        guard writing else { throw LanguageServiceFailure("修改任务需要先保存全部文档，并等待其他工具和修改预览结束") }
                    }
                    try Task.checkCancellation()
                    guard let secret = try await self.credentials.read(config.credentialAccount(root: access.url))
                    else {
                        throw LanguageServiceFailure("请先在 Codex 设置中保存当前项目的 API Key")
                    }
                    let home = try await storage.runtimeHome(id, root: access.url)
                    let executable = try await CodexBundledRuntime.shared.executable()
                    _ = try await run.run(
                        executable: executable, root: access.url, home: home, configuration: config,
                        apiKey: secret, conversation: conversation
                    ) { [weak self] event in
                        try await self?.receive(event, id: id, generation: ticket, secret: secret)
                    }
                    if self.generation == ticket { self.statuses[id] = "已完成" }
                } catch is CancellationError {
                    if self.generation == ticket { self.statuses[id] = "已停止" }
                } catch {
                    if self.generation == ticket {
                        self.statuses[id] = "失败"
                        self.conversationErrors[id] = error.localizedDescription
                    }
                }
                await run.stop()
                if self.generation == ticket, let index = self.state.conversations.firstIndex(where: { $0.id == id }) {
                    self.state.conversations[index].finishPendingActivities(
                        self.statuses[id] == "已停止" ? "interrupted" : self.statuses[id] == "已完成" ? "unknown" : "failed")
                }
                if writing { self.finishWrite(id) }
                self.runs[id] = nil
                self.tasks[id] = nil
                self.approvals[id] = nil
                self.admission.finish(id)
                self.persist()
            }
            persist()
        } catch { self.error = error.localizedDescription }
    }
    private func receive(_ event: JSONValue, id: UUID, generation: UUID, secret: String) async throws {
        guard self.generation == generation, running(id),
            let index = state.conversations.firstIndex(where: { $0.id == id })
        else { throw CancellationError() }
        let method = event["method"].string ?? ""
        if method.hasSuffix("/requestApproval") {
            let params = event["params"]
            let detail = [params["command"].string, params["reason"].string, params["cwd"].string]
                .compactMap { $0 }.joined(separator: "\n")
            approvals[id, default: []].append(
                Approval(
                    requestID: event["id"], title: method.contains("fileChange") ? "批准文件修改" : "批准命令执行",
                    detail: detail.isEmpty
                        ? "查看上方对应的操作或文件差异后决定。"
                        : String(detail.replacingOccurrences(of: secret, with: "[已隐藏密钥]").prefix(16_384))))
            statuses[id] = "等待审批"
        } else if method == "serverRequest/resolved" {
            let request = event["params"]["requestId"]
            approvals[id]?.removeAll { $0.requestID == request }
        } else if method == "turn/started" {
            statuses[id] = "正在运行"
        }
        let snapshot = state.conversations[index]
        let projection = Task.detached(priority: .utility) {
            var conversation = snapshot
            try conversation.receive(event, redacting: secret)
            return conversation
        }
        let next = try await withTaskCancellationHandler(
            operation: { try await projection.value }, onCancel: { projection.cancel() })
        guard self.generation == generation, running(id),
            let current = state.conversations.firstIndex(where: { $0.id == id })
        else { throw CancellationError() }
        // The event owner updates only protocol state. A draft or title edited
        // while the utility task ran belongs to the UI and must be retained.
        state.conversations[current].messages = next.messages
        state.conversations[current].threadID = next.threadID
        state.conversations[current].tokenUsage = next.tokenUsage
        state.conversations[current].updatedAt = next.updatedAt
        persist()
    }
    func answer(_ approval: Approval, conversation id: UUID, accept: Bool) {
        guard let run = runs[id] else { return }
        approvals[id]?.removeAll { $0.id == approval.id }
        Task {
            do { try await run.answer(approval.requestID, accept: accept) } catch {
                self.error = error.localizedDescription
            }
        }
        statuses[id] = "正在运行"
    }
    func stop(_ id: UUID) {
        guard let run = runs[id] else { return }
        statuses[id] = "正在停止"
        Task { await run.stop() }
    }
    func stopAll() async {
        let current = Array(tasks.values)
        for id in Array(runs.keys) { stop(id) }
        for task in current { await task.value }
        persistence?.cancel()
        if ready, let storage {
            do { try await storage.save(state) } catch { self.error = error.localizedDescription }
        }
    }
    private func persist() {
        guard ready, let storage else { return }
        persistence?.cancel()
        let ticket = generation
        persistence = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, self.generation == ticket else { return }
            do { try await storage.save(self.state) } catch {
                if self.generation == ticket { self.error = error.localizedDescription }
            }
        }
    }
}
