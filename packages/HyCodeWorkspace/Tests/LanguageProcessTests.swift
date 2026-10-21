import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized) struct LanguageProcessTests {
    @Test func cancellingTheCallingTaskStopsItsOwnedToolGroup() async throws {
        let runner = DeveloperToolTask()
        let ready = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let operation = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'ready\\n'; exec sleep 30"],
                directory: FileManager.default.temporaryDirectory
            ) { _ in ready.continuation.yield(()) }
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            ready.continuation.finish()
            await runner.stop()
        }
        var received = false
        for await _ in ready.stream {
            received = true
            break
        }
        operation.cancel()
        let result = try await operation.value
        deadline.cancel()
        ready.continuation.finish()
        #expect(received && result.exitCode != 0)
    }
    @Test func toolCancellationReclaimsDescendantsHoldingOutputPipes() async throws {
        let runner = DeveloperToolTask()
        let ready = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let operation = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' INT TERM; sleep 30 & printf 'ready\\n'; wait"],
                directory: FileManager.default.temporaryDirectory
            ) { _ in ready.continuation.yield(()) }
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            ready.continuation.finish()
            await runner.stop()
        }
        var received = false
        for await _ in ready.stream {
            received = true
            break
        }
        let start = ContinuousClock.now
        await runner.stop()
        let result = try await operation.value
        deadline.cancel()
        ready.continuation.finish()
        #expect(received)
        #expect(result.exitCode != 0)
        #expect(start.duration(to: .now) < .seconds(7))
    }
    @Test func exitedToolDoesNotLeavePipeOwningWorkersBehind() async throws {
        let runner = DeveloperToolTask()
        let start = ContinuousClock.now
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 30 & printf 'done\\n'; exit 0"],
            directory: FileManager.default.temporaryDirectory
        ) { _ in }
        #expect(result.exitCode == 0)
        #expect(result.stdout == "done\n")
        #expect(start.duration(to: .now) < .seconds(6))
    }
    @Test func largeDuplexMessagesDoNotBlockTheProtocolActor() async throws {
        let connection = LanguageServerConnection()
        try await connection.start(
            executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
            directory: FileManager.default.temporaryDirectory)
        do {
            // cat echoes the client request as a server capability request. The
            // reply is echoed again as a response, exercising both pipe directions.
            let response = try await connection.request(
                "window/workDoneProgress/create", params: JSONValue(["token": String(repeating: "中", count: 300_000)]),
                timeout: 5)
            #expect(response == .null)
            await connection.stop()
        } catch {
            await connection.stop()
            throw error
        }
    }
    @Test func unresponsiveReaderStillAllowsTimeoutAndProcessShutdown() async throws {
        let connection = LanguageServerConnection()
        try await connection.start(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
            directory: FileManager.default.temporaryDirectory)
        let start = ContinuousClock.now
        do {
            _ = try await connection.request(
                "blocked", params: .string(String(repeating: "x", count: 1_000_000)), timeout: 1)
            Issue.record("Unresponsive child replied")
        } catch is LanguageServiceFailure {}
        await connection.stop()
        #expect(start.duration(to: .now) < .seconds(6))
    }
    @Test func stoppedOwnersCannotLaunchLateProcesses() async throws {
        let directory = FileManager.default.temporaryDirectory
        let connection = LanguageServerConnection()
        await connection.stop()
        do {
            try await connection.start(
                executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], directory: directory)
            Issue.record("Stopped connection restarted")
        } catch is LanguageServiceFailure {}
        let runner = DeveloperToolTask()
        await runner.stop()
        do {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], directory: directory)
            { _ in }
            Issue.record("Stopped tool started")
        } catch is CancellationError {}
    }
}
