import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

struct TextDocumentTests {
    @Test func blockRestoreAndInverseUseRevisionBoundNativeTextDeltas() async throws {
        let body = "😀changed\r\nkeep\r\nlast"
        let fixture = try Fixture(Data([0xef, 0xbb, 0xbf]) + Data(body.utf8))
        let document = fixture.document()
        _ = try await document.open()
        let rows = try GitDiffParser.rows(
            "@@ -1,3 +1,3 @@\n-😀base\r\n+😀changed\r\n keep\r\n last\n\\ No newline at end of file\n")
        let comparison = try GitTextComparison.make(left: "😀base\r\nkeep\r\nlast", right: body, rows: rows)
        let block = try #require(comparison.blocks.first)
        let edit = try GitBlockEdit.restoring(block.id, in: comparison)
        try await document.replace(expected: 0, range: edit.range, text: edit.replacement)
        #expect(try await document.textSnapshot(revision: 1) == comparison.left.text)
        await #expect(throws: WorkspaceFailure.self) {
            try await document.replace(expected: 0, range: edit.range, text: edit.replacement)
        }
        try await document.replace(
            expected: 1, range: NSRange(location: edit.range.location, length: edit.replacement.utf16.count),
            text: edit.expected)
        #expect(try await document.textSnapshot(revision: 2) == body)
        try await document.save(revision: 2)
        #expect(try Data(contentsOf: fixture.file) == Data([0xef, 0xbb, 0xbf]) + Data(body.utf8))
    }
    @Test func revisionBoundSnapshotsKeepEncodingBOMAndLiteralLeadingFEFFWithoutSaving() async throws {
        for (encoding, bom) in [
            (String.Encoding.utf8, Data()), (.utf8, Data([0xef, 0xbb, 0xbf])),
            (.utf16LittleEndian, Data([0xff, 0xfe])), (.utf16BigEndian, Data([0xfe, 0xff])),
        ] {
            let original = bom + "中😀\r\n".data(using: encoding)!
            let fixture = try Fixture(original)
            let document = fixture.document()
            _ = try await document.open()
            try await document.replace(expected: 0, range: NSRange(location: 0, length: 0), text: "\u{feff}")
            #expect(try await document.textSnapshot(revision: 1) == "\u{feff}中😀\r\n")
            await #expect(throws: WorkspaceFailure.self) { try await document.textSnapshot(revision: 0) }
            #expect(try Data(contentsOf: fixture.file) == original)
            try await document.save(revision: 1)
            #expect(try Data(contentsOf: fixture.file) == bom + "\u{feff}中😀\r\n".data(using: encoding)!)
        }
    }
    private final class Fixture {
        let root: URL
        let file: URL
        init(_ data: Data = Data("abc".utf8)) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "hycode-text-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            file = root.appendingPathComponent("file.txt", isDirectory: false)
            try data.write(to: file)
        }
        deinit { try? FileManager.default.removeItem(at: root) }
        func document() -> NativeTextDocument { NativeTextDocument(root: root, path: "file.txt") }
    }
    @Test func unicodeIncrementalEditingAndNativeUndoDeltasPreserveBOMAndCRLF() async throws {
        let original = Data([0xef, 0xbb, 0xbf]) + Data("a😀中\r\n".utf8)
        let fixture = try Fixture(original)
        let document = fixture.document()
        let content = try await document.open()
        #expect(content.text == "a😀中\r\n")
        #expect(content.hasBOM && content.lineEnding == "CRLF")
        try await document.replace(expected: 0, range: NSRange(location: 1, length: 2), text: "你好")
        try await document.save(revision: 1)
        #expect(try Data(contentsOf: fixture.file) == Data([0xef, 0xbb, 0xbf]) + Data("a你好中\r\n".utf8))
        try await document.replace(expected: 1, range: NSRange(location: 1, length: 2), text: "😀")
        try await document.save(revision: 2)
        #expect(try Data(contentsOf: fixture.file) == original)
    }
    @Test func utf16FilesKeepOriginalEncodingAndBOM() async throws {
        for (encoding, bom) in [
            (String.Encoding.utf16LittleEndian, Data([0xff, 0xfe])), (.utf16BigEndian, Data([0xfe, 0xff])),
        ] {
            let fixture = try Fixture(bom + "中\r\n".data(using: encoding)!)
            let document = fixture.document()
            let content = try await document.open()
            #expect(content.text == "中\r\n")
            try await document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "😀")
            try await document.save(revision: 1)
            #expect(try Data(contentsOf: fixture.file) == bom + "😀\r\n".data(using: encoding)!)
        }
    }
    @Test func externalChangesAreNeverReplacedAndBufferRemainsEditable() async throws {
        let fixture = try Fixture()
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 3), text: "local")
        try Data("external".utf8).write(to: fixture.file)
        do {
            try await document.save(revision: 1)
            Issue.record("Conflicting save succeeded")
        } catch let error as WorkspaceFailure { #expect(error.code == "external_change") }
        #expect(try Data(contentsOf: fixture.file) == Data("external".utf8))
        try await document.replace(expected: 1, range: NSRange(location: 5, length: 0), text: "!")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["file.txt"])
    }
    @Test func invalidOrOldEditsDoNotMutateTheDocument() async throws {
        let fixture = try Fixture(Data("😀".utf8))
        let document = fixture.document()
        _ = try await document.open()
        do {
            try await document.replace(expected: 0, range: NSRange(location: 1, length: 1), text: "x")
            Issue.record("Split surrogate accepted")
        } catch let error as WorkspaceFailure { #expect(error.code == "invalid_range") }
        do {
            try await document.save(revision: 1)
            Issue.record("Old revision accepted")
        } catch let error as WorkspaceFailure { #expect(error.code == "stale_revision") }
        try await document.save(revision: 0)
        #expect(try Data(contentsOf: fixture.file) == Data("😀".utf8))
    }
    @Test func symlinksAndParentTraversalAreRejected() async throws {
        let fixture = try Fixture()
        let outside = try Fixture(Data("private".utf8))
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("link"), withDestinationURL: outside.root)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("alias"), withDestinationURL: outside.file)
        for path in ["../file.txt", "/file.txt", "link/file.txt", "alias"] {
            let document = NativeTextDocument(root: fixture.root, path: path)
            do {
                _ = try await document.open()
                Issue.record("Unsafe path accepted: \(path)")
            } catch {}
        }
        #expect(try Data(contentsOf: outside.file) == Data("private".utf8))
    }
    @Test func savesPreservePermissionsAndExtendedAttributes() async throws {
        let fixture = try Fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: fixture.file.path)
        let attribute = Data("fixture-metadata".utf8)
        let result = attribute.withUnsafeBytes {
            setxattr(fixture.file.path, "com.hycode.editor-test", $0.baseAddress, $0.count, 0, 0)
        }
        #expect(result == 0)
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 3, length: 0), text: "!")
        try await document.save(revision: 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        var read = [UInt8](repeating: 0, count: 64)
        let count = getxattr(fixture.file.path, "com.hycode.editor-test", &read, read.count, 0, 0)
        #expect(count == attribute.count)
        #expect(Data(read.prefix(max(0, count))) == attribute)
    }
    @Test func readOnlyFilesFailSavingWithoutChangingOriginalOrLeavingTemporaryFiles() async throws {
        let fixture = try Fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.file.path)
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        do {
            try await document.save(revision: 1)
            Issue.record("Read-only save accepted")
        } catch let error as WorkspaceFailure { #expect(error.code == "read_only") }
        #expect(try Data(contentsOf: fixture.file) == Data("abc".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == ["file.txt"])
    }
    @Test func separateDocumentsCannotOverwriteEachOthersCommittedVersion() async throws {
        let fixture = try Fixture()
        let first = fixture.document()
        let second = fixture.document()
        _ = try await first.open()
        _ = try await second.open()
        try await first.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "1")
        try await second.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "2")
        try await first.save(revision: 1)
        do {
            try await second.save(revision: 1)
            Issue.record("Stale disk baseline accepted")
        } catch let error as WorkspaceFailure { #expect(error.code == "external_change") }
        #expect(try Data(contentsOf: fixture.file) == Data("1bc".utf8))
    }
    @Test func completionOfAnOlderSaveKeepsNewerTypingDirty() {
        var state = DocumentEditState()
        #expect(!state.isDirty)
        state.edited()
        let saving = state.revision
        state.edited()
        state.saved(saving)
        #expect(state.isDirty && state.savedRevision == 1)
        state.saved(999)
        #expect(state.isDirty)
        state.saved(2)
        #expect(!state.isDirty)
    }
    @Test func cancelledSaveDoesNotWriteOrLoseTheBuffer() async throws {
        let fixture = try Fixture()
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        let cancellation = DocumentSaveCancellation()
        cancellation.cancel()
        do {
            try await document.save(revision: 1, cancellation: cancellation)
            Issue.record("Cancelled save wrote")
        } catch is CancellationError {}
        #expect(try Data(contentsOf: fixture.file) == Data("abc".utf8))
        try await document.save(revision: 1)
        #expect(try Data(contentsOf: fixture.file) == Data("xbc".utf8))
    }
    @Test func ownerWithoutWritePermissionIsNotGrantedTheOtherUsersWriteBit() async throws {
        if geteuid() == 0 { return }  // root deliberately has different kernel access semantics.
        let fixture = try Fixture()
        try FileManager.default.setAttributes([.posixPermissions: 0o446], ofItemAtPath: fixture.file.path)
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        do {
            try await document.save(revision: 1)
            Issue.record("Owner without write was replaced")
        } catch {}
        #expect(try Data(contentsOf: fixture.file) == Data("abc".utf8))
    }
    @Test func aclDenyWriteIsRespectedEvenWhenModeBitsAllowIt() async throws {
        let fixture = try Fixture()
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod", isDirectory: false)
        chmod.arguments = ["+a", "\(NSUserName()) deny write", fixture.file.path]
        try chmod.run()
        chmod.waitUntilExit()
        #expect(chmod.terminationStatus == 0)
        let document = fixture.document()
        _ = try await document.open()
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 1), text: "x")
        do {
            try await document.save(revision: 1)
            Issue.record("ACL-protected file was replaced")
        } catch {}
        #expect(try Data(contentsOf: fixture.file) == Data("abc".utf8))
    }
    @Test func specialFilesAndHardLinksAreNotEditable() async throws {
        let fixture = try Fixture()
        let fifo = fixture.root.appendingPathComponent("pipe", isDirectory: false)
        #expect(mkfifo(fifo.path, 0o600) == 0)
        try FileManager.default.linkItem(
            at: fixture.file, to: fixture.root.appendingPathComponent("hard", isDirectory: false))
        for path in ["pipe", "file.txt", "hard"] {
            let document = NativeTextDocument(root: fixture.root, path: path)
            do {
                _ = try await document.open()
                Issue.record("Non-regular/linked file opened: \(path)")
            } catch {}
        }
    }
}
