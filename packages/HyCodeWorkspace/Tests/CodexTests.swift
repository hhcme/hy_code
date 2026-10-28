import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized)
struct CodexTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("HyCodeCodexTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func config() -> CodexConfiguration {
        var value = CodexConfiguration()
        value.baseURL = "http://127.0.0.1:12345/v1"
        value.model = "fixture-model"
        return value
    }
    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "tools/fixtures/codex_adapter.py")
    }
    private func connection() async throws -> CodexJSONLConnection {
        let value = CodexJSONLConnection()
        try await value.start(
            executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture().path],
            directory: FileManager.default.temporaryDirectory,
            environment: ["PATH": "/usr/bin:/bin", "HYCODE_FIXTURE": "isolated"])
        return value
    }
    @Test func customSettingsDoNotImportEnvironmentOrPutCredentialsOnTheCommandLine() throws {
        let home = URL(fileURLWithPath: "/tmp/HyCodeOwnRuntime")
        let arguments = try config().arguments(home: home)
        let environment = try config().environment(home: home, apiKey: "fixture-only-value")
        #expect(environment["CODEX_HOME"] == home.path)
        #expect(environment["OPENAI_API_KEY"] == nil)
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["NODE_OPTIONS"] == nil)
        #expect(environment["HTTP_PROXY"] == nil)
        #expect(!arguments.joined().contains("fixture-only-value"))
        #expect(arguments.contains("model_provider=\"hycode\""))
        #expect(arguments.contains("model_providers.hycode.base_url=\"http://127.0.0.1:12345/v1\""))
        var invalid = config()
        invalid.baseURL = "https://name:password@example.com/v1"
        #expect(throws: LanguageServiceFailure.self) { try invalid.validated() }
        invalid.baseURL = "http://example.com/v1"
        #expect(throws: LanguageServiceFailure.self) { try invalid.validated() }
        invalid.baseURL = "https://example.com/v1?token=value"
        #expect(throws: LanguageServiceFailure.self) { try invalid.validated() }
    }
    @Test func conversationsKeepTheirOwnStreamDraftModelAndHistory() throws {
        var first = CodexConversation(configuration: config())
        var second = CodexConversation(configuration: config())
        second.draft = "另一个对话的草稿"
        second.model = "other-model"
        try first.addUserMessage("解释这个项目")
        try first.receive(JSONValue(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "你"]]))
        try first.receive(JSONValue(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "好"]]))
        try first.receive(
            JSONValue([
                "method": "item/completed", "params": ["item": ["id": "a", "type": "agentMessage", "text": "你好"]],
            ]))
        #expect(first.messages.count == 2)
        #expect(first.messages.last?.text == "你好")
        #expect(second.messages.isEmpty)
        #expect(second.draft == "另一个对话的草稿")
        #expect(second.model == "other-model")
        #expect(throws: LanguageServiceFailure.self) { try first.addUserMessage(String(repeating: "x", count: 65_537)) }
    }
    @Test func deepSeekMaximumDefaultsAreRealMetadataAndContextOverridesStayBounded() throws {
        var value = CodexConfiguration.deepSeek()
        #expect(value.model == "deepseek-v4-pro")
        #expect(value.effort == "max")
        #expect(value.contextWindow == 1_048_576)
        let root = URL(fileURLWithPath: "/fixture/project")
        let previousAccount = value.credentialAccount(root: root)
        value.credentialID = UUID()
        #expect(value.credentialAccount(root: root) != previousAccount)
        let restored = try JSONDecoder().decode(CodexConfiguration.self, from: JSONEncoder().encode(value))
        #expect(restored.credentialID == value.credentialID)
        #expect(restored.credentialAccount(root: root) == value.credentialAccount(root: root))
        let arguments = try value.arguments(home: URL(fileURLWithPath: "/tmp/HyCodeOwnRuntime"))
        #expect(arguments.contains("model_reasoning_effort=\"max\""))
        #expect(arguments.contains("model_context_window=1048576"))
        #expect(arguments.contains("model_catalog_json=\"/tmp/HyCodeOwnRuntime/models.json\""))
        let catalog = try JSONDecoder().decode(JSONValue.self, from: CodexModelCatalog.deepSeekData())
        #expect(Set(catalog["models"].array.compactMap { $0["slug"].string }) == Set(CodexModelCatalog.deepSeekModels))
        #expect(
            catalog["models"].array.allSatisfy { model in
                model["context_window"].int == 1_048_576 && model["max_context_window"].int == 1_048_576
                    && model["supported_reasoning_levels"].array.contains { $0["effort"].string == "max" }
                    && model["model_messages"]["instructions_template"].string?.contains("HyCode") == true
            })
        value.contextWindow = 1_048_577
        #expect(throws: LanguageServiceFailure.self) { try value.validated() }
        value.contextWindow = 8_191
        #expect(throws: LanguageServiceFailure.self) { try value.validated() }
        value.contextWindow = 131_072
        #expect(try value.validated().contextWindow == 131_072)
        var first = CodexConversation(configuration: .deepSeek())
        let second = CodexConversation(configuration: .deepSeek())
        first.contextWindow = 65_536
        first.effort = "low"
        #expect(second.contextWindow == 1_048_576 && second.effort == "max")
    }
    @Test func versionOneHistoryWithoutContextFieldsStillLoadsAndPreservesPreviousChoices() throws {
        let previousConfig = Data(
            #"{"baseURL":"https://api.example.com/v1","model":"existing","effort":"medium"}"#.utf8)
        let configuration = try JSONDecoder().decode(CodexConfiguration.self, from: previousConfig)
        #expect(configuration.contextWindow == nil && configuration.effort == "medium")
        var conversation = CodexConversation(configuration: configuration)
        conversation.threadID = "preserved-thread"
        conversation.draft = "preserved input"
        let encoded = try JSONEncoder().encode(conversation)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["contextWindow"] = nil
        let restored = try JSONDecoder().decode(
            CodexConversation.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.id == conversation.id && restored.threadID == conversation.threadID)
        #expect(restored.contextWindow == nil && restored.draft == "preserved input" && restored.effort == "medium")
    }
    @Test func admissionBoundsConcurrencyAndKeepsWritingExclusive() throws {
        var value = CodexRunAdmission()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        try value.begin(a, mode: .readOnly)
        try value.begin(b, mode: .readOnly)
        #expect(throws: LanguageServiceFailure.self) { try value.begin(c, mode: .readOnly) }
        value.finish(a)
        #expect(throws: LanguageServiceFailure.self) { try value.begin(c, mode: .workspaceWrite) }
        value.finish(b)
        try value.begin(c, mode: .workspaceWrite)
        #expect(throws: LanguageServiceFailure.self) { try value.begin(a, mode: .readOnly) }
        value.finish(c)
        try value.begin(a, mode: .readOnly)
    }
    @Test func rejectedBudgetsKeepThePreviousUsableHistoryAndSplitSecretsStayRedacted() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexStore(directory: root.appendingPathComponent("projects/example"))
        var state = CodexProjectState()
        state.conversations = [CodexConversation(configuration: config())]
        try await store.save(state)
        state.conversations[0].draft = String(repeating: "x", count: 65_537)
        await #expect(throws: LanguageServiceFailure.self) { try await store.save(state) }
        #expect(try await store.load().conversations[0].draft == "")
        var conversation = CodexConversation(configuration: config())
        let secret = "fixture-secret-value"
        try conversation.receive(
            JSONValue(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "fixture-secret-"]]),
            redacting: secret)
        try conversation.receive(
            JSONValue(["method": "item/agentMessage/delta", "params": ["itemId": "a", "delta": "value"]]),
            redacting: secret)
        #expect(conversation.messages.last?.text == "[已隐藏密钥]")
        let previous = conversation.messages
        #expect(throws: LanguageServiceFailure.self) {
            try conversation.receive(
                JSONValue([
                    "method": "item/agentMessage/delta",
                    "params": ["itemId": "a", "delta": String(repeating: "x", count: 262_145)],
                ]))
        }
        #expect(conversation.messages == previous)
        conversation.messages = (0..<256).map { CodexMessage(role: .system, text: "message-\($0)") }
        let maximum = conversation.messages
        #expect(throws: LanguageServiceFailure.self) {
            try conversation.receive(
                JSONValue(["method": "item/agentMessage/delta", "params": ["itemId": "new", "delta": "excess"]]))
        }
        #expect(conversation.messages == maximum)
    }
    @Test func projectStoreRestoresConversationsWithoutCredentialsAndRejectsSymlinks() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CodexStore(directory: root.appendingPathComponent("projects/example"))
        var state = CodexProjectState()
        state.configuration = config()
        var conversation = CodexConversation(configuration: config())
        conversation.draft = "中文和 emoji 👨‍👩‍👧‍👦"
        conversation.threadID = "thread-fixture"
        state.conversations = [conversation]
        state.selectedID = conversation.id
        try await store.save(state)
        let restored = try await store.load()
        #expect(restored.conversations == state.conversations)
        #expect(restored.selectedID == conversation.id)
        let home = try await store.runtimeHome(conversation.id, root: root)
        #expect(home.path.contains(conversation.id.uuidString))
        let attributes = try FileManager.default.attributesOfItem(atPath: home.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o700)
        let path = root.appendingPathComponent("projects/example/state.json")
        try FileManager.default.removeItem(at: path)
        let outside = root.appendingPathComponent("canary")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
        await #expect(throws: LanguageServiceFailure.self) { try await store.save(state) }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
    }
    @Test func projectStateHasOneCrossProcessOwnerAndReleasesItsLease() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("projects/example")
        var first: CodexStore? = CodexStore(directory: directory)
        _ = try await first?.load()
        let second = CodexStore(directory: directory)
        await #expect(throws: LanguageServiceFailure.self) { try await second.load() }
        // A separately launched process must observe the same kernel lease.
        let contender = CodexJSONLConnection()
        try await contender.start(
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [
                "-c",
                """
                import fcntl, sys
                with open(sys.argv[1], 'r+') as stream:
                    try:
                        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        sys.exit(2)
                    except BlockingIOError:
                        print('{"jsonrpc":"2.0","method":"locked"}', flush=True)
                """, directory.appendingPathComponent(".owner.lock").path,
            ], directory: root, environment: ["PATH": "/usr/bin:/bin"])
        var events = contender.events.makeAsyncIterator()
        #expect(await events.next()?["method"].string == "locked")
        await contender.stop()
        first = nil
        _ = try await second.load()
    }
    @Test func setupHandoffPreservesAnActiveSnapshotAndItsLateWritesUntilTheNextOpen() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("projects/example")
        var active: CodexStore? = CodexStore(directory: directory)
        var state = CodexProjectState()
        state.configuration = config()
        var original = CodexConversation(configuration: config())
        original.draft = "Keep unsent work"
        original.threadID = "existing-thread"
        state.conversations = [original]
        state.selectedID = original.id
        try await active?.save(state)
        let setup = CodexStore(directory: directory)
        try await setup.stageConfiguration(.deepSeek())
        #expect(try await setup.configurationSnapshot() == .deepSeek())
        let before = try Data(contentsOf: directory.appendingPathComponent("state.json"))
        #expect(try JSONDecoder().decode(CodexProjectState.self, from: before).configuration == config())
        // Reproduces an older application's whole-snapshot persist at close.
        state.conversations[0].draft = "Newer input from the still-running app"
        try await active?.save(state)
        active = nil
        let restored = try await setup.load()
        #expect(restored.configuration == .deepSeek())
        #expect(restored.conversations.first(where: { $0.id == original.id })?.draft == state.conversations[0].draft)
        #expect(restored.conversations.first(where: { $0.id == original.id })?.threadID == "existing-thread")
        #expect(restored.conversations.count == 2 && restored.selectedID != original.id)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("provider-setup.json").path))
        #expect(try await setup.load().conversations == restored.conversations)
    }
    @Test func jsonlSupportsConcurrentRequestsAndReverseMessagesWithoutEnvironmentLeakage() async throws {
        let value = try await connection()
        async let first = value.request("echo", params: .string("中文"))
        async let second = value.request("echo", params: .string("second"))
        #expect(try await first == .string("中文"))
        #expect(try await second == .string("second"))
        let environment = try await value.request(
            "environment", params: JSONValue(["HYCODE_FIXTURE", "NODE_OPTIONS", "OPENAI_API_KEY"]))
        #expect(environment["HYCODE_FIXTURE"].string == "isolated")
        #expect(environment["NODE_OPTIONS"] == .null)
        #expect(environment["OPENAI_API_KEY"] == .null)
        _ = try await value.request("reverse", params: .null)
        var iterator = value.events.makeAsyncIterator()
        let approval = await iterator.next()
        #expect(approval?["id"].string == "approval-fixture")
        try await value.respond(id: .string("approval-fixture"), result: JSONValue(["decision": "decline"]))
        await value.stop()
    }
    @Test func malformedAndOversizedFramesCloseTheConnection() async throws {
        for method in ["broken", "oversized"] {
            let value = try await connection()
            await #expect(throws: LanguageServiceFailure.self) { try await value.request(method, params: .null) }
            await value.stop()
        }
    }
    @Test func cancellationIsBoundedAndAStoppedConnectionCannotRestart() async throws {
        let value = try await connection()
        let task = Task { try await value.request("wait", params: .null) }
        try await Task.sleep(for: .milliseconds(80))
        let start = ContinuousClock.now
        await value.stop()
        _ = try? await task.value
        #expect(start.duration(to: .now) < .seconds(3))
        await #expect(throws: LanguageServiceFailure.self) {
            try await value.start(
                executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                directory: FileManager.default.temporaryDirectory, environment: [:])
        }
    }
    @Test func stoppingOneConversationDoesNotStopAnotherTransport() async throws {
        let first = try await connection()
        let second = try await connection()
        let pending = Task { try await first.request("wait", params: .null) }
        await first.stop()
        _ = try? await pending.value
        #expect(try await second.request("echo", params: .string("still running")) == .string("still running"))
        await second.stop()
    }
    @Test func outerSandboxRestrictsReadsAndKeepsReadOnlyAndWritingModesSeparate() async throws {
        let directory = try temporary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("project")
        let outside = directory.appendingPathComponent("outside")
        let home = directory.appendingPathComponent("home")
        let runtime = directory.appendingPathComponent("runtime")
        for path in [root, outside, home, runtime] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        let source = root.appendingPathComponent("inside")
        let canary = outside.appendingPathComponent("canary")
        try Data("outside".utf8).write(to: canary)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        for mode in CodexAccessMode.allCases {
            try Data("inside".utf8).write(to: source)
            let policy = try CodexSandbox.policy(runtime: runtime, root: root, home: home, mode: mode)
            let runner = DeveloperToolTask()
            let script = """
                cat "$1/inside"
                if cat "$2/canary" >/dev/null 2>&1; then printf ESCAPED; else printf DENIED; fi
                if cat "$1/link/canary" >/dev/null 2>&1; then printf ESCAPED_LINK; else printf LINK_DENIED; fi
                if (printf bad > "$2/canary") 2>/dev/null; then printf ESCAPED_WRITE; fi
                if (printf changed > "$1/inside") 2>/dev/null; then printf WRITE; else printf READ_ONLY; fi
                """
            let result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: ["-p", policy, "/bin/sh", "-c", script, "probe", root.path, outside.path],
                directory: root
            ) { _ in }
            #expect(result.exitCode == 0)
            #expect(result.stdout == "insideDENIEDLINK_DENIED" + (mode == .readOnly ? "READ_ONLY" : "WRITE"))
            #expect(try String(contentsOf: canary, encoding: .utf8) == "outside")
            #expect(try String(contentsOf: source, encoding: .utf8) == (mode == .readOnly ? "inside" : "changed"))
        }
    }
}
