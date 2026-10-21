import Foundation
import Testing

@testable import HyCodeWorkspace

struct TextLineIndexTests {
    @Test func repeatedEditsAtOneLocationKeepIndexStorageBounded() {
        let text = NSMutableString(string: String(repeating: "x\n", count: 2048))
        var index = TextLineIndex(text as String)
        for _ in 0..<2000 {
            index.replace(in: text, range: NSRange(location: 0, length: 0), with: "\n")
            text.insert("\n", at: 0)
        }
        #expect(index.allocatedBlockCount <= 2 + (index.count + 255) / 256)
        for _ in 0..<1500 {
            let range = NSRange(location: 0, length: 1)
            index.replace(in: text, range: range, with: "")
            text.deleteCharacters(in: range)
        }
        #expect(index.allocatedBlockCount <= 2 + (index.count + 255) / 256)
        let fresh = TextLineIndex(text as String)
        #expect(index.count == fresh.count)
        #expect((0..<index.count).allSatisfy { index.start(of: $0) == fresh.start(of: $0) })
    }
    @Test func sparseEditsAcrossManyLinesKeepOffsetsAndCRLFBoundaries() {
        let text = NSMutableString(string: String(repeating: "x\r\n", count: 200_000))
        var index = TextLineIndex(text as String)
        for location in [0, 1536, 300_000, text.length - 1] {
            let range = NSRange(location: location, length: 1)
            index.replace(in: text, range: range, with: "😀\n")
            text.replaceCharacters(in: range, with: "😀\n")
        }
        let fresh = TextLineIndex(text as String)
        #expect(index.count == fresh.count)
        for line in [0, 1, 511, 512, 100_000, index.count - 1] {
            #expect(index.start(of: line) == fresh.start(of: line))
            #expect(index.line(at: index.start(of: line)) == line)
        }
    }
    @Test func emptyTrailingAndMixedUnicodeLines() {
        let index = TextLineIndex("a😀\r\n中\rnext\n\u{2028}")
        #expect(index.count == 5)
        #expect((0..<index.count).map { index.start(of: $0) } == [0, 5, 7, 12, 13])
        #expect(index.line(at: 4) == 0)
        #expect(index.line(at: 5) == 1)
        #expect(TextLineIndex().count == 1)
    }
    @Test func incrementalIndexMatchesRebuildAcrossCRLFAndEmojiEdits() {
        let text = NSMutableString(string: "a\r\nb\r\nc😀\n")
        var index = TextLineIndex(text as String)
        var random: UInt64 = 17
        let fragments = ["", "x", "\r", "\n", "\r\n", "😀", "中\u{2028}"]
        for _ in 0..<600 {
            random = random &* 6_364_136_223_846_793_005 &+ 1
            let boundaries = (0...text.length).filter { i in
                i == 0 || i == text.length || !(0xdc00...0xdfff).contains(text.character(at: i))
            }
            let a = boundaries[Int(random % UInt64(boundaries.count))]
            let next = boundaries[min(boundaries.count - 1, boundaries.firstIndex(of: a)! + 1)]
            let range = NSRange(location: a, length: random & 8 == 0 ? next - a : 0)
            let fragment = fragments[Int((random >> 16) % UInt64(fragments.count))]
            index.replace(in: text, range: range, with: fragment)
            text.replaceCharacters(in: range, with: fragment)
            let rebuilt = TextLineIndex(text as String)
            #expect(index.count == rebuilt.count)
            #expect((0..<index.count).map { index.start(of: $0) } == (0..<rebuilt.count).map { rebuilt.start(of: $0) })
        }
    }
}
