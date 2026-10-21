import Foundation
import Testing

@testable import HyCodeWorkspace

struct SyntaxHighlightTests {
    private final class Fixture {
        let root: URL
        let file: URL
        let document: NativeTextDocument
        init(_ text: String, name: String = "main.dart") throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "hycode-syntax-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent(name, isDirectory: false)
            try Data(text.utf8).write(to: file)
            document = NativeTextDocument(root: root, path: name)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }
    @Test func nativeBridgeReturnsUTF16CapturesWithoutEditingTheDocument() async throws {
        let text = "// 😀中文\r\nfinal message = 'hello';\r\n"
        let fixture = try Fixture(text)
        let content = try await fixture.document.open()
        #expect(content.lineIndex.count == 3)
        let snapshot = try await fixture.document.syntax(
            revision: 0, range: NSRange(location: 0, length: text.utf16.count))
        #expect(snapshot.language == "Dart" && snapshot.status == "ready")
        let source = text as NSString
        #expect(
            snapshot.spans.contains {
                $0.style.hasPrefix("string") && source.substring(with: $0.range).contains("hello")
            })
        try await fixture.document.save(revision: 0)
        #expect(try Data(contentsOf: fixture.file) == Data(text.utf8))
    }
    @Test func revisionsAndViewportRangesSurviveEditsAndRejectStaleResults() async throws {
        let fixture = try Fixture("const value = 'x';", name: "main.ts")
        _ = try await fixture.document.open()
        _ = try await fixture.document.syntax(revision: 0, range: NSRange(location: 0, length: 18))
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 0), text: "// 😀\n")
        do {
            _ = try await fixture.document.syntax(revision: 0, range: NSRange(location: 0, length: 5))
            Issue.record("Stale syntax accepted")
        } catch let error as WorkspaceFailure { #expect(error.code == "stale_revision") }
        let snapshot = try await fixture.document.syntax(revision: 1, range: NSRange(location: 6, length: 18))
        #expect(snapshot.spans.allSatisfy { $0.start >= 6 && $0.start + $0.length <= 24 })
    }
    @Test func unsupportedAndLargeFilesStayEditableWithExplicitHighlightStatus() async throws {
        for (name, text, status) in [
            ("notes.txt", "hello", "plain"), ("big.rs", String(repeating: "x", count: 1024 * 1024 + 1), "size_limit"),
        ] {
            let fixture = try Fixture(text, name: name)
            _ = try await fixture.document.open()
            let snapshot = try await fixture.document.syntax(revision: 0, range: NSRange(location: 0, length: 5))
            #expect(snapshot.status == status && snapshot.spans.isEmpty)
            try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "y")
        }
    }
    @Test func cancelledViewportDoesNotEnterTheNativeParser() async throws {
        let fixture = try Fixture("final message = 'hello';")
        _ = try await fixture.document.open()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.document.syntax(revision: 0, range: NSRange(location: 0, length: 10))
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled syntax request entered the parser")
        } catch is CancellationError {
        }
    }

    @Test func distantDartViewportsReturnColorsWithReadAheadAndKeepSavedContent() async throws {
        let text = (0..<2_000).map { "// line \($0)\nfinal message\($0) = 'hello \($0)';\n" }.joined()
        let source = text as NSString
        let fixture = try Fixture(text)
        _ = try await fixture.document.open()
        var milliseconds: [Double] = []
        for location in [0, 20_000, 60_000, 10_000, 80_000] {
            let range = try #require(
                SyntaxViewportState.requestRange(for: NSRange(location: location, length: 1_000), source: source))
            let start = ContinuousClock.now
            let snapshot = try await fixture.document.syntax(revision: 0, range: range)
            let elapsed = start.duration(to: .now).components
            milliseconds.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
            #expect(snapshot.status == "ready" && !snapshot.spans.isEmpty)
            #expect(snapshot.spans.allSatisfy { NSIntersectionRange($0.range, range) == $0.range })
        }
        print("Dart generated viewport probe (ms, not UI latency): \(milliseconds)")
        try await fixture.document.save(revision: 0)
        #expect(try Data(contentsOf: fixture.file) == Data(text.utf8))
    }
}
