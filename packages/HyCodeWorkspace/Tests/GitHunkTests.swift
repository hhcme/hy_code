import Foundation
import Testing

@testable import HyCodeWorkspace

struct GitHunkTests {
    @Test func restoreAndPartialCompositionKeepCRLFUnicodeAndUnterminatedEOF() throws {
        let left = "😀old\r\nkeep\r\nlast"
        let right = "😀new\r\nkeep\r\nlast\r\nadded"
        let rows = try GitDiffParser.rows(
            "@@ -1,3 +1,4 @@\n-😀old\r\n+😀new\r\n keep\r\n-last\n+last\r\n+added\n\\ No newline at end of file\n")
        let comparison = try GitTextComparison.make(left: left, right: right, rows: rows)
        #expect(comparison.blocks.count == 2)
        let a = try #require(comparison.blocks.first)
        let b = try #require(comparison.blocks.last)
        let edit = try GitBlockEdit.restoring(b.id, in: comparison)
        #expect(edit.expected == "last\r\nadded" && edit.replacement == "last")
        #expect(
            (right as NSString).replacingCharacters(in: edit.range, with: edit.replacement) == "😀new\r\nkeep\r\nlast")
        #expect(
            try GitPartialSelection.contents(comparison, selecting: [a.id], bom: true)
                == Data([0xef, 0xbb, 0xbf]) + Data("😀new\r\nkeep\r\nlast".utf8))
        #expect(
            try GitPartialSelection.contents(comparison, selecting: [b.id], bom: false)
                == Data("😀old\r\nkeep\r\nlast\r\nadded".utf8))
        #expect(throws: GitFailure.self) { try GitBlockEdit.restoring(-1, in: comparison) }
        #expect(throws: GitFailure.self) { try GitPartialSelection.contents(comparison, selecting: [], bom: false) }
        #expect(throws: GitFailure.self) {
            try GitPartialSelection.contents(comparison, selecting: [a.id], bom: false, maximumBytes: 1)
        }
    }

    @Test func insertionAndDeletionRestoreAtActualEmptyAnchors() throws {
        let rows = try GitDiffParser.rows("@@ -1,3 +1,3 @@\n-old\n keep\n tail\n+added\n")
        let comparison = try GitTextComparison.make(left: "old\nkeep\ntail\n", right: "keep\ntail\nadded\n", rows: rows)
        let deletion = try GitBlockEdit.restoring(comparison.blocks[0].id, in: comparison)
        #expect(deletion.range == NSRange(location: 0, length: 0) && deletion.replacement == "old\n")
        let insertion = try GitBlockEdit.restoring(comparison.blocks[1].id, in: comparison)
        #expect(insertion.expected == "added\n" && insertion.replacement == "")
        #expect(
            try GitPartialSelection.contents(comparison, selecting: [comparison.blocks[0].id], bom: false)
                == Data("keep\ntail\n".utf8))
        #expect(
            try GitPartialSelection.contents(comparison, selecting: [comparison.blocks[1].id], bom: false)
                == Data("old\nkeep\ntail\nadded\n".utf8))
    }

    @Test func aggregateCandidatesAreBoundedBeforeCommitPreparation() throws {
        let part = GitPartialSelection(
            blocks: [1], contents: Data(count: 8_388_608), mode: "100644", preserveIndex: false)
        let selection = GitSelection(
            path: "a", paths: ["a"], head: nil, indexDigest: "", diskDigests: [:],
            indexObject: "", headObject: "", bothLayersChanged: false, partial: part)
        #expect(try GitPartialSelection.retainedBytes(Array(repeating: selection, count: 4)) == 33_554_432)
        #expect(throws: GitFailure.self) {
            try GitPartialSelection.retainedBytes(Array(repeating: selection, count: 5))
        }
    }
}
