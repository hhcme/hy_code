import Foundation
import Testing

@testable import HyCodeWorkspace

struct LanguageProtocolTests {
    @Test func diagnosticRetainsProviderDataForCodeActionRoundTrip() throws {
        let raw = JSONValue([
            "range": ["start": ["line": 0, "character": 0], "end": ["line": 0, "character": 2]],
            "message": "unknown property", "source": "vue", "severity": 1,
            "data": ["pluginIndex": 2, "version": 7, "original": ["code": 123]], "hycodeService": "vue",
        ])
        let diagnostic = try raw.decode(LSPDiagnostic.self)
        #expect(diagnostic.raw == raw)
        #expect(diagnostic.raw["data"]["pluginIndex"].int == 2)
    }
    @Test func nativeCRLFEdgeEditsRemainExactlyEquivalentInTheProtocol() throws {
        let text = "中😀\r\nnext\r\nend" as NSString
        let index = TextLineIndex(text as String, unicodeLineSeparators: false)
        for (range, replacement) in [
            (NSRange(location: 3, length: 1), ""),  // delete CR, preserve LF
            (NSRange(location: 4, length: 1), ""),  // delete LF, preserve CR
            (NSRange(location: 4, length: 0), "插入"),  // insert between CR/LF
            (NSRange(location: 4, length: 6), "x"),  // split both pairs
        ] {
            let change = try #require(LSPDocumentChange(source: text, range: range, replacement: replacement))
            let edit = LSPTextEdit(
                range: LSPRange(
                    start: .at(change.range.location, in: index), end: .at(NSMaxRange(change.range), in: index)),
                newText: change.text)
            let expected = text.replacingCharacters(in: range, with: replacement)
            #expect(try LSPTextEdits.apply([edit], to: text as String) == expected)
        }
        #expect(LSPDocumentChange(source: text, range: NSRange(location: Int.max, length: 1), replacement: "") == nil)
    }
    @Test func editBatchIsValidatedBeforeMutationAndCompletionCaretAccountsForImports() throws {
        let text = "void main() { pri; }\n"
        let insert = LSPTextEdit(
            range: LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 0)),
            newText: "// added\n")
        let completion = LSPTextEdit(
            range: LSPRange(start: .init(line: 0, character: 14), end: .init(line: 0, character: 17)),
            newText: "print('中')")
        let result = try LSPTextEdits.apply([insert, completion], to: text)
        #expect(result == "// added\nvoid main() { print('中'); }\n")
        let caret = try LSPTextEdits.completionOffset(primary: completion, additional: [insert], text: text)
        #expect((result as NSString).substring(to: caret).hasSuffix("print('中')"))
        #expect(throws: (any Error).self) { try LSPTextEdits.apply([completion, completion], to: text) }
        #expect(text == "void main() { pri; }\n")
    }
    @Test func autoImportAtCompletionStartKeepsReplacementAndCaretCorrect() throws {
        let start = LSPPosition(line: 0, character: 0)
        let main = LSPTextEdit(range: LSPRange(start: start, end: .init(line: 0, character: 3)), newText: "greet")
        let added = LSPTextEdit(
            range: LSPRange(start: start, end: start), newText: "import { greet } from './helper';\n")
        let result = try LSPTextEdits.apply([added, main], to: "gre")
        #expect(result == "import { greet } from './helper';\ngreet")
        #expect(try LSPTextEdits.apply([main, added], to: "gre") == result)
        #expect(
            try LSPTextEdits.completionOffset(primary: main, additional: [added], text: "gre") == result.utf16.count)
        #expect(throws: LanguageServiceFailure.self) { try LSPTextEdits.apply([main, main, added], to: "gre") }
    }
    @Test func framingSurvivesEveryByteBoundaryAndMultipleMessages() throws {
        let a = JSONValue(["jsonrpc": "2.0", "id": 1, "result": ["text": "中文😀"]])
        let b = JSONValue(["method": "ready", "params": JSONValue(["uri": "file:///a.dart"])])
        let data = try LSPFraming.encode(a) + LSPFraming.encode(b)
        var frame = LSPFraming()
        var messages: [JSONValue] = []
        for byte in data { messages += try frame.append(Data([byte])) }
        #expect(messages == [a, b])
        #expect(b["params"]["uri"].string == "file:///a.dart")
    }
    @Test func invalidLengthsAndOversizedHeadersAreRejected() {
        for text in [
            "Content-Length: -1\r\n\r\n", "Content-Length: 9000000\r\n\r\n",
            "Content-Length: 1\r\nContent-Length: 1\r\n\r\nx", String(repeating: "x", count: 8193),
        ] {
            var frame = LSPFraming()
            #expect(throws: (any Error).self) { try frame.append(Data(text.utf8)) }
        }
    }
    @Test func protocolPositionsUseUTF16AndCRLFWithoutCountingUnicodeSeparatorsAsLines() throws {
        let text = "😀中\r\nnext\u{2028}word\n" as NSString
        var index = TextLineIndex(text as String, unicodeLineSeparators: false)
        #expect(index.count == 3)
        #expect(LSPPosition.at(6, in: index) == LSPPosition(line: 1, character: 1))
        #expect(LSPPosition(line: 0, character: 1).offset(in: index, source: text) == nil)
        #expect(LSPPosition(line: 0, character: 3).offset(in: index, source: text) == 3)
        #expect(LSPPosition(line: 0, character: 4).offset(in: index, source: text) == nil)
        #expect(LSPPosition(line: 1, character: 5).offset(in: index, source: text) == 10)
        index.replace(in: text, range: NSRange(location: 5, length: 0), with: "new\r\n")
        #expect(index.count == 4)
        #expect(index.start(of: 2) == 10)
    }
    @Test func locationsAcceptLinksAndSingleOrMultipleResults() throws {
        let range = JSONValue(["start": ["line": 1, "character": 2], "end": ["line": 1, "character": 4]])
        let link = JSONValue(["targetUri": "file:///dep.dart", "targetSelectionRange": range])
        let values = try LSPLocation.locations(.array([link]))
        #expect(values.first?.range.start.line == 1)
        let single = JSONValue(["uri": "file:///a.dart", "range": range])
        #expect(try LSPLocation.locations(single).count == 1)
        #expect(try LSPLocation.locations(.null).isEmpty)
    }
}
