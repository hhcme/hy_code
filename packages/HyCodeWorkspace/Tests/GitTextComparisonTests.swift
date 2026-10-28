import Foundation
import Testing

@testable import HyCodeWorkspace

struct GitTextComparisonTests {
    @Test func eofNotesDoNotConsumeSourceRowBudgetForExactContextOrDenseReplacement() throws {
        let context =
            "@@ -1,20000 +1,20000 @@\n" + String(repeating: " same\n", count: 20_000)
            + "\\ No newline at end of file\n"
        let exact = try GitDiffParser.rows(context)
        #expect(exact.filter { $0.kind != .note }.count == 20_000 && exact.last?.kind == .note)
        let patch =
            "@@ -1,10000 +1,10000 @@\n" + String(repeating: "-before\n", count: 10_000)
            + "\\ No newline at end of file\n" + String(repeating: "+after\n", count: 10_000)
            + "\\ No newline at end of file\n"
        let dense = try GitDiffParser.rows(patch)
        #expect(dense.count == 10_001 && dense.last?.left != nil && dense.last?.right != nil)
        #expect(throws: GitFailure.self) {
            try GitDiffParser.rows(
                "@@ -1 +1 @@\n same\n" + String(repeating: "\\ No newline at end of file\n", count: 33))
        }
    }
    @Test func cleanButStaleBufferCannotApproveAnUnseenDiskCandidateAndOldRepliesStayRejected() {
        var review = GitBufferReview()
        let document = UUID()
        let first = review.begin(document: document, revision: 0)
        review.accept(first, buffer: "old", saved: "externally changed", dirty: false)
        #expect(!review.canSelect(document: document, revision: 0, dirty: false))
        let current = review.begin(document: document, revision: 1)
        review.accept(first, buffer: "old", saved: "old", dirty: false)
        #expect(!review.canSelect(document: document, revision: 0, dirty: false))
        review.accept(current, buffer: "same", saved: "same", dirty: false)
        #expect(review.canSelect(document: document, revision: 1, dirty: false))
        #expect(!review.canSelect(document: UUID(), revision: 1, dirty: false))
        #expect(!review.canSelect(document: document, revision: 2, dirty: false))
        #expect(!review.canSelect(document: document, revision: 1, dirty: true))
        review.invalidate()
        review.accept(current, buffer: "same", saved: "same", dirty: false)
        #expect(!review.canSelect(document: document, revision: 1, dirty: false))
        let composed = review.begin(document: document, revision: 2)
        review.accept(composed, buffer: "\u{e9}", saved: "e\u{301}", dirty: false)
        #expect(!review.canSelect(document: document, revision: 2, dirty: false))
    }

    @Test func canonicallyEquivalentTextStillHasDistinctUTF16PresentationAndLiteralCopy() throws {
        let a = "\u{e9}"
        let b = "e\u{301}"
        let rowsA = try GitDiffParser.rows("@@ -1 +1 @@\n \(a)\n\\ No newline at end of file\n")
        let rowsB = try GitDiffParser.rows("@@ -1 +1 @@\n \(b)\n\\ No newline at end of file\n")
        let first = try GitTextComparison.make(left: a, right: a, rows: rowsA)
        let second = try GitTextComparison.make(left: b, right: b, rows: rowsB)
        #expect(first.left != second.left)
        #expect(first.left.text.utf16.count == 1 && second.left.text.utf16.count == 2)
    }
    @Test func alignmentUsesRealUTF16OffsetsWithoutPaddingTheSource() throws {
        let before = "first\r\n中😀\r\nlast"
        let after = "insert\r\nfirst\r\nchanged\r\nlast"
        let rows = try GitDiffParser.rows(
            "@@ -1,3 +1,4 @@\n+insert\r\n first\r\n-中😀\r\n+changed\r\n last\n\\ No newline at end of file\n")
        let comparison = try GitTextComparison.make(left: before, right: after, rows: rows)
        #expect(comparison.left.text == before && comparison.right.text == after)
        #expect(comparison.left.lines.map(\.row) == [1, 2, 3])
        #expect(comparison.left.lines.map(\.gapBefore) == [1, 0, 0])
        #expect(comparison.right.lines.map(\.offset) == [0, 8, 15, 24])
        for side in [comparison.left, comparison.right] {
            #expect(side.index.count == side.lines.count)
            for (index, line) in side.lines.enumerated() {
                #expect(side.index.start(of: index) == line.offset)
                #expect(side.line(at: line.offset) == index)
            }
        }
        #expect((comparison.left.text as NSString).substring(with: NSRange(location: 7, length: 4)) == "中😀\r")
    }

    @Test func emptyBaselineAndEOFStayLiteralAndSelectable() throws {
        let after = "a\nb\n"
        let rows = try GitDiffParser.rows("@@ -0,0 +1,2 @@\n+a\n+b\n")
        let comparison = try GitTextComparison.make(left: "", right: after, rows: rows)
        #expect(comparison.left.text.isEmpty)
        #expect(comparison.right.text == after)
        #expect(comparison.left.lines.first?.row == comparison.right.lines.last?.row)
        #expect(comparison.right.lines.last?.offset == after.utf16.count)
        let removed = try GitDiffParser.rows("@@ -1 +0,0 @@\n-old\n\\ No newline at end of file\n")
        #expect(try GitTextComparison.make(left: "old", right: "", rows: removed).left.text == "old")
    }

    @Test func omittedContextBareCRAndLongLinesCannotBecomeEditableFullText() throws {
        for text in ["a\r", "a\r\nb\r", "a\u{2028}b", "a\u{85}b", String(repeating: "a", count: 16_385)] {
            #expect(throws: GitFailure.self) { try GitTextComparison.make(left: text, right: text, rows: []) }
        }
        let rows = try GitDiffParser.rows("@@ -10 +10 @@\n-before\n+after\n")
        #expect(throws: GitFailure.self) { try GitTextComparison.make(left: "before", right: "after", rows: rows) }
        let projected = GitTextComparison.projection(rows, left: false, unified: false)
        #expect(projected.text.contains("已省略") && projected.text.contains("after"))
    }

    @Test func budgetIsCheckedBeforeAllocatingRowsForAnEmptyPatch() throws {
        let over = String(repeating: "\n", count: 20_001)
        #expect(throws: GitFailure.self) { try GitTextComparison.make(left: over, right: over, rows: []) }
        let exact = String(repeating: "\n", count: 20_000)
        #expect(try GitTextComparison.make(left: exact, right: exact, rows: []).left.lines.count == 20_001)
    }

    @Test func decodingRemovesOneFileBOMAndPreservesLiteralBodyFEFF() throws {
        let raw = Data([0xef, 0xbb, 0xbf]) + Data("\u{feff}body\n".utf8)
        #expect(try GitTextComparison.decode(raw) == "\u{feff}body\n")
        #expect(throws: GitFailure.self) { try GitTextComparison.decode(Data([0xff])) }
        let rows = try GitDiffParser.rows("@@ -1 +1 @@\n-before\n+\u{feff}body\n")
        let comparison = try GitTextComparison.make(left: "before\n", right: "\u{feff}body\n", rows: rows)
        #expect(comparison.right.text.hasPrefix("\u{feff}"))
        let rawPatch = try GitDiffParser.rows("@@ -1 +1 @@\n-\u{feff}before\n+\u{feff}after\n")
        #expect(try GitTextComparison.make(left: "before\n", right: "after\n", rows: rawPatch).right.text == "after\n")
    }

    @Test func sharedSourceAndDiffTabsRetainOneDocumentAndPinOnInput() throws {
        let entry = WorkspaceEntry(name: "a.swift", relativePath: "a.swift", kind: .file)
        let working = GitDiffLocation(repositoryID: "repo", path: entry.relativePath, comparison: .working)
        var tabs = BrowserTabs()
        tabs.open(.file(entry), preview: false)
        let source = try #require(tabs.activeID)
        tabs.open(.gitDiff(working), preview: true)
        let diff = try #require(tabs.activeID)
        #expect(tabs.documentPaths == [entry.relativePath])
        #expect(tabs.retainsDocument(entry.relativePath, excluding: source))
        tabs.pinDocument(entry.relativePath)
        #expect(tabs.tabs.allSatisfy { !$0.isPreview })
        tabs.close(source)
        #expect(tabs.documentPaths.contains(entry.relativePath))
        #expect(!tabs.retainsDocument(entry.relativePath, excluding: diff))
        tabs.open(.gitDiff(GitDiffLocation(repositoryID: "repo", path: "other", comparison: .working)), preview: true)
        tabs.open(.gitDiff(GitDiffLocation(repositoryID: "repo", path: "third", comparison: .working)), preview: true)
        #expect(tabs.tabs.count == 2 && tabs.tabs.contains { $0.id == diff })
        let history = BrowserLocation.gitDiff(
            GitDiffLocation(
                repositoryID: "repo", path: "a.swift",
                comparison: .commit(String(repeating: "a", count: 40), parent: nil)))
        #expect(history.documentPath == nil)
    }

    @Test func listRowsKeepStageAndWorkActionsBoundToTheSameIdentityAfterGrouping() throws {
        let entry = GitStatusEntry(
            path: "src/a.swift", originalPath: nil, indexStatus: "M", worktreeStatus: "M",
            headObject: "a", indexObject: "b", submodule: false)
        let rows = GitChangeListRow.make(
            entries: [entry], stagedMode: true, grouping: false, collapsed: [], expanded: true)
        #expect(rows.count == 4)
        #expect(rows[1].entry == entry && rows[1].staged)
        #expect(rows[3].entry == entry && !rows[3].staged && rows[1].id != rows[3].id)
        let collapsed = GitChangeListRow.make(
            entries: [entry], stagedMode: true, grouping: false, collapsed: ["staged"], expanded: true)
        #expect(collapsed.count == 3 && collapsed.last?.id == rows[3].id)
        let grouped = GitChangeListRow.make(
            entries: [entry], stagedMode: false, grouping: true, collapsed: [], expanded: true)
        #expect(grouped.count == 2 && grouped[1].entry?.path == entry.path)
        #expect(
            GitChangeListRow.make(entries: [entry], stagedMode: false, grouping: false, collapsed: [], expanded: false)
                .isEmpty)
    }
}
