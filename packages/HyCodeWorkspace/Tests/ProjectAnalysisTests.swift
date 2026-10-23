import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

private struct AnalysisFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-analysis-" + UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func put(_ path: String, _ data: Data) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

struct ProjectAnalysisTests {
    @Test func discoveryUsesExactRelativeNamesAndPrunesDependenciesAndLinks() throws {
        let fixture = try AnalysisFixture()
        defer { fixture.remove() }
        for path in [
            "src/目录/😀.ts", "src/a.scss", "nested/other.js", "node_modules/pkg/a.ts", ".hidden/a.ts", "build/a.ts",
            "lib/a.dart",
        ] {
            try fixture.put(path, Data("// text".utf8))
        }
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("linked"),
            withDestinationURL: fixture.root.appendingPathComponent("src"))
        let result = try ProjectSourceCatalog.scan(root: fixture.root)
        #expect(result.files.map(\.path) == ["nested/other.js", "src/a.scss", "src/目录/😀.ts"])
        #expect(result.hasDart && !result.limited)
        #expect(result.skipped == 1)
        for file in result.files { #expect(try ProjectSourceCatalog.read(file, root: fixture.root) == "// text") }
        #expect(ProjectSourceCatalog.inspect(path: "linked/a.scss", root: fixture.root) == nil)
    }
    @Test func discoveryAndReadEnforceBudgetsAndEncoding() throws {
        let fixture = try AnalysisFixture()
        defer { fixture.remove() }
        try fixture.put("a.ts", Data("let a = 1;".utf8))
        try fixture.put("large.ts", Data(repeating: 65, count: 1_048_577))
        try fixture.put("wide.css", Data([0xff, 0xfe]) + "中😀".data(using: .utf16LittleEndian)!)
        try fixture.put("binary.css", Data([0, 1, 2, 3]))
        let result = try ProjectSourceCatalog.scan(root: fixture.root)
        #expect(result.skipped == 1 && result.files.count == 3)
        #expect(try ProjectSourceCatalog.scan(root: fixture.root, fileLimit: 1).limited)
        #expect(try ProjectSourceCatalog.scan(root: fixture.root, byteLimit: 1).limited)
        let wide = try #require(result.files.first { $0.path == "wide.css" })
        #expect(try ProjectSourceCatalog.read(wide, root: fixture.root) == "中😀")
        let binary = try #require(result.files.first { $0.path == "binary.css" })
        #expect(throws: LanguageServiceFailure.self) { try ProjectSourceCatalog.read(binary, root: fixture.root) }
        for path in ["", "../outside.ts", "/outside.ts", "a/../../b.ts", "./a.ts", "a\0.ts"] {
            #expect(!ProjectSourceCatalog.allows(path))
        }
    }
    @Test func aLinkSwapAfterDiscoveryCannotReadOutsideTheProject() throws {
        let fixture = try AnalysisFixture()
        let outside = try AnalysisFixture()
        defer {
            fixture.remove()
            outside.remove()
        }
        try fixture.put("nested/a.css", Data("inside".utf8))
        try outside.put("a.css", Data("outside".utf8))
        let file = try #require(ProjectSourceCatalog.scan(root: fixture.root).files.first)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("nested"))
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("nested"), withDestinationURL: outside.root)
        #expect(throws: LanguageServiceFailure.self) { try ProjectSourceCatalog.read(file, root: fixture.root) }
    }
    @Test func cancelledDiscoveryDoesNotContinueScanning() async throws {
        let fixture = try AnalysisFixture()
        defer { fixture.remove() }
        try fixture.put("a.ts", Data("text".utf8))
        let task = Task { () throws -> ProjectSourceCatalog in
            try await Task.sleep(for: .milliseconds(20))
            return try ProjectSourceCatalog.scan(root: fixture.root)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func replacementWithAFifoDoesNotBlockTheReader() throws {
        let fixture = try AnalysisFixture()
        defer { fixture.remove() }
        try fixture.put("a.css", Data("ordinary".utf8))
        let file = try #require(ProjectSourceCatalog.scan(root: fixture.root).files.first)
        let path = fixture.root.appendingPathComponent("a.css").path
        try FileManager.default.removeItem(atPath: path)
        #expect(mkfifo(path, 0o600) == 0)
        #expect(throws: LanguageServiceFailure.self) { try ProjectSourceCatalog.read(file, root: fixture.root) }
    }
    @Test func problemAggregationPreservesSeverityCountsFilteringAndNavigation() throws {
        let root = URL(fileURLWithPath: "/tmp/hycode-problems")
        func diagnostic(_ message: String, severity: Int, line: Int) throws -> LSPDiagnostic {
            try JSONValue([
                "range": ["start": ["line": line, "character": 2], "end": ["line": line, "character": 4]],
                "message": message, "severity": severity, "source": "test",
            ]).decode(LSPDiagnostic.self)
        }
        let error = try diagnostic("error", severity: 1, line: 4)
        let warning = try diagnostic("warning", severity: 2, line: 2)
        let info = try diagnostic("info", severity: 3, line: 0)
        let hint = try diagnostic("hint", severity: 4, line: 1)
        let uri = root.appendingPathComponent("src/a.ts").absoluteString
        let inputs = [
            "web": [
                uri: [warning, error, info, hint, error], "file:///tmp/other/b.ts": [error],
                "file://remote/tmp/hycode-problems/b.ts": [error], root.absoluteString + "/../escape.ts": [error],
            ]
        ]
        let result = try WorkspaceProblemSnapshot.make(inputs, root: root)
        #expect(result.errors == 1 && result.warnings == 1 && result.suggestions == 2)
        #expect(result.groups.map(\.path) == ["src/a.ts"])
        #expect(result.groups[0].rows.first?.target.uri == uri)
        #expect(result.groups[0].rows.first?.target.range == error.range)
        let filtered = try WorkspaceProblemSnapshot.make(inputs, root: root, category: .warning)
        #expect(filtered.errors == 1 && filtered.suggestions == 2 && filtered.groups[0].rows.count == 1)
        let limited = try WorkspaceProblemSnapshot.make(inputs, root: root, limit: 2)
        #expect(limited.limited && limited.errors == 1 && limited.warnings == 1 && limited.suggestions == 0)
        #expect(try WorkspaceProblemSnapshot.make(inputs, root: root, limit: 0).groups.isEmpty)
    }
}

private actor DocumentQueueGate {
    var entered = false
    var values: [Int] = []
    var resume: CheckedContinuation<Void, Never>?
    func hold() async {
        values.append(0)
        await withCheckedContinuation { resume in
            self.resume = resume
            entered = true
        }
        values.append(1)
    }
    func release() {
        resume?.resume()
        resume = nil
    }
    func append(_ value: Int) { values.append(value) }
}
struct LSPDocumentQueueTests {
    @Test func cancellationCannotOverwriteLaterNativeBufferWork() async throws {
        let queue = LSPDocumentQueue()
        let gate = DocumentQueueGate()
        let first = Task { try await queue.run { await gate.hold() } }
        for _ in 0..<100 {
            if await gate.entered { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await gate.entered)
        let cancelled = Task { try await queue.run { await gate.append(2) } }
        cancelled.cancel()
        let latest = Task { try await queue.run { await gate.append(3) } }
        await gate.release()
        try await first.value
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try await latest.value
        #expect(await gate.values == [0, 1, 3])
    }
}

private actor WatchEventsInbox {
    var paths = Set<String>()
    func add(_ event: WorkspaceFileEvents) { paths.formUnion(event.paths) }
    func contains(_ path: String) -> Bool { paths.contains(path) }
}
struct WorkspaceSourceWatcherTests {
    @Test func recursiveEventsObserveOnlyOwnFixtureWithoutAMainRunLoop() async throws {
        let fixture = try AnalysisFixture()
        defer { fixture.remove() }
        try fixture.put("nested/a.ts", Data("first".utf8))
        try fixture.put("nested/schema.schema", Data("{}".utf8))
        try fixture.put("nested/schema", Data("{}".utf8))
        let inbox = WatchEventsInbox()
        let watcher = try WorkspaceSourceWatcher(root: fixture.root) { event in Task { await inbox.add(event) } }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(350))
        try fixture.put("nested/a.ts", Data("second".utf8))
        try fixture.put("nested/schema.schema", Data("{\"type\":\"string\"}".utf8))
        try fixture.put("nested/schema", Data("{\"type\":\"integer\"}".utf8))
        for _ in 0..<100 {
            if await inbox.contains("nested/a.ts"), await inbox.contains("nested/schema.schema"),
                await inbox.contains("nested/schema")
            {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await inbox.contains("nested/a.ts"))
        #expect(await inbox.contains("nested/schema.schema"))
        #expect(await inbox.contains("nested/schema"))
        watcher.stop()
        watcher.stop()
    }
}
