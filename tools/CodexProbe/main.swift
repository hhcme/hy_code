import Darwin
import Foundation
import HyCodeWorkspace

actor Transcript {
    var conversation: CodexConversation
    private(set) var contextWindow: Int?
    init(_ value: CodexConversation) { conversation = value }
    func receive(_ event: JSONValue) throws {
        if event["method"].string == "thread/tokenUsage/updated" {
            contextWindow = event["params"]["tokenUsage"]["modelContextWindow"].int
        }
        try conversation.receive(event)
    }
    func snapshot() -> CodexConversation { conversation }
}

@main struct HyCodeCodexProbe {
    static func main() async {
        do { try await perform() } catch {
            FileHandle.standardError.write(Data(("Codex probe failed: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func perform() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw LanguageServiceFailure("Usage: HyCodeCodexProbe /path/to/codex /path/to/codex_provider.py")
        }
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("HyCodeCodexProbe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("generated fixture\n".utf8).write(to: root.appendingPathComponent("sample.txt"))
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [CommandLine.arguments[2], directory.path]
        server.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer {
            if server.isRunning { server.terminate() }
            server.waitUntilExit()
        }
        let portFile = directory.appendingPathComponent("port")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: portFile.path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let port = try String(contentsOf: portFile, encoding: .utf8)
        var settings = CodexConfiguration.deepSeek()
        settings.baseURL = "http://127.0.0.1:\(port)/v1"
        let configuration = settings
        let store = CodexStore(directory: directory.appendingPathComponent("private/project"))
        let executable = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        var a = CodexConversation(configuration: configuration)
        var b = CodexConversation(configuration: configuration)
        try a.addUserMessage("Reply with the fixture response. Do not call any tools.")
        try b.addUserMessage("An independent conversation. Do not call any tools.")
        async let first = execute(a, root: root, store: store, executable: executable, configuration: configuration)
        async let second = execute(b, root: root, store: store, executable: executable, configuration: configuration)
        let pair = try await (first, second)
        var completedA = pair.0
        let completedB = pair.1
        guard completedA.threadID != completedB.threadID else { throw LanguageServiceFailure("Threads collided") }
        let originalThread = completedA.threadID
        try completedA.addUserMessage("Continue this conversation. Do not call any tools.")
        var smallerContext = configuration
        smallerContext.contextWindow = 131_072
        completedA.contextWindow = smallerContext.contextWindow
        completedA = try await execute(
            completedA, root: root, store: store, executable: executable, configuration: smallerContext)
        guard completedA.threadID == originalThread else {
            throw LanguageServiceFailure("Thread resumption lost identity")
        }
        var writer = CodexConversation(configuration: configuration)
        writer.mode = .workspaceWrite
        try writer.addUserMessage("HYCODE_TOOL_PROBE: use the fixed fixture command, then reply.")
        _ = try await execute(writer, root: root, store: store, executable: executable, configuration: configuration)
        guard try String(contentsOf: root.appendingPathComponent("owned-by-agent.txt"), encoding: .utf8) == "wrote"
        else {
            throw LanguageServiceFailure("Real runtime did not execute the controlled project command")
        }
        var cancelled = CodexConversation(configuration: configuration)
        cancelled.mode = .workspaceWrite
        try cancelled.addUserMessage("HYCODE_CANCEL_PROBE: start the fixed fixture command.")
        let cancelledHome = try await store.runtimeHome(cancelled.id, root: root)
        let cancelledRun = CodexAgentRun()
        let interrupted = Task {
            try await cancelledRun.run(
                executable: executable, root: root, home: cancelledHome, configuration: configuration,
                apiKey: "hycode-fixture-only", conversation: cancelled
            ) { _ in }
        }
        let pidFile = root.appendingPathComponent("owned-shell.pid")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8)), pid > 1 else {
            await cancelledRun.stop()
            _ = try? await interrupted.value
            throw LanguageServiceFailure("Controlled command did not start")
        }
        let stopStart = ContinuousClock.now
        await cancelledRun.stop()
        _ = try? await interrupted.value
        for _ in 0..<20 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard kill(pid, 0) != 0, stopStart.duration(to: .now) < .seconds(5),
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("late-marker").path)
        else { throw LanguageServiceFailure("Controlled command was not stopped and reaped") }
        let requests = try String(contentsOf: directory.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        let records = try requests.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let toolOutputs = try records.flatMap { $0["input"].array }
            .filter { $0["type"].string == "function_call_output" }
            .map { String(decoding: try JSONEncoder().encode($0["output"]), as: UTF8.self) }
        guard (6...8).contains(records.count),
            records.allSatisfy({
                $0["authorizationOK"] == .bool(true) && $0["model"].string == "deepseek-v4-pro"
                    && $0["reasoning"]["effort"].string == "max"
                    && $0["hycodeReplyPolicy"] == .bool(true)
            }),
            toolOutputs.contains(where: { $0.contains("HYCODE_TOOL_PROBE") && $0.contains("HYCODE_ENV_OK") }),
            !toolOutputs.contains(where: { $0.contains("ENV_LEAK") || $0.contains("sandbox_apply") })
        else {
            throw LanguageServiceFailure("Provider route, authentication or reply policy did not match fixture")
        }
        print(
            "PASS: official Codex runtime; HyCode reply policy and max reasoning on wire, 1M context and resumed 128K override; two concurrent conversations, streamed responses, cross-process resume, real fixed command/write and command cancellation; \(requests.count) loopback-only model requests"
        )
        print("No real provider, account, user project, GUI, clipboard, player or global configuration used.")
    }
    static func execute(
        _ conversation: CodexConversation, root: URL, store: CodexStore, executable: URL,
        configuration: CodexConfiguration
    ) async throws -> CodexConversation {
        let home = try await store.runtimeHome(conversation.id, root: root)
        let transcript = Transcript(conversation)
        let run = CodexAgentRun()
        _ = try await run.run(
            executable: executable, root: root, home: home, configuration: configuration,
            apiKey: "hycode-fixture-only", conversation: conversation
        ) { event in
            try await transcript.receive(event)
        }
        let result = await transcript.snapshot()
        let reportedContext = await transcript.contextWindow
        guard result.messages.last(where: { $0.role == .assistant })?.text == "HYCODE_CODEX_PROBE_OK",
            result.threadID != nil, reportedContext == configuration.contextWindow.map({ $0 * 95 / 100 })
        else { throw LanguageServiceFailure("Real runtime response did not match fixture") }
        return result
    }
}
