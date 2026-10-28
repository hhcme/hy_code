import Darwin
import Foundation

public struct CodexProjectState: Codable, Sendable {
    public var schema = 1
    public var configuration = CodexConfiguration()
    public var conversations: [CodexConversation] = []
    public var selectedID: UUID?
    public init() {}
    /// New workspaces inherit HyCode's own defaults, including an existing unsent
    /// draft. Explicit project settings and started threads remain independent.
    public mutating func inheritConfiguration(_ value: CodexConfiguration) -> Bool {
        if configuration.credentialScope == .application, value.credentialScope == .application,
            configuration.baseURL == value.baseURL, configuration.credentialID != value.credentialID
        {
            configuration.credentialID = value.credentialID
            return true
        }
        guard configuration.baseURL.isEmpty, configuration.model.isEmpty else { return false }
        configuration = value
        for index in conversations.indices
        where conversations[index].model.isEmpty && conversations[index].threadID == nil {
            conversations[index].model = value.model
            conversations[index].effort = value.effort
            conversations[index].contextWindow = value.contextWindow
        }
        if conversations.isEmpty {
            let conversation = CodexConversation(configuration: value)
            conversations = [conversation]
            selectedID = conversation.id
        }
        return true
    }
    public mutating func applyConfiguration(_ value: CodexConfiguration) {
        configuration = value
        if let index = conversations.firstIndex(where: { $0.id == selectedID }),
            conversations[index].threadID == nil, conversations[index].messages.isEmpty,
            conversations[index].draft.isEmpty
        {
            conversations[index].model = value.model
            conversations[index].effort = value.effort
            conversations[index].contextWindow = value.contextWindow
            conversations[index].providerURL = value.baseURL
        } else if conversations.count < 24 {
            let conversation = CodexConversation(configuration: value)
            conversations.insert(conversation, at: 0)
            selectedID = conversation.id
        }
    }
    public func validate() throws {
        guard schema == 1, conversations.count <= 24,
            Set(conversations.map(\.id)).count == conversations.count,
            conversations.allSatisfy({
                $0.messages.count <= 256
                    && $0.messages.allSatisfy {
                        $0.payloadBytes <= 262_144 && ($0.activity?.actions.count ?? 0) <= 128
                            && ($0.activity?.files.count ?? 0) <= 256
                    }
                    && $0.messages.reduce(0, { $0 + $1.payloadBytes }) <= 1_048_576
                    && $0.draft.utf8.count <= 65_536 && $0.title.count <= 100 && $0.model.utf8.count <= 200
            })
        else { throw LanguageServiceFailure("对话达到存储预算：草稿最多 64 KiB、单项输出 256 KiB、每对话 256 项/1 MiB，最多 24 对话") }
    }
}

/// One actor serializes project settings/transcripts. Credentials never enter
/// this format. Private directories reject symlinks and use owner-only modes.
public actor CodexStore {
    public let directory: URL
    private var lease: CodexStoreLease?
    public init(directory: URL) { self.directory = directory }
    public static var defaultsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("HyCode/Codex/defaults")
    }
    public static func projectDirectory(root: URL) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent(
                "HyCode/Codex/projects/" + CodexConfiguration.workspaceKey(root))
    }
    public func load() throws -> CodexProjectState {
        try prepare()
        // Setup never replaces a running app's snapshot. It leaves a separate
        // handoff, imported by this owner only when the project next opens.
        let handoff = try CodexStoreLease(directory: directory, name: ".setup.lock")
        defer { withExtendedLifetime(handoff) {} }
        var state = try readState(directory.appendingPathComponent("state.json"))
        let pending = directory.appendingPathComponent("provider-setup.json")
        if FileManager.default.fileExists(atPath: pending.path) {
            state.applyConfiguration(try readConfiguration(pending))
            try save(state)
            try FileManager.default.removeItem(at: pending)
        }
        return state
    }
    public func stageConfiguration(_ configuration: CodexConfiguration) throws {
        try prepareDirectories()
        let handoff = try CodexStoreLease(directory: directory, name: ".setup.lock")
        defer { withExtendedLifetime(handoff) {} }
        try atomicWrite(try JSONEncoder().encode(configuration.validated()), name: "provider-setup.json")
    }
    /// Read-only verification cannot import a pending setup or write state.
    public func configurationSnapshot() throws -> CodexConfiguration {
        try prepareDirectories()
        let handoff = try CodexStoreLease(directory: directory, name: ".setup.lock")
        defer { withExtendedLifetime(handoff) {} }
        let pending = directory.appendingPathComponent("provider-setup.json")
        if FileManager.default.fileExists(atPath: pending.path) { return try readConfiguration(pending) }
        return try readState(directory.appendingPathComponent("state.json")).configuration.validated()
    }
    private func readConfiguration(_ path: URL) throws -> CodexConfiguration {
        try Self.regular(path)
        guard (try path.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 <= 16_384 else {
            throw LanguageServiceFailure("Codex 待应用配置超过读取预算")
        }
        return try JSONDecoder().decode(CodexConfiguration.self, from: Data(contentsOf: path)).validated()
    }
    private func readState(_ path: URL) throws -> CodexProjectState {
        guard FileManager.default.fileExists(atPath: path.path) else { return CodexProjectState() }
        try Self.regular(path)
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 33_554_432 else { throw LanguageServiceFailure("Codex 历史超过 32 MiB 读取预算") }
        let state = try JSONDecoder().decode(CodexProjectState.self, from: Data(contentsOf: path))
        try state.validate()
        return state
    }
    public func save(_ state: CodexProjectState) throws {
        try prepare()
        try state.validate()
        let data = try JSONEncoder().encode(state)
        guard data.count <= 33_554_432 else { throw LanguageServiceFailure("Codex 历史超过 32 MiB 保存预算") }
        try atomicWrite(data, name: "state.json")
    }
    private func atomicWrite(_ data: Data, name: String) throws {
        let temporary = directory.appendingPathComponent(".state-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { try Self.regular(destination) }
        guard rename(temporary.path, destination.path) == 0 else { throw POSIXError(.EIO) }
    }
    public func runtimeHome(_ id: UUID, root: URL) throws -> URL {
        try prepare()
        let home = directory.appendingPathComponent("sessions/" + id.uuidString, isDirectory: true)
        try Self.privateDirectory(directory.appendingPathComponent("sessions"))
        try Self.privateDirectory(home)
        try Self.privateDirectory(home.appendingPathComponent("tmp"))
        // An untrusted project may supply AGENTS.md, but must not mount project
        // hooks, MCP servers, plugins or credential-routing settings at startup.
        let encoded = try CodexWireLiteral.string(CodexSandbox.canonicalPath(root))
        let config = Data(("[projects." + encoded + "]\ntrust_level = \"untrusted\"\n").utf8)
        let path = home.appendingPathComponent("config.toml")
        if FileManager.default.fileExists(atPath: path.path) { try Self.regular(path) }
        try config.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return home
    }
    public func deleteRuntime(_ id: UUID) throws {
        let path = directory.appendingPathComponent("sessions/" + id.uuidString)
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        guard path.resolvingSymlinksInPath().path == path.standardizedFileURL.path else {
            throw LanguageServiceFailure("Codex 会话目录包含符号链接，已停止删除")
        }
        try FileManager.default.removeItem(at: path)
    }
    private func prepare() throws {
        try prepareDirectories()
        if lease == nil { lease = try CodexStoreLease(directory: directory) }
    }
    private func prepareDirectories() throws {
        try Self.privateDirectory(directory.deletingLastPathComponent())
        try Self.privateDirectory(directory)
    }
    private static func regular(_ url: URL) throws {
        let value = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard value.isSymbolicLink != true, value.isRegularFile == true else {
            throw LanguageServiceFailure("Codex 私有存储目标不是普通文件")
        }
    }
    private static func privateDirectory(_ url: URL) throws {
        let manager = FileManager.default
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw LanguageServiceFailure("Codex 私有存储的目录层级包含符号链接")
        }
        try manager.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard value.isDirectory == true, value.isSymbolicLink != true else {
            throw LanguageServiceFailure("Codex 私有存储目录不可用或为符号链接")
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}

/// The application and explicit setup utility must never hold independent
/// writable snapshots for one project. Do not unlink this persistent lock file.
private final class CodexStoreLease: @unchecked Sendable {
    private let descriptor: Int32
    init(directory: URL, name: String = ".owner.lock") throws {
        let path = directory.appendingPathComponent(name).path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LanguageServiceFailure("无法取得 Codex 私有存储租约") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw LanguageServiceFailure("此项目的 Codex 正由另一个 HyCode 窗口或配置任务使用，请在该任务结束后重试")
        }
        self.descriptor = descriptor
    }
    deinit { close(descriptor) }
}
