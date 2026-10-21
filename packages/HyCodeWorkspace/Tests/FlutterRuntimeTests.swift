import Foundation
import Testing

@testable import HyCodeWorkspace

struct FlutterRuntimeTests {
    @Test func launchArgumentsAreLiteralBoundedAndDoNotImplicitlyRunPub() throws {
        var config = FlutterLaunchConfiguration()
        config.deviceID = "macos"
        config.flavor = "demo"
        config.defines = ["MESSAGE=$(echo unsafe); `echo unsafe` 中文"]
        let args = try config.launchArguments(root: URL(fileURLWithPath: "/tmp/sample"), debug: true)
        #expect(args["noDebug"] == .bool(false))
        #expect(args["toolArgs"].array.contains(.string("--no-pub")))
        #expect(args["toolArgs"].array.contains(.string("--dart-define=" + config.defines[0])))
        #expect(args["program"].string == "/tmp/sample/lib/main.dart")
        #expect(args["evaluateGettersInDebugViews"] == .bool(false))
        config.mode = .profile
        #expect(
            try config.launchArguments(root: URL(fileURLWithPath: "/tmp/sample"), debug: true)["noDebug"] == .bool(true)
        )
        for value in ["/tmp/main.dart", "../main.dart", "lib/../main.dart", "main.txt", "bad\0.dart"] {
            config.program = value
            #expect(throws: LanguageServiceFailure.self) { try config.validate() }
        }
        config.program = "lib/main.dart"
        config.defines = ["=bad"]
        #expect(throws: LanguageServiceFailure.self) { try config.validate() }
    }
    @Test func devicesAreDeduplicatedFilteredAndDoNotCreateFakeTargets() throws {
        let text =
            #"[{"id":"macos","name":"Mac","targetPlatform":"darwin-arm64","emulator":false},{"id":"macos"},{"id":"old","isSupported":false},{"name":"missing id"}]"#
        let result = try FlutterDevice.parse(text)
        #expect(
            result.count == 1 && result[0].id == "macos" && result[0].platform == "darwin-arm64" && !result[0].emulator)
        #expect(throws: LanguageServiceFailure.self) { try FlutterDevice.parse("warning: not JSON") }
        #expect(throws: LanguageServiceFailure.self) { try FlutterDevice.parse("{}") }
    }
    @Test func stopEpochInvalidatesFramesAndLateEventsCannotResumeEndedSession() {
        var state = FlutterDebugState()
        state.start()
        let start = state.epoch
        state.receive(JSONValue(["event": "stopped", "body": ["threadId": 9]]))
        #expect(state.phase == .paused && state.threadID == 9 && state.epoch > start)
        let pause = state.epoch
        state.receive(JSONValue(["event": "continued"]))
        #expect(state.phase == .running && state.threadID == nil && state.epoch > pause)
        state.receive(JSONValue(["event": "dart.debuggerUris", "body": ["vmServiceUri": "file:///tmp/bad"]]))
        #expect(state.vmServiceURI.isEmpty)
        state.receive(
            JSONValue(["event": "dart.debuggerUris", "body": ["vmServiceUri": "ws://127.0.0.1:1234/token=/ws"]]))
        #expect(!state.vmServiceURI.isEmpty)
        state.stopping()
        state.receive(JSONValue(["event": "continued"]))
        #expect(state.phase == .stopping && state.vmServiceURI.isEmpty)
        state.receive(JSONValue(["event": "terminated"]))
        state.receive(JSONValue(["event": "stopped", "body": ["threadId": 1]]))
        #expect(state.phase == .ended && state.threadID == nil)
        let ended = state.epoch
        state.start()
        #expect(state.epoch > ended)
    }
    @Test func conditionalLogBreakpointsAndRelocationPreserveOneLineOwner() {
        var value = FlutterBreakpoint(line: 2)
        value.condition = "count > 3"
        value.logMessage = "count={count}"
        #expect(value.dap["line"].int == 2 && value.dap["condition"].string == "count > 3")
        #expect(FlutterBreakpoint(line: 1).dap["condition"] == .null)
        let range = LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 0))
        let shifted = FlutterBreakpoint.relocate([value], range: range, text: "😀\r\n")
        #expect(shifted.first?.line == 3 && shifted.first?.condition == value.condition)
        let deleted = LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 3, character: 0))
        #expect(FlutterBreakpoint.relocate([FlutterBreakpoint(line: 1), value], range: deleted, text: "").count == 1)
    }
    @Test func testReporterHandlesChunksNoiseFailuresAndOversizedLines() {
        var reporter = FlutterTestResults()
        let text =
            "noise\n" + #"{"type":"testStart","test":{"id":1,"name":"中文 😀"}}"# + "\n"
            + #"{"type":"error","testID":1,"error":"expected failure"}"# + "\n"
            + #"{"type":"testDone","testID":1,"result":"error","skipped":false}"# + "\n"
            + #"{"type":"done","success":false}"# + "\n"
        for char in text { reporter.append(String(char)) }
        #expect(reporter.done && !reporter.success && reporter.items[1]?.status == "失败")
        #expect(reporter.items[1]?.name == "中文 😀" && reporter.items[1]?.error == "expected failure")
        reporter.append(String(repeating: "x", count: 70_000) + "\n" + #"{"type":"done","success":true}"# + "\n")
        #expect(reporter.limited && reporter.success)
        for id in 2...1_100 { reporter.receive(JSONValue(["type": "testStart", "test": ["id": id, "name": "test"]])) }
        #expect(reporter.items.count == 1_000)
    }
    @Test func inspectorProjectsSafeCreationLocationsAndCapsTreeDepth() {
        let generation = UUID()
        let input = JSONValue([
            "result": [
                "description": "Root", "valueId": "widget-1",
                "creationLocation": ["file": "file:///tmp/sample.dart", "line": 3, "column": 2],
                "children": [["description": "Child"]],
            ]
        ])
        let result = FlutterInspectorTree.rows(input, generation: generation)
        #expect(result[0].generation == generation)
        #expect(result.count == 2 && result[1].depth == 1 && result[0].valueID == "widget-1")
        #expect(result[0].source?.range.start == LSPPosition(line: 2, character: 1))
        #expect(
            FlutterInspectorTree.rows(
                JSONValue([
                    "description": "Root", "creationLocation": ["file": "https://invalid.test/code", "line": 1],
                ])
            ).first?.source == nil)
    }
    @Test func unsavedBreakpointProjectionDiscardsAndPartialSaveKeepsTheDiskBaseline() {
        let path = "/fixture/main.dart"
        let point = FlutterBreakpoint(line: 4)
        var store = FlutterBreakpointStore(saved: [path: [point]])
        let insert = LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 0))
        store.edit(path: path, range: insert, text: "\n")
        #expect(
            store.projected[path]?.first?.line == 5 && store.persisted[path]?.first?.line == 4
                && store.dirty.contains(path))
        let snapshot = store.projected[path] ?? []
        store.edit(path: path, range: insert, text: "\n")
        store.saved(path: path, snapshot: snapshot, clean: false)
        #expect(
            store.projected[path]?.first?.line == 6 && store.persisted[path]?.first?.line == 5
                && store.dirty.contains(path))
        store.discard(path: path)
        #expect(store.projected[path]?.first?.line == 5 && !store.dirty.contains(path))
        let deletion = LSPRange(start: LSPPosition(line: 1, character: 0), end: LSPPosition(line: 3, character: 0))
        #expect(FlutterBreakpoint.relocate([point], range: deletion, text: "X\n").first?.line == 3)
    }
    @Test func breakpointConfirmationCanArriveBeforeTheResponseAndRemovedEventsClearIt() {
        var state = FlutterBreakpointResolution()
        let changed = JSONValue(["body": ["reason": "changed", "breakpoint": ["id": 7, "line": 5, "verified": true]]])
        state.receive(changed)
        state.response(
            path: "/fixture/main.dart", requested: [FlutterBreakpoint(line: 4)],
            result: JSONValue(["breakpoints": [["id": 7, "line": 4, "verified": false]]]))
        #expect(state.entries[7]?.requested == 4 && state.entries[7]?.actual == 5 && state.entries[7]?.verified == true)
        state.receive(JSONValue(["body": ["reason": "removed", "breakpoint": ["id": 7]]]))
        #expect(state.entries[7]?.verified == false)
        state.response(path: "/fixture/main.dart", requested: [], result: JSONValue(["breakpoints": []]))
        #expect(state.entries.isEmpty)
    }
}

@Suite(.serialized) struct FlutterDAPProcessTests {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "tools/fixtures/dap_adapter.py")
    }
    @Test func adjacentInitializeEventsWaitForCapabilitiesAndLaunchBeforeConfiguration() async throws {
        for options in [[], ["--fragment"]] {
            let session = FlutterDebugSession()
            do {
                try await session.start(
                    executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: [fixture.path] + options,
                    directory: FileManager.default.temporaryDirectory, launch: JSONValue(["program": "fixture-only"]),
                    breakpoints: ["/tmp/hycode-fixture.dart": [FlutterBreakpoint(line: 3)]])
                let status = try await session.request("fixtureStatus")
                #expect(status["configured"] == .bool(true) && status["filters"].array == [.string("Unhandled")])
                #expect(status["reverseDenied"] == .bool(true))
                let threads = try await session.request("threads")
                #expect(threads["threads"].array.first?["name"].string == "main 中")
                let stack = try await session.request("stackTrace", JSONValue(["threadId": 1]))
                #expect(stack["stackFrames"].array.first?["id"].int == 7)
                let scopes = try await session.request("scopes", JSONValue(["frameId": 7]))
                let reference = try #require(scopes["scopes"].array.first?["variablesReference"].int)
                let variables = try await session.request("variables", JSONValue(["variablesReference": reference]))
                #expect(variables["variables"].array.first?["value"].string == "42")
                let evaluation = try await session.request("evaluate", JSONValue(["expression": "answer"]))
                #expect(evaluation["result"].string == "42")
                _ = try await session.request("hotReload")
                _ = try await session.request("hotRestart")
                await #expect(throws: LanguageServiceFailure.self) { try await session.request("fail") }
                await session.stop()
                var ended = false
                for await event in session.events {
                    if event["event"].string == "hycode/disconnected" || event["event"].string == "terminated" {
                        ended = true
                    }
                }
                #expect(ended)
            } catch {
                await session.stop()
                throw error
            }
        }
    }
    @Test func stalledDAPWriterStillTimesOutAndReclaimsTheChild() async throws {
        let connection = StdioProtocolConnection(wire: .debugAdapter)
        try await connection.start(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
            directory: FileManager.default.temporaryDirectory)
        let began = ContinuousClock.now
        await #expect(throws: LanguageServiceFailure.self) {
            try await connection.request(
                "blocked", params: .string(String(repeating: "x", count: 1_000_000)), timeout: 1)
        }
        await connection.stop()
        #expect(began.duration(to: .now) < .seconds(6))
        await #expect(throws: LanguageServiceFailure.self) { try await connection.request("late", params: .null) }
    }
}
