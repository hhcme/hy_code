import CryptoKit
import Foundation

public enum CodexAccessMode: String, Codable, CaseIterable, Sendable {
    case readOnly, workspaceWrite
}

public enum CodexCredentialScope: String, Codable, Sendable {
    case project, application
}

/// Contains no credential. Provider settings belong to HyCode, never the repository
/// or the user's global Codex configuration. Each conversation owns its runtime home.
public struct CodexConfiguration: Codable, Equatable, Sendable {
    public var baseURL = ""
    public var model = ""
    public var effort = "max"
    public var contextWindow: Int?
    public var credentialID: UUID?
    public var credentialScope: CodexCredentialScope = .project
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case baseURL, model, effort, contextWindow, credentialID, credentialScope
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        effort = try values.decodeIfPresent(String.self, forKey: .effort) ?? "max"
        contextWindow = try values.decodeIfPresent(Int.self, forKey: .contextWindow)
        credentialID = try values.decodeIfPresent(UUID.self, forKey: .credentialID)
        credentialScope = try values.decodeIfPresent(CodexCredentialScope.self, forKey: .credentialScope) ?? .project
    }

    public static func deepSeek(model: String = "deepseek-v4-pro") -> Self {
        var value = Self()
        value.baseURL = "https://api.deepseek.com"
        value.model = model
        value.contextWindow = CodexModelCatalog.deepSeekContextWindow
        return value
    }

    public var isDeepSeekModel: Bool { CodexModelCatalog.deepSeekModels.contains(model) }
    public var supportedEfforts: [String] {
        isDeepSeekModel
            ? ["none", "low", "high", "max"] : ["none", "minimal", "low", "medium", "high", "xhigh", "max"]
    }

    public func validated() throws -> Self {
        var value = self
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: value.baseURL),
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil,
            url.scheme == "https"
                || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)),
            value.baseURL.utf8.count <= 2_048,
            !value.model.isEmpty, value.model.utf8.count <= 200,
            !value.model.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            ["none", "minimal", "low", "medium", "high", "xhigh", "max"].contains(value.effort)
        else { throw LanguageServiceFailure("请填写有效的 HTTPS Responses API 地址、模型和思考强度；本机接口允许 HTTP") }
        if let limit = value.contextWindow {
            let maximum = value.isDeepSeekModel ? CodexModelCatalog.deepSeekContextWindow : 16_777_216
            guard (8_192...maximum).contains(limit) else {
                throw LanguageServiceFailure("上下文应为 8192 至 \(maximum) tokens；不能超过模型服务支持的范围")
            }
        }
        return value
    }

    public static func workspaceKey(_ root: URL) -> String {
        SHA256.hash(data: Data(root.resolvingSymlinksInPath().standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    public func credentialAccount(root: URL) -> String {
        let provider = SHA256.hash(data: Data(baseURL.utf8)).map { String(format: "%02x", $0) }.joined()
        let owner = credentialScope == .application ? "hycode-default" : Self.workspaceKey(root)
        return owner + ":" + provider + (credentialID.map { ":" + $0.uuidString } ?? "")
    }

    public func arguments(home: URL) throws -> [String] {
        let value = try validated()
        func literal(_ text: String) throws -> String { try CodexWireLiteral.string(text) }
        var overrides = try [
            "model_provider=\"hycode\"", "model=" + literal(value.model),
            "model_reasoning_effort=" + literal(value.effort),
            "model_providers.hycode.name=\"HyCode Custom\"",
            "model_providers.hycode.base_url=" + literal(value.baseURL),
            "model_providers.hycode.env_key=\"HYCODE_CODEX_API_KEY\"",
            "model_providers.hycode.requires_openai_auth=false",
            "model_providers.hycode.wire_api=\"responses\"",
            "model_providers.hycode.supports_websockets=false",
            "cli_auth_credentials_store=\"ephemeral\"", "web_search=\"disabled\"",
            "approvals_reviewer=\"user\"", "analytics.enabled=false", "feedback.enabled=false",
            "features.multi_agent=false", "features.shell_snapshot=false",
            "shell_environment_policy.inherit=\"none\"",
            "shell_environment_policy.set.PATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"",
            "shell_environment_policy.set.HOME=" + literal(FileManager.default.homeDirectoryForCurrentUser.path),
            "shell_environment_policy.set.TMPDIR=" + literal(home.appendingPathComponent("tmp").path),
            "shell_environment_policy.set.LANG=\"en_US.UTF-8\"",
            "shell_environment_policy.set.SHELL=\"/bin/bash\"",
        ]
        if let limit = value.contextWindow { overrides.append("model_context_window=\(limit)") }
        if value.isDeepSeekModel {
            overrides.append("model_catalog_json=" + (try literal(home.appendingPathComponent("models.json").path)))
        }
        return ["app-server", "--listen", "stdio://"] + overrides.flatMap { ["-c", $0] }
    }

    public func environment(home: URL, apiKey: String) throws -> [String: String] {
        guard !apiKey.isEmpty, apiKey.utf8.count <= 16_384, !apiKey.contains("\0") else {
            throw LanguageServiceFailure("请先为当前项目保存 API Key")
        }
        return [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "SHELL": "/bin/bash",
            "LANG": "en_US.UTF-8", "TERM": "dumb", "CODEX_HOME": home.path,
            "TMPDIR": home.appendingPathComponent("tmp").path, "HYCODE_CODEX_API_KEY": apiKey,
            "SQLITE_TMPDIR": home.appendingPathComponent("tmp").path,
        ]
    }
}

enum CodexWireLiteral {
    static func string(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        // JSON's optional slash escaping is not a valid TOML/SBPL escape.
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
