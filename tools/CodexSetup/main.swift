import Darwin
import Foundation
import HyCodeWorkspace

/// Explicit headless setup, never an application host. Secrets enter via stdin
/// with terminal echo disabled, and are written only to HyCode's private local store.
@main struct HyCodeCodexSetup {
    static func main() async {
        do { try await perform() } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func perform() async throws {
        let arguments = CommandLine.arguments
        guard (3...4).contains(arguments.count),
            ["configure", "configure-default", "verify", "check-credentials", "check-default"].contains(arguments[1])
        else {
            throw LanguageServiceFailure(
                "Usage: HyCodeCodexSetup configure|configure-default|verify|check-credentials|check-default /project/root [/path/to/HyCode.app]"
            )
        }
        let root = URL(fileURLWithPath: arguments[2], isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
        guard (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw LanguageServiceFailure("项目目录无效")
        }
        // The optional legacy application argument is accepted for compatibility;
        // local credentials do not depend on an application signature or ACL.
        let defaults = ["configure-default", "check-default"].contains(arguments[1])
        let store = CodexStore(
            directory: defaults ? CodexStore.defaultsDirectory : CodexStore.projectDirectory(root: root))
        let credentials = CodexCredentials()
        if ["configure", "configure-default"].contains(arguments[1]) {
            var configuration = try CodexConfiguration.deepSeek().validated()
            configuration.credentialScope = defaults ? .application : .project
            let input = try readSecret()
            let secret: String
            if input.isEmpty {
                let current = try await store.configurationSnapshot()
                if current.baseURL == configuration.baseURL,
                    let stored = try await credentials.read(current.credentialAccount(root: root))
                {
                    secret = stored
                } else if !defaults,
                    let shared = try? await CodexStore(directory: CodexStore.defaultsDirectory).configurationSnapshot(),
                    shared.baseURL == configuration.baseURL,
                    let stored = try await credentials.read(shared.credentialAccount(root: root))
                {
                    secret = stored
                } else {
                    throw LanguageServiceFailure("本地没有可复用的 DeepSeek API Key，请重新输入")
                }
            } else {
                secret = input
            }
            configuration.credentialID = UUID()
            try await credentials.write(secret, account: configuration.credentialAccount(root: root))
            guard try await credentials.read(configuration.credentialAccount(root: root)) == secret else {
                throw LanguageServiceFailure("本地密钥保存后的读取验证失败")
            }
            try await store.stageConfiguration(configuration)
            print(
                "Configured: DeepSeek V4 Pro; reasoning=max; context=1048576 tokens. Local private credential write/read passed; key omitted."
            )
            print("Setup is staged for the next project open; an existing window's state was not overwritten.")
            print(
                defaults
                    ? "HyCode defaults are available to unconfigured projects; system Codex was not changed."
                    : "Only this HyCode project's private settings and local credential record were changed.")
        } else {
            let configuration = try await store.configurationSnapshot()
            guard configuration.baseURL == "https://api.deepseek.com", configuration.isDeepSeekModel,
                let secret = try await credentials.read(configuration.credentialAccount(root: root))
            else { throw LanguageServiceFailure("当前 HyCode 项目尚未配置 DeepSeek 凭据") }
            if ["check-credentials", "check-default"].contains(arguments[1]) {
                print(
                    "PASS: HyCode's private local credential is readable without system authentication; key omitted; no network request."
                )
            } else {
                try await verify(configuration: configuration, key: secret)
            }
        }
    }
    private static func readSecret() throws -> String {
        var original = termios()
        let terminal = isatty(STDIN_FILENO) == 1
        if terminal {
            guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw POSIXError(.EIO) }
            var hidden = original
            hidden.c_lflag &= ~tcflag_t(ECHO)
            guard tcsetattr(STDIN_FILENO, TCSANOW, &hidden) == 0 else { throw POSIXError(.EIO) }
        }
        defer { if terminal { _ = tcsetattr(STDIN_FILENO, TCSANOW, &original) } }
        FileHandle.standardOutput.write(
            Data("Waiting for API key on stdin (input hidden; empty line keeps an existing key)…\n".utf8))
        var data = Data()
        while data.count <= 16_384 {
            var byte: UInt8 = 0
            let count = Darwin.read(STDIN_FILENO, &byte, 1)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw LanguageServiceFailure("API Key 输入未完成") }
            if byte == 10 { break }
            data.append(byte)
        }
        guard data.count <= 16_384, let secret = String(data: data, encoding: .utf8),
            !secret.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw LanguageServiceFailure("API Key 输入无效") }
        return secret
    }
    private static func verify(configuration: CodexConfiguration, key: String) async throws {
        // A real model must never control a tool or process in a headless test.
        // The Codex tool loop is verified separately against the fixed fixture.
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 30
        options.timeoutIntervalForResource = 45
        options.httpCookieStorage = nil
        options.urlCredentialStorage = nil
        options.urlCache = nil
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model, "reasoning": ["effort": configuration.effort],
            "input": "只回复 HYCODE_DEEPSEEK_OK", "stream": true,
            "max_output_tokens": 512, "tools": [], "tool_choice": "none", "store": false,
        ])
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw LanguageServiceFailure("DeepSeek 未返回 HTTP 状态") }
            guard http.statusCode == 200 else {
                throw LanguageServiceFailure("DeepSeek 连通验证失败，HTTP \(http.statusCode)；请检查密钥、模型权限或余额")
            }
            var line = Data()
            var size = 0
            var deltas = 0
            var completed: JSONValue?
            for try await byte in bytes {
                size += 1
                guard size <= 262_144, line.count <= 65_536 else { throw LanguageServiceFailure("DeepSeek 验证输出超过预算") }
                if byte == 10 {
                    if let value = String(data: line, encoding: .utf8), value.hasPrefix("data:") {
                        let data = Data(value.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines).utf8)
                        let event = try JSONDecoder().decode(JSONValue.self, from: data)
                        if event["type"].string == "response.output_text.delta" { deltas += 1 }
                        if event["type"].string == "response.completed" { completed = event["response"] }
                        if ["response.failed", "response.incomplete"].contains(event["type"].string ?? "") {
                            throw LanguageServiceFailure("DeepSeek 验证未完成固定短回复")
                        }
                    }
                    line.removeAll(keepingCapacity: true)
                    if completed != nil { break }
                } else {
                    line.append(byte)
                }
            }
            guard let completed, completed["status"].string == "completed", deltas > 0 else {
                throw LanguageServiceFailure("DeepSeek 未返回完整的流式结果")
            }
            let messages = completed["output"].array.filter { $0["type"].string == "message" }
            let text = messages.flatMap { $0["content"].array }.compactMap { $0["text"].string }.joined()
            guard text.contains("HYCODE_DEEPSEEK_OK"),
                completed["output"].array.allSatisfy({ ["message", "reasoning"].contains($0["type"].string ?? "") })
            else { throw LanguageServiceFailure("DeepSeek 验证未返回固定标记或返回了工具项；没有执行任何工具") }
            print(
                "PASS: DeepSeek Responses API; HTTP 200; streamed fixed reply; model=\(configuration.model), reasoning=\(configuration.effort), inputTokens=\(completed["usage"]["input_tokens"].int ?? 0), outputTokens=\(completed["usage"]["output_tokens"].int ?? 0)."
            )
            print(
                "No tools offered or executed; fixed prompt only; no project files, GUI or system Codex settings used; key omitted."
            )
        } catch {
            throw LanguageServiceFailure(error.localizedDescription.replacingOccurrences(of: key, with: "[已隐藏密钥]"))
        }
    }
}
