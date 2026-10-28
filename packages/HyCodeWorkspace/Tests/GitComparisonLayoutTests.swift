import Foundation
import Testing

@testable import HyCodeWorkspace

struct GitComparisonLayoutTests {
    @Test func deletionKeepsBothSourcesContinuousAndConnectsFiveLinesToAnAnchor() throws {
        let patch = "@@ -1,7 +1,2 @@\n first\n-old1\n-old2\n-old3\n-old4\n-old5\n last\n"
        let rows = try GitDiffParser.rows(patch)
        let comparison = try GitTextComparison.make(
            left: "first\nold1\nold2\nold3\nold4\nold5\nlast\n",
            right: "first\nlast\n", rows: rows)
        let block = try #require(comparison.blocks.first)
        #expect(block.left == 1..<6 && block.right == 1..<1 && block.kind == .removed)
        #expect(comparison.left.index.count == 8 && comparison.right.index.count == 3)
        #expect(comparison.right.index.start(of: 1) == 6)
        #expect(comparison.right.text.utf8.elementsEqual("first\nlast\n".utf8))
        #expect(GitDiffBlock.map(0.5, fromLeft: true, blocks: comparison.blocks) == 0.5)
        #expect(GitDiffBlock.map(3.5, fromLeft: true, blocks: comparison.blocks) == 1)
        #expect(GitDiffBlock.map(6.5, fromLeft: true, blocks: comparison.blocks) == 1.5)
        #expect(GitDiffBlock.map(1.5, fromLeft: false, blocks: comparison.blocks) == 6.5)
    }

    @Test func insertionAndUnequalReplacementMapRealLineRangesInBothDirections() throws {
        let rows = try GitDiffParser.rows("@@ -1,3 +1,6 @@\n+intro\n a\n-b\n+one\n+two\n+three\n c\n")
        let comparison = try GitTextComparison.make(
            left: "a\nb\nc\n", right: "intro\na\none\ntwo\nthree\nc\n", rows: rows)
        #expect(comparison.blocks.count == 2)
        #expect(comparison.blocks[0].left == 0..<0 && comparison.blocks[0].right == 0..<1)
        #expect(comparison.blocks[1].left == 1..<2 && comparison.blocks[1].right == 2..<5)
        #expect(GitDiffBlock.map(1.5, fromLeft: true, blocks: comparison.blocks) == 3.5)
        #expect(GitDiffBlock.map(3.5, fromLeft: false, blocks: comparison.blocks) == 1.5)
        #expect(GitDiffBlock.map(2.5, fromLeft: true, blocks: comparison.blocks) == 5.5)
        #expect(GitDiffBlock.map(-0.25, fromLeft: true, blocks: comparison.blocks) == -0.25)
        #expect(GitDiffBlock.map(.nan, fromLeft: true, blocks: comparison.blocks) == 0)
    }

    @Test func emptyBaselineAndMissingFinalNewlineHaveExactEOFAnchors() throws {
        let rows = try GitDiffParser.rows("@@ -0,0 +1,2 @@\n+one\n+two\n\\ No newline at end of file\n")
        let comparison = try GitTextComparison.make(left: "", right: "one\ntwo", rows: rows)
        #expect(comparison.blocks.count == 1)
        #expect(comparison.blocks[0].left == 0..<0 && comparison.blocks[0].right == 0..<2)
        #expect(comparison.right.index.count == 2)
        #expect(GitDiffBlock.map(1.25, fromLeft: false, blocks: comparison.blocks) == 0)
    }

    @Test func fileListAndReviewNavigationUseTheSameTrackedOrderAndSeparateUntrackedGroup() throws {
        func entry(_ path: String, untracked: Bool = false) -> GitStatusEntry {
            GitStatusEntry(
                path: path, originalPath: nil, indexStatus: untracked ? "?" : ".",
                worktreeStatus: untracked ? "?" : "M",
                headObject: "a", indexObject: "a", submodule: false)
        }
        let values = [
            entry("docs/README.md"), entry("settings.json"), entry("new.md", untracked: true), entry("a.yaml"),
        ]
        let rows = GitChangeListRow.make(
            entries: values, stagedMode: false, grouping: false,
            collapsed: ["untracked"], expanded: true)
        #expect(rows.compactMap { $0.entry?.path } == ["a.yaml", "docs/README.md", "settings.json"])
        #expect(rows.last?.id == "untracked" && rows.last?.expanded == false)
        #expect(GitChangeListRow.reviewPaths(values, path: "settings.json") == rows.compactMap { $0.entry?.path })
        #expect(GitChangeListRow.reviewPaths(values, path: "new.md") == ["new.md"])
        let open = GitChangeListRow.make(
            entries: values, stagedMode: false, grouping: false,
            collapsed: [], expanded: false)
        #expect(open.count == 2 && open.last?.entry?.untracked == true)
        let groupedEntries = [entry("a/z.swift"), entry("b/a.swift")]
        let grouped = GitChangeListRow.make(
            entries: groupedEntries, stagedMode: false, grouping: true,
            collapsed: [], expanded: true)
        #expect(grouped.compactMap { $0.entry?.path } == ["a/z.swift", "b/a.swift"])
        #expect(
            GitChangeListRow.reviewPaths(groupedEntries, path: "a/z.swift", grouping: true)
                == grouped.compactMap { $0.entry?.path })
        #expect(
            GitChangeListRow.ordered([entry("file10"), entry("file2"), entry("README"), entry("a")]).map(\.path)
                == ["a", "file2", "file10", "README"])
    }
}
