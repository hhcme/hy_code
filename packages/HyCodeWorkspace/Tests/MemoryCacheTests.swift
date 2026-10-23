import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized) struct MemoryCacheTests {
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-cache-" + UUID().uuidString)
        let file: URL
        let document: NativeTextDocument
        init(_ text: String) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent("main.dart")
            try Data(text.utf8).write(to: file)
            document = NativeTextDocument(root: root, path: "main.dart")
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }
    @Test func dirtyUnicodeBufferAndRevisionSurviveCacheEvictionAndRebuild() async throws {
        let original = "final value = '中😀';\r\n"
        let fixture = try Fixture(original)
        _ = try await fixture.document.open()
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 0), text: "// 未保存\r\n")
        let text = "// 未保存\r\n" + original
        let range = NSRange(location: 0, length: text.utf16.count)
        let first = try await fixture.document.syntax(revision: 1, range: range)
        #expect(!first.spans.isEmpty)
        let activated = DocumentSaveCancellation()
        activated.cancel()
        do {
            _ = try await fixture.document.trimRebuildableCaches(cancellation: activated)
            Issue.record("Activated document cache was evicted")
        } catch is CancellationError {}
        // The cancelled action did not consume this cache or mutate the revision.
        #expect(try await fixture.document.trimRebuildableCaches())
        #expect(!(try await fixture.document.trimRebuildableCaches()))
        #expect(try Data(contentsOf: fixture.file) == Data(original.utf8))
        _ = try await NativeCacheMaintenance.shared.releaseUnusedSyntaxGrammars()
        let rebuilt = try await fixture.document.syntax(revision: 1, range: range)
        #expect(rebuilt.spans.map(\.style) == first.spans.map(\.style))
        try await fixture.document.save(revision: 1)
        #expect(try Data(contentsOf: fixture.file) == Data(text.utf8))
    }
    @Test func largePageDirtyInputAndCrossPageUndoAreNeverCacheEvicted() async throws {
        let source = String(repeating: "a", count: 150_000) + "\nTAIL"
        let fixture = try Fixture(source)
        let content = try await fixture.document.open()
        let first = try #require(content.largePage)
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "中😀")
        #expect(!(try await fixture.document.trimRebuildableCaches()))
        _ = try await fixture.document.page(revision: 1, offset: first.last)
        #expect(!(try await fixture.document.trimRebuildableCaches()))
        let undone = try await fixture.document.history(revision: 1, redo: false)
        #expect(undone.largePage?.start == 0 && undone.text.hasPrefix("aaa"))
        let redone = try await fixture.document.history(revision: 2, redo: true)
        #expect(redone.text.hasPrefix("中😀aa"))
        try await fixture.document.save(revision: 3)
        #expect(try Data(contentsOf: fixture.file) == Data(("中😀" + source.dropFirst()).utf8))
    }
}
