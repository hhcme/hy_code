import Foundation
import HyCodeWorkspace

actor DebugProbeInbox {
    private var stopped = false
    private var ended = false
    func receive(_ event: JSONValue) {
        if let name = event["event"].string { print("DAP event: " + name) }
        if let output = event["body"]["output"].string {
            print(
                String(
                    output.replacingOccurrences(
                        of: #"[A-Za-z][A-Za-z0-9+.-]*://[^\s]+"#, with: "<local-service>", options: .regularExpression
                    ).prefix(2_000)))
        }
        if event["event"].string == "stopped" { stopped = true }
        if ["terminated", "hycode/disconnected"].contains(event["event"].string ?? "") { ended = true }
    }
    func reachedStop() -> Bool { stopped }
    func reachedEnd() -> Bool { ended }
}

/// Explicit SDK protocol probe. The only debuggee is a generated Dart console
/// script printing an integer; never a Flutter app, GUI, device or user project.
@main struct DebugProbe {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LanguageServiceFailure(message) }
    }
    static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw LanguageServiceFailure("Usage: HyCodeDebugProbe <explicit-sdk-root>")
        }
        let sdk = try DartToolchain.discover(configured: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            "hycode-debug-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("main.dart")
        let text = "void main() {\n  final answer = 42;\n  print(answer);\n}\n"
        try Data(text.utf8).write(to: file)
        let inbox = DebugProbeInbox()
        let session = FlutterDebugSession()
        let listener = Task { for await event in session.events { await inbox.receive(event) } }
        do {
            try await session.start(
                executable: sdk.dart, arguments: ["debug_adapter"], directory: root,
                launch: JSONValue([
                    "cwd": root.path, "program": file.path, "console": "internalConsole", "noDebug": false,
                    "customTool": sdk.dartSDK.appendingPathComponent("bin/dartvm").path,
                    "debugSdkLibraries": false, "evaluateGettersInDebugViews": false,
                    "evaluateToStringInDebugViews": false,
                ]),
                breakpoints: [file.path: [FlutterBreakpoint(line: 3)]])
            let began = ContinuousClock.now
            while !(await inbox.reachedStop()), !(await inbox.reachedEnd()), began.duration(to: .now) < .seconds(15) {
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(await inbox.reachedStop(), "Generated Dart console did not stop at its breakpoint")
            let threads = try await session.request("threads")
            guard let thread = threads["threads"].array.first?["id"].int else {
                throw LanguageServiceFailure("Missing thread")
            }
            let stack = try await session.request("stackTrace", JSONValue(["threadId": thread, "levels": 10]))
            guard let frame = stack["stackFrames"].array.first?["id"].int else {
                throw LanguageServiceFailure("Missing frame")
            }
            let result = try await session.request(
                "evaluate", JSONValue(["expression": "answer", "frameId": frame, "context": "watch"]))
            try require(result["result"].string == "42", "Unexpected expression value")
            let scopes = try await session.request("scopes", JSONValue(["frameId": frame]))
            try require(!scopes["scopes"].array.isEmpty, "Missing scopes")
            _ = try await session.request("continue", JSONValue(["threadId": thread]))
            let resumed = ContinuousClock.now
            while !(await inbox.reachedEnd()), resumed.duration(to: .now) < .seconds(10) {
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(await inbox.reachedEnd(), "Generated Dart console did not terminate")
            await session.stop()
            listener.cancel()
            try require(try String(contentsOf: file, encoding: .utf8) == text, "Fixture disk contents changed")
            print(
                "PASS: Dart \(sdk.dartVersion) DAP initialize/configuration, breakpoint, thread/stack/scopes, evaluation=42, continue/termination. Generated console script only; no Flutter, GUI, device, Pub or user project."
            )
        } catch {
            await session.stop()
            listener.cancel()
            throw error
        }
    }
}
