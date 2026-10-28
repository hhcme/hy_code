import Darwin
import Foundation
import SwiftTerm
import Testing

@testable import HyCodeWorkspace

struct TerminalModelTests {
    @Test func nestedSplitsCollapseWithoutLosingTheOtherSession() throws {
        var tab = TerminalTab(title: "server")
        let first = tab.activePane
        let secondResult = tab.split(.horizontal)
        let second = try #require(secondResult)
        let thirdResult = tab.split(.vertical)
        let third = try #require(thirdResult)
        #expect(tab.layout.panes == [first, second, third])
        let removedSecond = tab.remove(second)
        #expect(removedSecond)
        #expect(tab.layout.panes == [first, third])
        #expect(tab.activePane == third)
        let removedThird = tab.remove(third)
        #expect(removedThird)
        #expect(tab.activePane == first)
        let removedLast = tab.remove(first)
        #expect(!removedLast)
    }
    @Test func splitsAreBoundedAndUnknownSelectionCannotStealFocus() {
        var tab = TerminalTab(title: "tools")
        for _ in 0..<3 {
            let pane = tab.split(.horizontal)
            #expect(pane != nil)
        }
        let extra = tab.split(.vertical)
        #expect(extra == nil)
        let active = tab.activePane
        tab.select(UUID())
        #expect(tab.activePane == active)
    }
    @Test func terminalEnvironmentDoesNotReceiveHyCodeAgentSecrets() throws {
        let config = try TerminalConfiguration(
            shell: URL(fileURLWithPath: "/bin/sh"), arguments: [], directory: URL(fileURLWithPath: "/tmp"),
            environment: [
                "HYCODE_CODEX_API_KEY": "fixture", "DYLD_INSERT_LIBRARIES": "fixture", "PATH": "/bin",
                "USER_VALUE": "中文",
            ])
        #expect(config.environment["HYCODE_CODEX_API_KEY"] == nil)
        #expect(config.environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(config.environment["USER_VALUE"] == "中文")
        #expect(config.environment["TERM"] == "xterm-256color")
        #expect(config.environment["SHELL"] == "/bin/sh")
        #expect(throws: TerminalFailure.self) {
            try TerminalConfiguration(
                shell: config.shell, arguments: ["invalid\0argument"], directory: config.directory, environment: [:])
        }
    }
    @Test func insertedPathsRemainOneShellArgument() async throws {
        let value = "a' b;$(not-a-command)\n中文"
        #expect(TerminalConfiguration.quotePath(value) == "'a'\\'' b;$(not-a-command)\n中文'")
        #expect(TerminalConfiguration.pasteNeedsConfirmation("first\r\nsecond"))
        #expect(TerminalConfiguration.pasteNeedsConfirmation("first\nsecond"))
        #expect(!TerminalConfiguration.pasteNeedsConfirmation("one line"))
    }
    @Test func fileReferencesRespectTheAuthorizedRootAndSourceLocations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("中文.swift")
        try Data("fixture".utf8).write(to: file)
        let ref = try TerminalFileReference.resolve("中文.swift:12:3", directory: root, root: root)
        #expect(ref.url == file.resolvingSymlinksInPath())
        #expect(ref.line == 12 && ref.column == 3)
        #expect(throws: TerminalFailure.self) {
            try TerminalFileReference.resolve("../outside", directory: root, root: root)
        }
        #expect(throws: TerminalFailure.self) {
            try TerminalFileReference.resolve("file://remote/etc/passwd", directory: root, root: root)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        #expect(throws: TerminalFailure.self) {
            try TerminalFileReference.resolve("escape", directory: root, root: root)
        }
    }
    @Test func theEmbeddedEngineHandlesFragmentedUnicodeCursorAndAlternateScreen() {
        let delegate = TerminalTestDelegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 30, rows: 4, scrollback: 8))
        for byte in "中文🙂".utf8 { terminal.feed(byteArray: [byte]) }
        terminal.feed(text: "\r\nnormal\u{1b}[?1049halternate\u{1b}[?1049l")
        // Selection text resolves wide/complex glyphs through the emulator's payload table.
        let text = terminal.getText(start: Position(col: 0, row: 0), end: Position(col: 29, row: 3))
        #expect(text.contains("中文🙂"))
        #expect(text.contains("normal"))
        #expect(!text.contains("alternate"))
        terminal.feed(text: "\u{1b}[6n")
        #expect(String(decoding: delegate.sent, as: UTF8.self).contains("R"))
    }
    @Test func outputGatePreservesSplitUtf8AnsiAndBoundedMetadata() {
        var filter = TerminalOutputFilter()
        let source = "中文🙂\u{1b}[31mred\u{1b}[0m\u{1b}]2;标题\u{7}"
        var output = Data()
        for byte in source.utf8 { output.append(filter.append(Data([byte]))) }
        #expect(output == Data(source.utf8))
        #expect(filter.oversizedSequences == 0)
    }
    @Test func outputGateDropsGraphicsAndOversizedStringsBeforeTheyReachTheEngine() {
        var filter = TerminalOutputFilter()
        let dangerous = "\u{1b}Pq#999999999999999999999999;2;0;0;0\u{1b}\\"
        let nested = "\u{1b}]2;title\u{1b}Pq#999999999999999999999999\u{1b}\\"
        #expect(filter.append(Data((dangerous + nested).utf8)).isEmpty)
        #expect(filter.append(Data("\u{1b}_Gpayload\u{1b}\\".utf8)).isEmpty)
        #expect(filter.append(Data("\u{1b}]52;clipboard\u{7}".utf8)).isEmpty)
        _ = filter.append(Data("\u{1b}]2;".utf8))
        for _ in 0..<32 { #expect(filter.append(Data(repeating: 97, count: 4096)).isEmpty) }
        #expect(filter.oversizedSequences == 1)
        #expect(filter.append(Data("\u{1b}\\OK".utf8)) == Data("OK".utf8))
        let delegate = TerminalTestDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.feed(byteArray: Array(filter.append(Data((dangerous + "safe").utf8))))
        #expect(terminal.getText(start: Position(col: 0, row: 0), end: Position(col: 10, row: 0)).contains("safe"))
    }
    @Test func c1AndEmbeddedIntroducersCannotBypassTheOutputGate() {
        var filter = TerminalOutputFilter()
        #expect(filter.append(Data([0x90] + Array("qmalicious".utf8) + [0x9c])).isEmpty)
        #expect(filter.append(Data([0x1b, 0x5d, 0x32, 0x3b, 0x90, 0x71, 0x1b, 0x5c])).isEmpty)
        #expect(filter.append(Data("\u{1b}[999999999999999999999b".utf8)).isEmpty)
        #expect(filter.append(Data([0x1b, 0x5b, 0x90, 0x71])).isEmpty)
        #expect(filter.append(Data("after".utf8)) == Data("after".utf8))
    }
    @Test func escapeIntermediateStateIsBoundedAcrossThousandsOfChunks() {
        var filter = TerminalOutputFilter()
        #expect(filter.append(Data([0x1b])).isEmpty)
        for _ in 0..<10_000 { #expect(filter.append(Data([0x20])).isEmpty) }
        #expect(filter.oversizedSequences == 1)
        #expect(filter.append(Data("Arestored".utf8)) == Data("restored".utf8))
        #expect(filter.append(Data("\u{1b}(B".utf8)) == Data("\u{1b}(B".utf8))
    }
    @Test func repeatedCombiningMarksAreBoundedBeforeTheEmulator() {
        var filter = TerminalOutputFilter()
        let source = "a" + String(repeating: "\u{301}", count: 1000) + " end"
        let output = filter.append(Data(source.utf8))
        #expect(filter.unicodeReplacements > 0)
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.unicodeScalars.contains { $0.value == 0xfffd })
        let delegate = TerminalTestDelegate()
        let terminal = Terminal(delegate: delegate)
        terminal.feed(byteArray: Array(output))
        #expect(terminal.getText(start: Position(col: 0, row: 0), end: Position(col: 70, row: 0)).contains("end"))
    }
    @Test func c0AndRepeatedEscapesCannotDesynchronizeTheGateAndEngine() {
        for control: UInt8 in [0, 7, 10, 13, 0x1b, 0x7f] {
            var filter = TerminalOutputFilter()
            let bytes = [0x1b, control] + Array("Pq#999999999999999999999999;2;0;0;0".utf8) + [0x1b, 0x5c]
            var output = Data()
            for byte in bytes { output.append(filter.append(Data([byte]))) }
            #expect(output.isEmpty)
            #expect(filter.append(Data("safe".utf8)) == Data("safe".utf8))
        }
    }
    @Test func distinctUnicodeClustersKeepFlagsHangulAndEmojiIntactAcrossChunks() {
        var filter = TerminalOutputFilter()
        let source = String(repeating: "🇨🇳", count: 20) + String(repeating: "각", count: 12) + "👨‍👩‍👧‍👦👍🏽❤️"
        var output = Data()
        for byte in source.utf8 { output.append(filter.append(Data([byte]))) }
        #expect(output == Data(source.utf8))
        #expect(filter.unicodeReplacements == 0)
    }
}

private final class TerminalTestDelegate: TerminalDelegate {
    var sent: [UInt8] = []
    func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
}

/// Only generated fixtures and fixed non-login shell commands. No terminal
/// view, application host, user shell configuration, clipboard, bell or GUI.
@Suite(.serialized) struct TerminalProcessTests {
    private func helper() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["HYCODE_TEST_TERMINAL_HOST"],
            FileManager.default.isExecutableFile(atPath: path)
        {
            return URL(fileURLWithPath: path)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let built = root.appendingPathComponent(".build/out/Products/Debug/HyCodeTerminalHost")
        if FileManager.default.isExecutableFile(atPath: built.path) { return built }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let path = directory.appendingPathComponent("HyCodeTerminalHost")
            if FileManager.default.isExecutableFile(atPath: path.path) { return path }
            directory.deleteLastPathComponent()
        }
        throw TerminalFailure("Build HyCodeTerminalHost before running terminal tests")
    }
    private func configuration(_ script: String, directory: URL) throws -> TerminalConfiguration {
        try TerminalConfiguration(
            shell: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: directory,
            environment: ["PATH": "/usr/bin:/bin", "HOME": directory.path, "LC_ALL": "en_US.UTF-8"])
    }
    private func collect(_ process: TerminalProcess) async -> Data {
        var data = Data()
        while let part = await process.nextOutput() {
            if data.count + part.count <= 1_048_576 { data.append(part) }
        }
        return data
    }
    @Test func realPtyHasAControllingTerminalAndInitialDimensions() async throws {
        let directory = FileManager.default.temporaryDirectory
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "test -t 0 && test -t 1 && test -t 2 || exit 9\npwd\nstty size\nprintf '中文\\n'", directory: directory),
            helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        let output = String(decoding: await collect(process), as: UTF8.self)
        let code = await process.waitForExit()
        watchdog.cancel()
        #expect(code == 0)
        #expect(output.contains("28 100"))
        #expect(output.contains(directory.resolvingSymlinksInPath().path))
        #expect(output.contains("中文"))
    }
    @Test func orderedInputAndResizeReachTheRealShell() async throws {
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "stty -echo\nprintf 'READY\\n'\nIFS= read -r value\nprintf 'INPUT:<%s>\\n' \"$value\"\nstty size",
                directory: FileManager.default.temporaryDirectory), helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        var output = Data()
        var sent = false
        while let bytes = await process.nextOutput() {
            output.append(bytes)
            if !sent, String(decoding: output, as: UTF8.self).contains("READY") {
                sent = true
                process.resize(columns: 88, rows: 17)
                try await process.send(Data("中文 'quoted'\n".utf8))
            }
        }
        let code = await process.waitForExit()
        watchdog.cancel()
        let text = String(decoding: output, as: UTF8.self)
        #expect(sent && code == 0)
        #expect(text.contains("INPUT:<中文 'quoted'>"))
        #expect(text.contains("17 88"))
    }
    @Test func controlCInterruptsTheForegroundProcess() async throws {
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "printf 'READY\\n'\nexec /bin/sleep 30", directory: FileManager.default.temporaryDirectory),
            helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        var received = false
        while let bytes = await process.nextOutput() {
            if !received, String(decoding: bytes, as: UTF8.self).contains("READY") {
                received = true
                try await process.send(Data([3]))
            }
        }
        let code = await process.waitForExit()
        watchdog.cancel()
        #expect(received && code == 130)
    }
    @Test func closingAnUnresponsiveSessionIsBoundedAndRejectsLateInput() async throws {
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "trap '' HUP TERM\nprintf 'READY\\n'\nwhile :; do /bin/sleep 30; done",
                directory: FileManager.default.temporaryDirectory), helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        let ready = await process.nextOutput()
        #expect(ready != nil)
        let start = ContinuousClock.now
        await process.stop()
        _ = await collect(process)
        watchdog.cancel()
        #expect(start.duration(to: .now) < .seconds(4))
        await #expect(throws: TerminalFailure.self) { try await process.send(Data("late".utf8)) }
    }
    @Test func stoppedOwnersAndInvalidDirectoriesCannotLaunchAChild() async throws {
        let terminalHelper = try helper()
        let process = TerminalProcess()
        await process.stop()
        await #expect(throws: TerminalFailure.self) {
            try await process.start(
                configuration: configuration("exit 0", directory: FileManager.default.temporaryDirectory),
                helper: terminalHelper)
        }
        let invalid = TerminalProcess()
        do {
            try await invalid.start(
                configuration: configuration(
                    "exit 0", directory: URL(fileURLWithPath: "/tmp/hycode-missing-\(UUID())")), helper: terminalHelper)
            Issue.record("Invalid directory started a terminal")
        } catch {}
        await invalid.stop()
    }
    @Test func aBlockedInputConsumerDoesNotPreventShutdown() async throws {
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "stty -echo\nprintf 'READY\\n'\nexec /bin/sleep 30",
                directory: FileManager.default.temporaryDirectory), helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        let ready = await process.nextOutput()
        #expect(ready != nil)
        try await process.send(Data(repeating: 97, count: 200_000))
        await #expect(throws: TerminalFailure.self) { try await process.send(Data(repeating: 97, count: 262_145)) }
        let began = ContinuousClock.now
        await process.stop()
        _ = await collect(process)
        watchdog.cancel()
        #expect(began.duration(to: .now) < .seconds(4))
    }
    @Test func closeReclaimsBackgroundJobsInSeparateGroupsOfTheSameSession() async throws {
        let began = ContinuousClock.now
        let process = TerminalProcess()
        try await process.start(
            configuration: configuration(
                "set -m\ntrap '' HUP TERM\n/bin/sleep 30 &\nprintf 'CHILD:%s\\n' \"$!\"\nwait",
                directory: FileManager.default.temporaryDirectory), helper: helper())
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(8))
            await process.stop()
        }
        var text = ""
        while true {
            if text.components(separatedBy: "CHILD:").dropFirst().first?.unicodeScalars.contains(where: {
                $0.value == 10
            }) == true {
                break
            }
            guard let bytes = await process.nextOutput() else { break }
            text += String(decoding: bytes, as: UTF8.self)
        }
        let childText = text.components(separatedBy: "CHILD:").last?.prefix { $0.isNumber } ?? ""
        let child = try #require(Int32(childText))
        let childSession = getsid(child)
        defer { if childSession > 1, getsid(child) == childSession { _ = kill(child, SIGKILL) } }
        await process.stop()
        _ = await collect(process)
        for _ in 0..<20 {
            if kill(child, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        watchdog.cancel()
        #expect(kill(child, 0) != 0)
        #expect(began.duration(to: .now) < .seconds(4))
    }
}
