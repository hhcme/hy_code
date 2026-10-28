import Foundation
import Testing

@testable import HyCodeWorkspace

struct GitInteractionTests {
    @Test func diffBodyExcludesPatchHeadersAndNavigatesActualChangeBlocks() throws {
        let rows = try GitDiffParser.rows(
            """
            diff --git a/example.swift b/example.swift
            index abc1234..def1234 100644
            --- a/example.swift
            +++ b/example.swift
            @@ -1,4 +1,4 @@
             first
            -let a = 1
            +let a = 2
             unchanged
            -let b = 3
            +let b = 4

            """)
        #expect(rows.count == 4)
        #expect(rows.first?.leftNumber == 1 && rows.first?.left == "first")
        #expect(!rows.contains { $0.kind == .header || $0.kind == .note })
        #expect(GitDiffParser.changeStarts(rows) == [1, 3])
    }

    @Test func compactDiffExplainsOmittedLinesAndKeepsNoNewlineOnTheCorrectSide() throws {
        let rows = try GitDiffParser.rows("@@ -12 +12 @@\n-old\n\\ No newline at end of file\n+new\n")
        #expect(rows.first?.kind == .header && rows.first?.left?.contains("11") == true)
        #expect(rows[1].kind == .changed && rows[1].leftNumber == 12 && rows[1].rightNumber == 12)
        #expect(rows.last?.kind == .note && rows.last?.left != nil && rows.last?.right == nil)
        #expect(GitDiffParser.changeStarts(rows) == [1])
        let exactBudget = "@@ -1,20000 +1,20000 @@\n" + String(repeating: " unchanged\n", count: 20_000)
        #expect(try GitDiffParser.rows(exactBudget).count == 20_000)
    }

    @Test func diffWidthsMeasureFallbackGlyphsAndTabsWithoutAWindow() throws {
        let rows = try GitDiffParser.rows("@@ -1 +1 @@\n-中文中文中文中文中文中文\n+\t中文🙂\n")
        let widths = try GitDiffText.widths(rows)
        #expect(widths.left > Double("中文中文中文中文中文中文".utf16.count) * 8.6)
        #expect(widths.right > 0 && widths.right.isFinite)
        #expect(try GitDiffText.widths([]).left == 0)
    }

    @Test func sourcePreviewAndHistoricalDiffHaveDifferentIdentityAndPinning() throws {
        var tabs = BrowserTabs()
        let path = "source.swift"
        let history = GitDiffLocation(
            repositoryID: "repo", path: path, comparison: .commit(String(repeating: "a", count: 40), parent: nil))
        tabs.open(.gitDiff(history), preview: false)
        let historyID = tabs.activeID
        tabs.open(.file(WorkspaceEntry(name: path, relativePath: path, kind: .file)), preview: true)
        let source = try #require(tabs.fileTab(path: path))
        #expect(source.id != historyID)
        tabs.pin(source.id)
        tabs.open(.file(WorkspaceEntry(name: "other", relativePath: "other", kind: .file)), preview: true)
        #expect(tabs.fileTab(path: path)?.isPreview == false)
        #expect(tabs.tabs.count == 3)
        #expect(tabs.tabs.first { $0.id == historyID }?.location == .gitDiff(history))
        tabs.close(source.id)
        #expect(tabs.tabs.contains { $0.id == historyID })
    }

    @Test func amendRepliesCannotOverwriteTypingOrLaterRequest() {
        var requests = GitAmendRequests()
        let head = String(repeating: "a", count: 40)
        let first = requests.begin(head: head, messageRevision: 5)
        #expect(requests.accepts(first, head: head, messageRevision: 5))
        #expect(!requests.accepts(first, head: head, messageRevision: 6))
        #expect(!requests.accepts(first, head: String(repeating: "b", count: 40), messageRevision: 5))
        requests.cancel()
        #expect(!requests.accepts(first, head: head, messageRevision: 5))
        let second = requests.begin(head: head, messageRevision: 5)
        #expect(!requests.accepts(first, head: head, messageRevision: 5))
        #expect(requests.accepts(second, head: head, messageRevision: 5))
    }

    @Test func commitAndLogAreIndependentToolsAndKeepCodexOpen() {
        var docking = WorkbenchDocking()
        docking.toggle(.commit)
        docking.toggle(.git)
        #expect(docking.isVisible(.commit) && docking.isVisible(.git) && docking.isVisible(.codex))
        docking.toggle(.git)
        #expect(docking.isVisible(.commit) && !docking.isVisible(.git) && docking.isVisible(.codex))
    }
    @Test func olderSelectionBatchCannotReplaceOrFinishNewerChoices() {
        var requests = GitSelectionRequests()
        let batch = requests.begin(["a", "b"])
        requests.cancel(["a"])
        let new = requests.begin(["a"])
        #expect(!requests.accepts(batch, path: "a"))
        #expect(requests.accepts(batch, path: "b"))
        requests.finish(batch)
        #expect(requests.pending == ["a"])
        #expect(requests.accepts(new, path: "a"))
        requests.finish(new)
        #expect(requests.pending.isEmpty)
    }

    @Test func graphTracksMergeParentsInsteadOfInventingLinearHistory() {
        func commit(_ object: String, parents: [String]) -> GitCommit {
            GitCommit(
                object: object, parents: parents, author: "fixture", email: "fixture@example.invalid",
                authoredAt: .distantPast, committer: "fixture", committerEmail: "fixture@example.invalid",
                committedAt: .distantPast, decorations: "", message: object)
        }
        let rows = GitGraphRow.layout([
            commit("merge", parents: ["left", "right"]), commit("left", parents: ["base"]),
            commit("right", parents: ["base"]), commit("base", parents: []),
        ])
        #expect(rows[0].edges.count == 2)
        #expect(rows[0].columns == 2)
        #expect(rows.last?.edges.isEmpty == true)
    }
}
