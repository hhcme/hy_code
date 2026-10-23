import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized) struct LargeTextDocumentTests {
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-large-" + UUID().uuidString)
        let file: URL
        let document: NativeTextDocument
        init(_ text: String, name: String = "large.log", encoding: String.Encoding = .utf8, bom: Data = Data()) throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent(name)
            try (bom + text.data(using: encoding)!).write(to: file)
            document = NativeTextDocument(root: root, path: name)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }
    @Test func everyTextExtensionRoutesWithoutWholeFileTextAndKeepsTailOnSave() async throws {
        // Multi-MiB valid text, not a sparse binary mistaken for a GB text test.
        let text = String(repeating: "abcdef0123456789\n", count: 530_000) + "FINAL-😀-中文\r\n"
        for name in ["large.json", "large.yaml", "large.dart", "large.rs", "large.log", "large.html"] {
            let fixture = try Fixture(text, name: name)
            let content = try await fixture.document.open()
            let first = try #require(content.largePage)
            #expect(first.totalBytes == UInt64(text.utf8.count))
            #expect(content.text.utf8.count <= 65_536)
            #expect(first.start == 0 && first.end < first.totalBytes)
            let last = try await fixture.document.page(revision: 0, offset: first.last)
            let tail = try #require(last.largePage)
            #expect(tail.end == tail.totalBytes && last.text.hasSuffix("FINAL-😀-中文\r\n"))
            try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "中")
            try await fixture.document.save(revision: 1)
            let saved = try Data(contentsOf: fixture.file)
            #expect(saved.count == text.utf8.count + 2)
            #expect(saved.suffix(128) == Data(text.utf8).suffix(128))
            #expect(saved.prefix(Int(tail.start)) == Data(text.utf8).prefix(Int(tail.start)))
        }
    }
    @Test func utf16BOMSurrogatesCrossPagesHistoryAndRepeatedSaves() async throws {
        let text = String(repeating: "中😀\r\n", count: 20_000)
        for (encoding, bom) in [
            (String.Encoding.utf16LittleEndian, Data([0xff, 0xfe])), (.utf16BigEndian, Data([0xfe, 0xff])),
        ] {
            // Long first physical line triggers paging even below 8 MiB.
            let source = String(repeating: "中😀", count: 22_000) + text
            let fixture = try Fixture(source, encoding: encoding, bom: bom)
            let content = try await fixture.document.open()
            let first = try #require(content.largePage)
            #expect(first.encoding == (encoding == .utf16LittleEndian ? "utf16_le" : "utf16_be"))
            do {
                try await fixture.document.replace(expected: 0, range: NSRange(location: 2, length: 1), text: "x")
                Issue.record("Split surrogate accepted")
            } catch let error as WorkspaceFailure { #expect(error.code == "invalid_range") }
            try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 3), text: "A😀")
            try await fixture.document.save(revision: 1)
            _ = try await fixture.document.page(revision: 1, offset: first.last)
            let restored = try await fixture.document.history(revision: 1, redo: false)
            #expect(restored.largePage?.start == 0)
            try await fixture.document.save(revision: 2)
            #expect(try Data(contentsOf: fixture.file) == bom + source.data(using: encoding)!)
            _ = try await fixture.document.history(revision: 2, redo: true)
            _ = try await fixture.document.page(revision: 3, offset: 0)
            try await fixture.document.save(revision: 3)
            #expect(try Data(contentsOf: fixture.file) == bom + ("A😀" + source.dropFirst(2)).data(using: encoding)!)
        }
    }
    @Test func literalSearchSpansIOBoundariesAndFindsUncommittedPieces() async throws {
        let text = String(repeating: "a", count: 262_142) + "needle😀" + String(repeating: "z", count: 90_000)
        let fixture = try Fixture(text)
        _ = try await fixture.document.open()
        let token = DocumentSaveCancellation()
        #expect(try await fixture.document.find(revision: 0, text: "needle😀", from: 0, cancellation: token) == 262_142)
        _ = try await fixture.document.page(revision: 0, offset: 0)
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "unsaved😀")
        #expect(try await fixture.document.find(revision: 1, text: "unsaved😀", from: 0, cancellation: token) == 0)
        #expect(try await fixture.document.find(revision: 1, text: "absent", from: 0, cancellation: token) == nil)
    }
    @Test func cancellationDoesNotChangeActivePageOrInstallAPartialFile() async throws {
        let fixture = try Fixture(String(repeating: "a", count: 180_000))
        _ = try await fixture.document.open()
        let token = DocumentSaveCancellation()
        token.cancel()
        do {
            _ = try await fixture.document.page(revision: 0, offset: 70_000, cancellation: token)
            Issue.record("Cancelled page loaded")
        } catch is CancellationError {}
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        do {
            try await fixture.document.save(revision: 1, cancellation: token)
            Issue.record("Cancelled export saved")
        } catch is CancellationError {}
        #expect(try Data(contentsOf: fixture.file).first == 97)
        try await fixture.document.save(revision: 1)
        #expect(try Data(contentsOf: fixture.file).first == 120)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["large.log"])
    }
    @Test func externalChangesAndReadOnlyModeNeverGetOverwritten() async throws {
        let fixture = try Fixture(String(repeating: "a", count: 180_000))
        _ = try await fixture.document.open()
        try await fixture.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        try Data("external".utf8).write(to: fixture.file)
        do {
            try await fixture.document.save(revision: 1)
            Issue.record("Conflict saved")
        } catch let error as WorkspaceFailure { #expect(error.code == "external_change") }
        #expect(try Data(contentsOf: fixture.file) == Data("external".utf8))
        let readOnly = try Fixture(String(repeating: "a", count: 180_000))
        _ = try await readOnly.document.open()
        try await readOnly.document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readOnly.file.path)
        do {
            try await readOnly.document.save(revision: 1)
            Issue.record("Read-only saved")
        } catch {}
        #expect(try Data(contentsOf: readOnly.file).first == 97)
    }
    @Test func previewAboveOneMiBUsesWholeDocumentAndNeverJustCurrentPage() async throws {
        let text =
            "<html><body><pre>" + String(repeating: "x", count: 1_100_000) + "</pre><p>END-MARKER</p></body></html>"
        let fixture = try Fixture(text, name: "large.html")
        _ = try await fixture.document.open()
        let content = try await fixture.document.markup(revision: 0, markdown: false)
        #expect(content.html == text && content.html.contains("END-MARKER"))
        let snippet = try await fixture.document.syntax(revision: 0, range: NSRange(location: 0, length: 100))
        #expect(snippet.language == "HTML" && !snippet.spans.isEmpty)
    }
    @Test func pendingInputReservationsCannotBeSpentTwiceOrResetByOldReplies() {
        var budget = LargeEditBudget(bytes: 10, pieces: 8)
        #expect(budget.permits(bytes: 6))
        budget.reserve(revision: 1, bytes: 6)
        #expect(!budget.permits(bytes: 5))
        budget.reserve(revision: 2, bytes: 3)
        budget.acknowledge(bytes: 4, pieces: 6, revision: 1)
        #expect(budget.bytes == 1 && budget.pieces == 3 && budget.hasPendingEdits)
        budget.acknowledge(bytes: 9, pieces: 8, revision: 0)
        #expect(budget.bytes == 1 && budget.pieces == 3)
        budget.acknowledge(bytes: 10, pieces: 8, revision: 2)
        #expect(budget.bytes == 10 && budget.pieces == 8 && !budget.hasPendingEdits)
    }
    @Test func committedSaveFailureIsDistinguishedFromFailureBeforeRename() throws {
        let fixture = try Fixture(String(repeating: "a", count: 180_000))
        let version = try TextFileIO.withLargeFile(root: fixture.root, path: "large.log") { _, version in version }
        do {
            _ = try TextFileIO.saveLarge(root: fixture.root, path: "large.log", expected: version, cancellation: nil) {
                fd in
                let bytes = Array("committed".utf8)
                let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                #expect(written == bytes.count)
            } committed: { _ in
                throw WorkspaceFailure(code: "injected", message: "fixture rebase failure")
            }
            Issue.record("Missing post-commit failure")
        } catch let failure as WorkspaceFailure { #expect(failure.code == "save_committed_rebase") }
        #expect(try Data(contentsOf: fixture.file) == Data("committed".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["large.log"])
    }

    @Test func syntaxProjectionNeedsNoDocumentOrDiskQueueAndKeepsPageUTF16Positions() async throws {
        let worker = SyntaxFragmentWorker()
        let text = "// 😀\nfinal message = 'hello';"
        let value = try await worker.highlight(text: text, path: "large.dart", start: 400)
        #expect(value.status == "windowed" && value.start == 400)
        #expect(value.spans.contains { $0.style.hasPrefix("string") })
        #expect(value.spans.allSatisfy { $0.start >= 400 && $0.start + $0.length <= 400 + text.utf16.count })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.highlight(text: text, path: "large.dart", start: 0)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled parser ran")
        } catch is CancellationError {}
    }

}
