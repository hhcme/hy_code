import Foundation
import Testing

@testable import HyCodeWorkspace

struct TerminalCompletionTests {
    private func request(_ line: String) throws -> TerminalCompletionRequest {
        try #require(TerminalCompletionRequest.parse(line: line, cursor: line.unicodeScalars.count))
    }
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    @Test func commandAndNestedSubcommandsUseOfflineMetadata() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for (line, expected) in [
            ("flu", "flutter"), ("git ch", "checkout"),
            ("flutter pub g", "get"), ("flutter build ma", "macos"), ("cargo test --rel", "--release"),
        ] {
            let values = TerminalCompletionProvider.suggestions(for: try request(line), directory: root, root: root)
            #expect(values.contains { $0.value == expected })
            #expect(values.allSatisfy { !$0.suffix.contains("\n") && !$0.suffix.contains("\r") })
        }
    }
    @Test func complexExpressionsAndMidLineEditingStayWithTheShell() {
        for line in [
            "echo $HOME", "git status | cat", "ls > out", "echo \u{60}pwd\u{60}", "echo a\nb", "x\\",
            "ls *.swift", "git;echo danger",
        ] {
            #expect(TerminalCompletionRequest.parse(line: line, cursor: line.unicodeScalars.count) == nil)
        }
        #expect(TerminalCompletionRequest.parse(line: "git ch", cursor: 3) == nil)
        #expect(TerminalCompletionRequest.parse(line: "cat \"a\\file", cursor: 11)?.prefix == "a\\file")
    }
    @Test func pathsAreQuotedAndConfinedToTheAuthorizedRoot() throws {
        let root = try fixture()
        let outside = try fixture()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("中文 folder"), withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("file '$(text).txt"))
        try Data().write(to: root.appendingPathComponent("~fixture"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let directories = TerminalCompletionProvider.suggestions(for: try request("cd 中"), directory: root, root: root)
        #expect(directories.map(\.suffix) == ["文\\ folder/"])
        let files = TerminalCompletionProvider.suggestions(for: try request("cat fi"), directory: root, root: root)
        #expect(files.first?.suffix == "le\\ \\'\\$\\(text\\).txt ")
        let tilde = TerminalCompletionProvider.suggestions(for: try request("cat "), directory: root, root: root)
        #expect(tilde.first(where: { $0.value == "~fixture" })?.suffix == "\\~fixture ")
        let quoted = TerminalCompletionProvider.suggestions(for: try request("cat 'fi"), directory: root, root: root)
        #expect(quoted.first?.suffix == "le '\\''$(text).txt' ")
        #expect(
            TerminalCompletionProvider.suggestions(for: try request("cat escape/"), directory: root, root: root).isEmpty
        )
        #expect(
            TerminalCompletionProvider.suggestions(for: try request("cat "), directory: outside, root: root).isEmpty)
    }
    @Test func promptReportsRequireTokenAndBoundedValidState() throws {
        let valid = #"{"token":"fixture","phase":"edit","line":"git ch","cursor":6,"directory":"/fixture"}"#
        #expect(TerminalPromptState.decode(Data(valid.utf8), token: "fixture")?.line == "git ch")
        #expect(TerminalPromptState.decode(Data(valid.utf8), token: "other") == nil)
        #expect(
            TerminalPromptState.decode(Data(valid.replacingOccurrences(of: ":6", with: ":999").utf8), token: "fixture")
                == nil)
        #expect(TerminalPromptState.decode(Data(repeating: 97, count: 8193), token: "fixture") == nil)
        let bad = valid.replacingOccurrences(of: "git ch", with: "git\\nch")
        #expect(TerminalPromptState.decode(Data(bad.utf8), token: "fixture") == nil)
    }
    @Test func integrationUsesPrivateStorageAndRejectsControlInput() throws {
        let integration = try #require(try TerminalShellIntegration.prepare(shell: URL(fileURLWithPath: "/bin/zsh")))
        defer { integration.remove() }
        let attributes = try FileManager.default.attributesOfItem(atPath: integration.directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(try TerminalShellIntegration.prepare(shell: URL(fileURLWithPath: "/bin/bash")) == nil)
        let state = TerminalPromptState(
            token: integration.token, phase: "edit", line: "git ch", cursor: 6, directory: "/fixture")
        let candidate = TerminalCompletionCandidate(
            value: "checkout", detail: "", kind: .subcommand, suffix: "eckout\n")
        #expect(throws: TerminalFailure.self) { try integration.writeAcceptance(state: state, candidate: candidate) }
    }
    @Test func outputGatePassesOnlyBoundedIntegrationFrames() {
        var filter = TerminalOutputFilter()
        let frame = "\u{1b}]7777;{}\u{7}"
        #expect(filter.append(Data(frame.utf8)) == Data(frame.utf8))
        #expect(filter.append(Data(("\u{1b}]7777;" + String(repeating: "x", count: 9000) + "\u{7}").utf8)).isEmpty)
        #expect(filter.oversizedSequences == 1)
    }
}

private actor PromptReports {
    let token: String
    private var reports: [TerminalPromptState] = []
    private var output = ""
    init(token: String) { self.token = token }
    func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        output = String((output + text).suffix(65_536))
        for part in text.components(separatedBy: "\u{1b}]7777;").dropFirst() {
            let json = part.prefix { $0 != "\u{7}" }
            if let state = TerminalPromptState.decode(Data(json.utf8), token: token) { reports.append(state) }
        }
        if reports.count > 128 { reports.removeFirst(reports.count - 128) }
    }
    func latest() -> TerminalPromptState? { reports.last }
    func contains(_ text: String) -> Bool { output.contains(text) }
}

/// Generated HOME/config files and fixed zsh input only, with global startup
/// files disabled. No app, terminal view, user profile, clipboard or GUI.
@Suite(.serialized) struct TerminalZshCompletionTests {
    private func helper() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["HYCODE_TEST_TERMINAL_HOST"] {
            return URL(fileURLWithPath: override)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let built = root.appendingPathComponent(".build/out/Products/Debug/HyCodeTerminalHost")
        if FileManager.default.isExecutableFile(atPath: built.path) { return built }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let file = directory.appendingPathComponent("HyCodeTerminalHost")
            if FileManager.default.isExecutableFile(atPath: file.path) { return file }
            directory.deleteLastPathComponent()
        }
        throw TerminalFailure("Build HyCodeTerminalHost before terminal tests")
    }
    private func wait(_ reports: PromptReports, line: String, phase: String = "edit") async throws
        -> TerminalPromptState
    {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if let state = await reports.latest(), state.phase == phase, state.line == line { return state }
            try await Task.sleep(for: .milliseconds(15))
        }
        throw TerminalFailure("Fixed zsh fixture did not report the expected prompt state")
    }
    private func withShell(
        login: Bool = false, setup: (URL) throws -> Void = { _ in },
        body: (TerminalProcess, PromptReports, TerminalShellIntegration, URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try setup(root)
        let integration = try #require(try TerminalShellIntegration.prepare(shell: URL(fileURLWithPath: "/bin/zsh")))
        defer { integration.remove() }
        let process = TerminalProcess()
        let reports = PromptReports(token: integration.token)
        let environment = integration.environment(["HOME": root.path, "PATH": "/usr/bin:/bin", "LC_ALL": "en_US.UTF-8"])
        try await process.start(
            configuration: TerminalConfiguration(
                shell: URL(fileURLWithPath: "/bin/zsh"), arguments: login ? ["-d", "-l", "-i"] : ["-d", "-i"],
                directory: root, environment: environment), helper: helper())
        let reader = Task {
            while let part = await process.nextOutput() { await reports.append(part) }
        }
        do {
            _ = try await wait(reports, line: "")
            try await body(process, reports, integration, root)
            await process.stop()
            await reader.value
        } catch {
            await process.stop()
            await reader.value
            throw error
        }
    }
    @Test func zleReportsUnicodeAndAcceptsWithoutExecuting() async throws {
        try await withShell { process, reports, integration, root in
            try await process.send(Data("git ch".utf8))
            let state = try await wait(reports, line: "git ch")
            let request = try #require(TerminalCompletionRequest.parse(line: state.line, cursor: state.cursor))
            let candidate = try #require(
                TerminalCompletionProvider.suggestions(for: request, directory: root, root: root).first)
            #expect(candidate.value == "checkout")
            try integration.writeAcceptance(state: state, candidate: candidate)
            try await process.send(Data(TerminalShellIntegration.acceptSequence.utf8), onlyWhenShellForeground: true)
            _ = try await wait(reports, line: "git checkout ")
            try await process.send(Data("\u{15}cat '中文/".utf8))
            let unicode = try await wait(reports, line: "cat '中文/")
            #expect(unicode.cursor == unicode.line.unicodeScalars.count)
            #expect(unicode.directory == root.path)
        }
    }
    @Test func staleBufferAndCursorCannotAcceptAnOldCandidate() async throws {
        try await withShell { process, reports, integration, root in
            try await process.send(Data("git ch".utf8))
            let old = try await wait(reports, line: "git ch")
            let request = try #require(TerminalCompletionRequest.parse(line: old.line, cursor: old.cursor))
            let candidate = try #require(
                TerminalCompletionProvider.suggestions(for: request, directory: root, root: root).first)
            try integration.writeAcceptance(state: old, candidate: candidate)
            try await process.send(Data("X".utf8))
            _ = try await wait(reports, line: "git chX")
            try await process.send(Data(TerminalShellIntegration.acceptSequence.utf8), onlyWhenShellForeground: true)
            try await Task.sleep(for: .milliseconds(120))
            #expect(await reports.latest()?.line == "git chX")
            try integration.writeAcceptance(state: old, candidate: candidate)
            try await process.send(Data("\u{7f}\u{1b}[D".utf8))
            try await Task.sleep(for: .milliseconds(80))
            try await process.send(Data(TerminalShellIntegration.acceptSequence.utf8), onlyWhenShellForeground: true)
            try await Task.sleep(for: .milliseconds(120))
            #expect(await reports.latest()?.line == "git ch")
            #expect(await reports.latest()?.cursor == 5)
        }
    }
    @Test func foregroundChildDoesNotReceiveTheCompletionSequence() async throws {
        try await withShell { process, reports, _, _ in
            try await process.send(Data("sleep 1\r".utf8))
            _ = try await wait(reports, line: "", phase: "finish")
            try await Task.sleep(for: .milliseconds(80))
            await #expect(throws: TerminalFailure.self) {
                try await process.send(
                    Data(TerminalShellIntegration.acceptSequence.utf8), onlyWhenShellForeground: true)
            }
            _ = try await wait(reports, line: "")
        }
    }
    @Test func loginStartupRelaysCustomZdotdirExactlyOnce() async throws {
        try await withShell(
            login: true,
            setup: { root in
                let config = root.appendingPathComponent("custom")
                try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false)
                try Data("print env >> \"$HOME/order\"\nexport ZDOTDIR=\"$HOME/custom\"\n".utf8)
                    .write(to: root.appendingPathComponent(".zshenv"))
                for (name, label) in [(".zprofile", "profile"), (".zshrc", "rc"), (".zlogin", "login")] {
                    try Data(
                        ("print \(label) >> \"$HOME/order\"\n" + (name == ".zshrc" ? "PROMPT='fixture> '\n" : "")).utf8
                    )
                    .write(to: config.appendingPathComponent(name))
                }
            },
            body: { process, reports, _, root in
                #expect(
                    try String(contentsOf: root.appendingPathComponent("order"), encoding: .utf8)
                        == "env\nprofile\nrc\nlogin\n")
                try await process.send(Data("print -r -- \"ZDOT:$ZDOTDIR\"\r".utf8))
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while ContinuousClock.now < deadline,
                    !(await reports.contains("ZDOT:" + root.appendingPathComponent("custom").path))
                {
                    try await Task.sleep(for: .milliseconds(15))
                }
                #expect(await reports.contains("ZDOT:" + root.appendingPathComponent("custom").path))
            })
    }
    @Test func acceptedInsertionPrecedesAnImmediateEnter() async throws {
        try await withShell(
            setup: { root in
                try Data().write(to: root.appendingPathComponent("fixture"))
            },
            body: { process, reports, integration, root in
                let line = "printf RESULT:%s fi"
                try await process.send(Data(line.utf8))
                let state = try await wait(reports, line: line)
                let request = try #require(TerminalCompletionRequest.parse(line: line, cursor: state.cursor))
                let candidate = try #require(
                    TerminalCompletionProvider.suggestions(for: request, directory: root, root: root).first)
                let identity = UUID().uuidString
                try integration.writeAcceptance(state: state, candidate: candidate, identity: identity)
                try await process.send(Data((TerminalShellIntegration.acceptSequence + "\r").utf8))
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while ContinuousClock.now < deadline, !(await reports.contains("RESULT:fixture")) {
                    try await Task.sleep(for: .milliseconds(15))
                }
                #expect(await reports.contains("RESULT:fixture"))
                #expect(await reports.latest()?.acceptance == identity)
            })
    }
    @Test func builtinReadKeepsCompletionDisabledWhileShellRemainsForeground() async throws {
        try await withShell { process, reports, _, _ in
            try await process.send(Data("read -r answer\r".utf8))
            _ = try await wait(reports, line: "", phase: "finish")
            try await Task.sleep(for: .milliseconds(120))
            #expect(await reports.latest()?.phase == "finish")
            try await process.send(Data("fixture\r".utf8))
            _ = try await wait(reports, line: "")
        }
    }
    @Test func nonExportedZdotdirDoesNotChangeChildStartup() async throws {
        try await withShell(
            login: true,
            setup: { root in
                let custom = root.appendingPathComponent("custom")
                try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: false)
                try Data("ZDOTDIR=$HOME/custom\nexport FIXTURE_CHAIN=${FIXTURE_CHAIN}x\n".utf8)
                    .write(to: root.appendingPathComponent(".zshenv"))
                try Data("PROMPT='fixture> '\n".utf8).write(to: custom.appendingPathComponent(".zshrc"))
            },
            body: { process, reports, _, _ in
                try await process.send(Data("/bin/zsh -d -c 'print -r -- CHAIN:$FIXTURE_CHAIN'\r".utf8))
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while ContinuousClock.now < deadline, !(await reports.contains("CHAIN:xx")) {
                    try await Task.sleep(for: .milliseconds(15))
                }
                #expect(await reports.contains("CHAIN:xx"))
            })
    }
}
