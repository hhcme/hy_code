import Foundation
import Testing

@testable import HyCodeWorkspace

struct LSPSnippetTests {
    @Test func defaultsChoiceFinalStopAndUnicodeUseUtf16() throws {
        let value = try LSPSnippet.expand("😀${1:name}(${2|one,two|})$0")
        #expect(value.text == "😀name(one)")
        #expect(
            value.stops == [
                NSRange(location: 2, length: 4), NSRange(location: 7, length: 3), NSRange(location: 11, length: 0),
            ])
    }
    @Test func escapedSymbolsVariablesAndRepeatedDefaultsDoNotReadEnvironment() throws {
        let value = try LSPSnippet.expand(#"\$${1:tag} $1 ${HOME} ${UNKNOWN:fallback}"#)
        #expect(value.text == "$tag tag  fallback")
        #expect(value.stops.count == 2)
    }
    @Test func nestedDefaultsPreservePlaceholderOrder() throws {
        let value = try LSPSnippet.expand("${2:call(${1:value})}$0")
        #expect(value.text == "call(value)")
        #expect(value.stops.first == NSRange(location: 5, length: 5))
    }
    @Test func malformedTransformAndOversizedTemplatesAreNotInsertedLiterally() {
        for source in ["${1:missing", "${1/old/new/}", "${100:value}", String(repeating: "x", count: 65_537)] {
            #expect(throws: LanguageServiceFailure.self) { try LSPSnippet.expand(source) }
        }
    }
    @Test func bareNumberStopsDoNotConsumeFollowingIdentifierAndTypingMovesLaterStops() throws {
        #expect(try LSPSnippet.expand("${1:tag} $1Suffix").text == "tag tagSuffix")
        let value = try LSPSnippet.expand("foo(${1:value}, ${2:other})$0")
        var session = LSPSnippetSession(ranges: value.stops)
        session.replace(NSRange(location: 4, length: 5), count: 2)
        #expect(session.current == NSRange(location: 4, length: 2))
        #expect(
            session.advance(backward: false, selection: NSRange(location: 6, length: 0))
                == NSRange(location: 8, length: 5))
        #expect(
            session.advance(backward: true, selection: NSRange(location: 8, length: 5))
                == NSRange(location: 4, length: 2))
        session.replace(NSRange(location: 0, length: 0), count: 1)
        #expect(session.current == nil)
    }
}
