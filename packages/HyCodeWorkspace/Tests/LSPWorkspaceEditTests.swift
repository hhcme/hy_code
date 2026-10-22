import Foundation
import Testing

@testable import HyCodeWorkspace

struct LSPWorkspaceEditTests {
    private func edit(_ text: String = "total") -> JSONValue {
        JSONValue([
            "range": ["start": ["line": 0, "character": 6], "end": ["line": 0, "character": 11]], "newText": text,
        ])
    }
    @Test func multiFileChangesAndVersionedEditsPreserveOneSourceRevision() throws {
        let root = URL(fileURLWithPath: "/tmp/hycode-workspace-tests")
        let uri = root.appendingPathComponent("main.ts").absoluteString
        let result = try LSPWorkspaceEdits.parse(.object(["changes": .object([uri: .array([edit()])])]), root: root)
        #expect(result.count == 1 && result[0].path == "main.ts" && result[0].version == nil)
        #expect(try LSPTextEdits.apply(result[0].edits, to: "const count = 1") == "const total = 1")
        let plan = JSONValue(["documentChanges": [["textDocument": ["uri": uri, "version": 7], "edits": [edit()]]]])
        #expect(try LSPWorkspaceEdits.parse(plan, root: root)[0].version == 7)
        let preview = try LSPWorkspaceEdits.preview(result[0].edits, text: "const count = 1")
        #expect(preview.contains("@@ 1:7 @@") && preview.contains("- count") && preview.contains("+ total"))
    }
    @Test func unsupportedResourceOperationsRemoteTargetsAndNullTextAreRejected() {
        let root = URL(fileURLWithPath: "/tmp/hycode-workspace-tests")
        for uri in ["https://example.com/main.ts", "file://remote/main.ts", "file:///tmp/outside.ts"] {
            #expect(throws: LanguageServiceFailure.self) {
                try LSPWorkspaceEdits.parse(.object(["changes": .object([uri: .array([edit()])])]), root: root)
            }
        }
        let resource = JSONValue([
            "documentChanges": [["kind": "rename", "oldUri": "file:///tmp/a", "newUri": "file:///tmp/b"]]
        ])
        #expect(throws: LanguageServiceFailure.self) { try LSPWorkspaceEdits.parse(resource, root: root) }
        let uri = root.appendingPathComponent("main.ts").absoluteString
        #expect(throws: LanguageServiceFailure.self) {
            try LSPWorkspaceEdits.parse(.object(["changes": .object([uri: .array([edit("\0")])])]), root: root)
        }
    }
    @Test func symlinksCannotEscapeGrantedRootAndDuplicateAliasesFail() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
        let uri = root.appendingPathComponent("outside/main.ts").absoluteString
        #expect(throws: LanguageServiceFailure.self) {
            try LSPWorkspaceEdits.parse(.object(["changes": .object([uri: .array([edit()])])]), root: root)
        }
        let duplicate = JSONValue([
            "documentChanges": [
                ["textDocument": ["uri": root.appendingPathComponent("a.ts").absoluteString], "edits": [edit()]],
                ["textDocument": ["uri": root.appendingPathComponent("a.ts").absoluteString], "edits": [edit()]],
            ]
        ])
        #expect(throws: LanguageServiceFailure.self) { try LSPWorkspaceEdits.parse(duplicate, root: root) }
    }
    @Test func overlappingUnicodeInvalidRangesAndOversizePreviewNeverProduceReplacement() {
        let bad = LSPTextEdit(
            range: LSPRange(start: LSPPosition(line: 0, character: 1), end: LSPPosition(line: 0, character: 2)),
            newText: "ok")
        #expect(throws: LanguageServiceFailure.self) { try LSPTextEdits.apply([bad], to: "😀") }
        #expect(throws: LanguageServiceFailure.self) { try LSPWorkspaceEdits.preview([bad], text: "😀") }
        let valid = LSPTextEdit(
            range: LSPRange(start: LSPPosition(line: 0, character: 0), end: LSPPosition(line: 0, character: 0)),
            newText: String(repeating: "x", count: 262_145))
        #expect(throws: LanguageServiceFailure.self) { try LSPWorkspaceEdits.preview([valid], text: "") }
        #expect(throws: LanguageServiceFailure.self) { try LSPTextEdits.apply([valid, valid], to: "") }
    }
    @Test func untrustedVueRequestNeverStartsConfiguredExecutable() async {
        let tools = WebToolchain(
            node: URL(fileURLWithPath: "/must/not/run"), services: URL(fileURLWithPath: "/missing"))
        let server = WebLanguageServer(root: URL(fileURLWithPath: "/tmp"), tools: tools)
        await #expect(throws: LanguageServiceFailure.self) {
            try await server.open(uri: "file:///tmp/main.vue", language: .vue, text: "<template/>", version: 0)
        }
        await server.stop()
    }
}
