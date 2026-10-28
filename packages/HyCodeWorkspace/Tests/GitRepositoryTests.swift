import Foundation
import Testing

@testable import HyCodeWorkspace

@Suite(.serialized)
struct GitRepositoryTests {
    @Test func partialCommitKeepsBOMCRLFAndNoFinalNewlineByteExact() async throws {
        let f = try await GitFixture.make()
        defer { f.remove() }
        let bom = Data([0xef, 0xbb, 0xbf])
        let file = f.root.appendingPathComponent("a.txt")
        try (bom + Data("old\r\nkeep\r\nlast".utf8)).write(to: file)
        _ = try await f.git(["add", "."])
        _ = try await f.git(["commit", "-m", "generated base"])
        let disk = bom + Data("new\r\nkeep\r\nchanged last".utf8)
        try disk.write(to: file)
        let repo = try #require(await GitRepository.open(root: f.root))
        let snapshot = try await repo.status()
        let diff = try await repo.diff(path: "a.txt", comparison: .working, snapshot: snapshot)
        let blocks = try #require(diff.text?.blocks)
        #expect(blocks.count == 2)
        let selection = try await repo.capturePartialSelection(diff, blocks: [blocks[0].id], snapshot: snapshot)
        _ = try await repo.createCommit(
            selections: [selection], staged: false, message: "one CRLF block", amend: false, snapshot: snapshot)
        #expect(try await f.git(["show", "HEAD:a.txt"]).stdout == bom + Data("new\r\nkeep\r\nlast".utf8))
        #expect(try Data(contentsOf: file) == disk)
    }

    @Test func stalePartialReviewAndCandidateNeverChangeHeadOrIndex() async throws {
        let f = try await GitFixture.make()
        defer { f.remove() }
        try f.write("a.txt", "A\nkeep\nB\n")
        _ = try await f.git(["add", "."])
        _ = try await f.git(["commit", "-m", "generated base"])
        try f.write("a.txt", "new A\nkeep\nnew B\n")
        let repo = try #require(await GitRepository.open(root: f.root))
        let snapshot = try await repo.status()
        let diff = try await repo.diff(path: "a.txt", comparison: .working, snapshot: snapshot)
        let blocks = try #require(diff.text?.blocks)
        let selection = try await repo.capturePartialSelection(diff, blocks: [blocks[0].id], snapshot: snapshot)
        try f.write("a.txt", "newer A\nkeep\nnew B\n")
        await #expect(throws: GitFailure.self) {
            try await repo.capturePartialSelection(diff, blocks: [blocks[1].id], snapshot: snapshot)
        }
        await #expect(throws: GitFailure.self) {
            try await repo.createCommit(
                selections: [selection], staged: false, message: "stale", amend: false, snapshot: snapshot)
        }
        let unchanged = try await repo.status()
        #expect(unchanged.head == snapshot.head && unchanged.indexDigest == snapshot.indexDigest)
        _ = try await f.git(["add", "a.txt"])
        let afterExternalStage = try await repo.status()
        await #expect(throws: GitFailure.self) {
            try await repo.createCommit(
                selections: [selection], staged: false, message: "stale index", amend: false, snapshot: snapshot)
        }
        #expect(try await repo.status().indexDigest == afterExternalStage.indexDigest)
        #expect(try await repo.status().head == snapshot.head)
    }

    @Test func partialPolicyRejectsConversionsButSelectingAllRemainsWholeFile() async throws {
        let f = try await GitFixture.make()
        defer { f.remove() }
        try f.write("a.txt", "A\nkeep\nB\n")
        _ = try await f.git(["add", "."])
        _ = try await f.git(["commit", "-m", "generated base"])
        try f.write("a.txt", "new A\nkeep\nnew B\n")
        let repo = try #require(await GitRepository.open(root: f.root))
        let snapshot = try await repo.status()
        let diff = try await repo.diff(path: "a.txt", comparison: .working, snapshot: snapshot)
        let blocks = try #require(diff.text?.blocks)
        let all = try await repo.capturePartialSelection(diff, blocks: Set(blocks.map(\.id)), snapshot: snapshot)
        #expect(all.partial == nil)
        await #expect(throws: GitFailure.self) {
            try await repo.capturePartialSelection(diff, blocks: [-1], snapshot: snapshot)
        }
        try f.write(".gitattributes", "a.txt text eol=lf\n")
        await #expect(throws: GitFailure.self) {
            try await repo.capturePartialSelection(diff, blocks: [blocks[0].id], snapshot: snapshot)
        }
        try FileManager.default.removeItem(at: f.root.appendingPathComponent(".gitattributes"))
        _ = try await f.git(["config", "core.autocrlf", "true"])
        await #expect(throws: GitFailure.self) {
            try await repo.capturePartialSelection(diff, blocks: [blocks[0].id], snapshot: snapshot)
        }
        let unchanged = try await repo.status()
        #expect(unchanged.head == snapshot.head && unchanged.indexDigest == snapshot.indexDigest)
    }

    @Test func partialCommitKeepsOtherWorkingHunksAndOtherStagedFiles() async throws {
        let f = try await GitFixture.make()
        defer { f.remove() }
        try f.write("a.txt", "first\nbase A\ncontext\nbase B\nlast\n")
        try f.write("other.txt", "old\n")
        _ = try await f.git(["add", "."])
        _ = try await f.git(["commit", "-m", "generated base"])
        try f.write("a.txt", "first\nwork A\ncontext\nwork B\nlast\n")
        try f.write("other.txt", "staged\n")
        _ = try await f.git(["add", "other.txt"])
        let repo = try #require(await GitRepository.open(root: f.root))
        let snapshot = try await repo.status()
        let diff = try await repo.diff(path: "a.txt", comparison: .working, snapshot: snapshot)
        let blocks = try #require(diff.text?.blocks)
        #expect(blocks.count == 2)
        let selected = try await repo.capturePartialSelection(diff, blocks: [blocks[0].id], snapshot: snapshot)
        #expect(selected.partial?.blocks == [blocks[0].id])
        _ = try await repo.createCommit(
            selections: [selected], staged: false, message: "first block", amend: false, snapshot: snapshot)
        #expect(try await f.git(["show", "HEAD:a.txt"]).stdout == Data("first\nwork A\ncontext\nbase B\nlast\n".utf8))
        #expect(try await f.git(["show", ":a.txt"]).stdout == Data("first\nwork A\ncontext\nbase B\nlast\n".utf8))
        #expect(
            try String(contentsOf: f.root.appendingPathComponent("a.txt"), encoding: .utf8)
                == "first\nwork A\ncontext\nwork B\nlast\n")
        #expect(try await f.git(["show", ":other.txt"]).stdout == Data("staged\n".utf8))
        #expect(try await f.git(["show", "HEAD:other.txt"]).stdout == Data("old\n".utf8))
    }

    @Test func partialCommitPreservesExcludedPreStagedHunks() async throws {
        let f = try await GitFixture.make()
        defer { f.remove() }
        try f.write("a.txt", "A\nkeep\nB\n")
        _ = try await f.git(["add", "."])
        _ = try await f.git(["commit", "-m", "generated base"])
        try f.write("a.txt", "new A\nkeep\nnew B\n")
        _ = try await f.git(["add", "a.txt"])
        let repo = try #require(await GitRepository.open(root: f.root))
        let snapshot = try await repo.status()
        let diff = try await repo.diff(path: "a.txt", comparison: .working, snapshot: snapshot)
        let blocks = try #require(diff.text?.blocks)
        let selected = try await repo.capturePartialSelection(diff, blocks: [blocks[1].id], snapshot: snapshot)
        _ = try await repo.createCommit(
            selections: [selected], staged: false, message: "second block", amend: false, snapshot: snapshot)
        #expect(try await f.git(["show", "HEAD:a.txt"]).stdout == Data("A\nkeep\nnew B\n".utf8))
        #expect(try await f.git(["show", ":a.txt"]).stdout == Data("new A\nkeep\nnew B\n".utf8))
        let status = try await repo.status()
        #expect(status.entries.first?.staged == true && status.entries.first?.unstaged == false)
    }

    @Test func bufferPreviewUsesTheFormalRevisionWithoutChangingDiskOrIndex() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let path = "source.swift"
        try fixture.write(path, "let value = 1\r\nlast")
        _ = try await fixture.git(["add", path])
        _ = try await fixture.git(["commit", "-m", "generated baseline"])
        try fixture.write(path, "let value = 2\r\nlast")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let document = NativeTextDocument(root: fixture.root, path: path)
        _ = try await document.open()
        let before = try await repository.diff(path: path, comparison: .working)
        #expect(before.text?.left.text == "let value = 1\r\nlast")
        let disk = try Data(contentsOf: fixture.root.appendingPathComponent(path))
        let index = try await fixture.git(["show", ":" + path]).stdout
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 0), text: "\u{feff}new\r\n")
        let buffer = try await document.textSnapshot(revision: 1)
        let preview = try await repository.preview(before, buffer: buffer)
        #expect(preview.text?.right.text == "\u{feff}new\r\nlet value = 2\r\nlast")
        #expect(preview.selection == nil && preview.rows.contains { $0.kind.isChange })
        #expect(try Data(contentsOf: fixture.root.appendingPathComponent(path)) == disk)
        #expect(try await fixture.git(["show", ":" + path]).stdout == index)
        let home = await repository.home
        #expect(try !FileManager.default.contentsOfDirectory(atPath: home.path).contains { $0.hasPrefix("preview-") })
        try await document.save(revision: 1)
        let saved = try await repository.diff(path: path, comparison: .working)
        #expect(saved.selection != nil && saved.text?.right.text == "new\r\nlet value = 2\r\nlast")
    }

    @Test func completeSourcesCoverCleanFilesStagingDeletionAndUntrackedEOF() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "generated baseline"])
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let clean = try await repository.diff(path: "a.txt", comparison: .working)
        #expect(clean.text?.left.text == "base\n" && clean.text?.right.text == "base\n")
        #expect(clean.editableWorkingText)
        try fixture.write("a.txt", "index\n")
        _ = try await fixture.git(["add", "a.txt"])
        try fixture.write("a.txt", "work\n")
        let staged = try await repository.diff(path: "a.txt", comparison: .staged)
        let unstaged = try await repository.diff(path: "a.txt", comparison: .unstaged)
        #expect(staged.text?.left.text == "base\n" && staged.text?.right.text == "index\n")
        #expect(!staged.editableWorkingText && unstaged.editableWorkingText)
        #expect(unstaged.text?.left.text == "index\n" && unstaged.text?.right.text == "work\n")
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("a.txt"))
        let deletion = try await repository.diff(path: "a.txt", comparison: .working)
        #expect(deletion.text?.right.text == "")
        #expect(!deletion.editableWorkingText && deletion.selection != nil)
        try fixture.write("new.txt", "new without newline")
        let untracked = try await repository.diff(path: "new.txt", comparison: .working)
        #expect(untracked.text?.left.text == "" && untracked.text?.right.text == "new without newline")
        #expect(untracked.editableWorkingText)
        try fixture.write("empty.txt", "")
        let emptyFile = try await repository.diff(path: "empty.txt", comparison: .working)
        let emptyPreview = try await repository.preview(emptyFile, buffer: "")
        #expect(emptyPreview.text?.right.text == "" && emptyPreview.message == emptyFile.message)
        #expect(emptyPreview.message != "这两个版本没有差异" && emptyPreview.selection == nil)
        try fixture.write("paged.txt", String(repeating: "中", count: 6_000) + "\n")
        let paged = try await repository.diff(path: "paged.txt", comparison: .working)
        #expect(paged.text != nil && paged.selection != nil && !paged.editableWorkingText)
        #expect(paged.message?.contains("分段") == true)
    }
    @Test func diffShowsFullSourceContextAndFallsBackWithinTheRowBudget() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let original = (1...100).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try fixture.write("context.txt", original)
        let large = (1...20_100).map { "unchanged \($0)" }.joined(separator: "\n") + "\n"
        try fixture.write("--unified=20000", large)
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "generated source context"])
        try fixture.write(
            "context.txt",
            original.replacingOccurrences(of: "line 20\n", with: "changed 20\n")
                .replacingOccurrences(of: "line 70\n", with: "changed 70\n"))
        try fixture.write(
            "--unified=20000", large.replacingOccurrences(of: "unchanged 10000\n", with: "changed 10000\n"))
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let ordinary = try await repository.diff(path: "context.txt", comparison: .working)
        #expect(
            ordinary.rows.count == 100 && ordinary.rows.first?.leftNumber == 1 && ordinary.rows.last?.rightNumber == 100
        )
        #expect(ordinary.differenceRows.count == 2)
        #expect(
            !ordinary.rows.contains { $0.left?.hasPrefix("diff --git") == true || $0.left?.hasPrefix("@@") == true })
        let compact = try await repository.diff(path: "--unified=20000", comparison: .working)
        #expect(compact.rows.count < 30 && compact.rows.first?.kind == .header)
        #expect(compact.rows.contains { $0.kind == .changed && $0.rightNumber == 10000 })
        #expect(compact.differenceRows.count == 1 && compact.selection != nil)
    }

    @Test func statusAndDiffUseActualTemporaryRepositoryAndLiteralNames() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let path = "-中文 ' $()\n文件.swift"
        try fixture.write(path, "let value = 1\n")
        _ = try await fixture.git(["add", "--", path])
        _ = try await fixture.git(["commit", "-m", "first"])
        try fixture.write(path, "let value = 2\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let snapshot = try await repository.status()
        #expect(snapshot.branch == "main")
        #expect(snapshot.entries.map(\.path) == [path])
        #expect(snapshot.entries[0].unstaged)
        let diff = try await repository.diff(path: path, comparison: .working, snapshot: snapshot)
        #expect(diff.rows.contains { $0.left == "let value = 1" && $0.right == "let value = 2" })
        #expect(diff.rows.contains { $0.kind == .changed && $0.leftNumber == 1 && $0.rightNumber == 1 })
        #expect(diff.selection != nil)
    }

    @Test func selectedCommitPreservesOtherStagedAndUnstagedVersions() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "a0\n")
        try fixture.write("b.txt", "b0\n")
        _ = try await fixture.git(["add", "a.txt", "b.txt"])
        _ = try await fixture.git(["commit", "-m", "base"])
        try fixture.write("a.txt", "a1\n")
        try fixture.write("b.txt", "b staged\n")
        _ = try await fixture.git(["add", "b.txt"])
        let stagedB = try await fixture.git(["show", ":b.txt"]).stdout
        try fixture.write("b.txt", "b working\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        let result = try await repository.createCommit(
            selections: [selection], staged: false, message: "only A", amend: false, snapshot: snapshot)
        #expect(result.commit != nil)
        #expect(try await fixture.git(["show", "HEAD:a.txt"]).text == "a1")
        #expect(try await fixture.git(["show", "HEAD:b.txt"]).text == "b0")
        #expect(try await fixture.git(["show", ":b.txt"]).stdout == stagedB)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("b.txt"), encoding: .utf8) == "b working\n")
        #expect(try await repository.status().entries.map(\.path) == ["b.txt"])
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".git/index.lock").path))
    }

    @Test func initialSelectedCommitAndMessageOnlyAmendKeepExcludedFile() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("new.txt", "new\n")
        try fixture.write("excluded.txt", "private draft\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        var snapshot = try await repository.status()
        #expect(snapshot.head == nil)
        let selection = try await repository.captureSelection("new.txt", snapshot: snapshot)
        _ = try await repository.createCommit(
            selections: [selection], staged: false, message: "first", amend: false, snapshot: snapshot)
        snapshot = try await repository.status()
        #expect(snapshot.entries.map(\.path) == ["excluded.txt"])
        _ = try await repository.createCommit(
            selections: [], staged: false, message: "amended", amend: true, snapshot: snapshot)
        #expect(try await fixture.git(["log", "--format=%s", "-1"]).text == "amended")
        #expect(try await fixture.git(["rev-list", "--count", "HEAD"]).text == "1")
        #expect(try await repository.status().entries.map(\.path) == ["excluded.txt"])
    }

    @Test func sameFileTwoLayersRequiresExplicitStagedCommit() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "base"])
        try fixture.write("a.txt", "index\n")
        _ = try await fixture.git(["add", "a.txt"])
        try fixture.write("a.txt", "working\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        await #expect(throws: GitFailure.self) {
            try await repository.createCommit(
                selections: [selection], staged: false, message: "not allowed", amend: false, snapshot: snapshot)
        }
        _ = try await repository.createCommit(
            selections: [], staged: true, message: "index only", amend: false, snapshot: snapshot)
        #expect(try await fixture.git(["show", "HEAD:a.txt"]).text == "index")
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8) == "working\n")
        #expect(try await repository.status().entries[0].unstaged)
    }

    @Test func changedSelectionAndExistingLockNeverModifyHeadOrDeleteForeignLock() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "first\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        try fixture.write("a.txt", "second\n")
        await #expect(throws: GitFailure.self) {
            try await repository.createCommit(
                selections: [selection], staged: false, message: "stale", amend: false, snapshot: snapshot)
        }
        #expect(try await repository.status().head == nil)
        let replacement = try await repository.captureSelection("a.txt", snapshot: snapshot)
        let lock = fixture.root.appendingPathComponent(".git/index.lock")
        try Data("external owner".utf8).write(to: lock)
        await #expect(throws: GitFailure.self) {
            try await repository.createCommit(
                selections: [replacement], staged: false, message: "locked", amend: false, snapshot: snapshot)
        }
        #expect(try String(contentsOf: lock, encoding: .utf8) == "external owner")
    }

    @Test func unstageAndDiscardHaveDifferentBaselines() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "head\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "base"])
        try fixture.write("a.txt", "index\n")
        _ = try await fixture.git(["add", "a.txt"])
        try fixture.write("a.txt", "working\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        var snapshot = try await repository.status()
        var selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        _ = try await repository.fileAction(.discardUnstaged, selections: [selection], snapshot: snapshot)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8) == "index\n")
        snapshot = try await repository.status()
        selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        _ = try await repository.fileAction(.unstage, selections: [selection], snapshot: snapshot)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8) == "index\n")
        #expect(try await fixture.git(["show", ":a.txt"]).text == "head")
    }

    @Test func historyDetailsAndBranchesUseCompleteObjects() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "one\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "one\n\nbody"])
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let page = try await repository.history(GitHistoryQuery())
        let first = try #require(page.commits.first)
        #expect(first.subject == "one")
        #expect(first.message.contains("body"))
        #expect(try await repository.files(in: first.object).map(\.path) == ["a.txt"])
        let snapshot = try await repository.status()
        _ = try await repository.createBranch(
            name: "feature/test", start: first.object, switchTo: true, snapshot: snapshot)
        #expect(try await repository.status().branch == "feature/test")
        let main = try #require(try await repository.references().first { $0.shortName == "main" })
        _ = try await repository.switchBranch(main, snapshot: repository.status())
        #expect(try await repository.status().branch == "main")
    }

    @Test func hooksFiltersAndExternalIncludesAreNotExecutedOrSilentlySkipped() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "one\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let hooks = fixture.root.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-commit")
        try Data("#!/bin/sh\ntouch \"$PWD/canary\"\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        await #expect(throws: GitFailure.self) {
            try await repository.createCommit(
                selections: [selection], staged: false, message: "must stop", amend: false, snapshot: snapshot)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("canary").path))
        try FileManager.default.removeItem(at: hook)
        try fixture.write(".gitattributes", "a.txt filter=must-not-run\n")
        await #expect(throws: GitFailure.self) {
            try await repository.createCommit(
                selections: [selection], staged: false, message: "must stop", amend: false, snapshot: snapshot)
        }
        _ = try await fixture.git(["config", "include.path", "/outside/no-read"])
        await #expect(throws: GitFailure.self) { try await repository.status() }
    }

    @Test func localBareRemotePushFetchAndRejectedPushKeepLocalCommit() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let bare = fixture.base.appendingPathComponent("remote.git")
        _ = try await fixture.git(["init", "--bare", "--template=", bare.path], directory: fixture.base)
        try fixture.write("a.txt", "first\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "first"])
        let repository = try #require(await GitRepository.open(root: fixture.root))
        _ = try await repository.setRemote(name: "origin", url: bare.path, replacing: false)
        let remote = try #require(try await repository.remotes().first)
        let plan = try await repository.pushPlan(remote: remote, target: "main", snapshot: repository.status())
        _ = try await repository.push(plan, remote: remote)
        #expect(
            try await fixture.git(["--git-dir=" + bare.path, "rev-parse", "refs/heads/main"], directory: fixture.base)
                .text == plan.head)
        #expect(try await repository.status().upstream == "origin/main")
        #expect(try await fixture.git(["rev-parse", "refs/remotes/origin/main"]).text == plan.head)
        _ = try await repository.fetch(remote: remote)
        #expect(try await repository.status().upstream == "origin/main")
        _ = try await fixture.git(
            ["config", "--file", bare.appendingPathComponent("config").path, "receive.denyNonFastForwards", "true"],
            directory: fixture.base)
        let oldHead = plan.head
        try fixture.write("a.txt", "second\n")
        var snapshot = try await repository.status()
        var selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        _ = try await repository.createCommit(
            selections: [selection], staged: false, message: "second", amend: false, snapshot: snapshot)
        snapshot = try await repository.status()
        let secondPlan = try await repository.pushPlan(remote: remote, target: "main", snapshot: snapshot)
        #expect(secondPlan.previousRemoteObject == oldHead)
        _ = try await repository.push(secondPlan, remote: remote)
        #expect(try await fixture.git(["rev-parse", "refs/remotes/origin/main"]).text == secondPlan.head)
        _ = try await fixture.git(["reset", "--hard", oldHead])
        _ = try await repository.pullFastForward(remote: remote, snapshot: repository.status())
        #expect(try await repository.status().head == secondPlan.head)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8) == "second\n")
        _ = try await fixture.git(["reset", "--hard", oldHead])
        try fixture.write("a.txt", "diverged\n")
        snapshot = try await repository.status()
        selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        let local = try await repository.createCommit(
            selections: [selection], staged: false, message: "diverged", amend: false, snapshot: snapshot)
        let rejectedPlan = try await repository.pushPlan(remote: remote, target: "main", snapshot: repository.status())
        await #expect(throws: GitFailure.self) { try await repository.push(rejectedPlan, remote: remote) }
        #expect(try await repository.status().head == local.commit)
        await #expect(throws: GitFailure.self) {
            try await repository.pullFastForward(remote: remote, snapshot: repository.status())
        }
        #expect(try await repository.status().head == local.commit)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8) == "diverged\n")
    }

    @Test func localBareRemoteHooksAndUnknownServerConfigurationAreNeverBypassed() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let bare = fixture.base.appendingPathComponent("remote.git")
        _ = try await fixture.git(["init", "--bare", "--template=", bare.path], directory: fixture.base)
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "base"])
        let repository = try #require(await GitRepository.open(root: fixture.root))
        _ = try await repository.setRemote(name: "origin", url: bare.path, replacing: false)
        let remote = try #require(try await repository.remotes().first)
        let plan = try await repository.pushPlan(remote: remote, target: "main", snapshot: repository.status())
        let hooks = bare.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let hook = hooks.appendingPathComponent("pre-receive")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        await #expect(throws: GitFailure.self) { try await repository.push(plan, remote: remote) }
        #expect(!FileManager.default.fileExists(atPath: bare.appendingPathComponent("refs/heads/main").path))
        try FileManager.default.removeItem(at: hook)
        let config = bare.appendingPathComponent("config").path
        for key in ["core.hooksPath", "uploadpack.packObjectsHook"] {
            _ = try await fixture.git(["config", "--file", config, key, "must-not-execute"], directory: fixture.base)
            await #expect(throws: GitFailure.self) { try await repository.fetch(remote: remote) }
            await #expect(throws: GitFailure.self) { try await repository.push(plan, remote: remote) }
            _ = try await fixture.git(["config", "--file", config, "--unset", key], directory: fixture.base)
        }
        let privateValue = "fixture-config-value-must-not-appear-in-diagnostics"
        _ = try await fixture.git(
            ["config", "--file", config, "core.repositoryformatversion", privateValue], directory: fixture.base)
        do {
            _ = try await repository.fetch(remote: remote)
            Issue.record("Invalid local remote configuration was accepted")
        } catch {
            #expect(!error.localizedDescription.contains(privateValue))
        }
        _ = try await fixture.git(
            ["config", "--file", config, "core.repositoryformatversion", "0"], directory: fixture.base)
        try Data("[core]\n".utf8).write(to: bare.appendingPathComponent("config.worktree"))
        await #expect(throws: GitFailure.self) { try await repository.push(plan, remote: remote) }
        #expect(!FileManager.default.fileExists(atPath: bare.appendingPathComponent("refs/heads/main").path))
    }

    @Test func selectedStagedDeletionAndRenameReconcileExactIndexPaths() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("nested/delete.txt", "delete\n")
        try fixture.write("old.txt", "rename\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "base"])
        _ = try await fixture.git(["rm", "nested/delete.txt"])
        _ = try await fixture.git(["mv", "old.txt", "new.txt"])
        let repository = try #require(await GitRepository.open(root: fixture.root))
        var snapshot = try await repository.status()
        let deleted = try await repository.captureSelection("nested/delete.txt", snapshot: snapshot)
        _ = try await repository.createCommit(
            selections: [deleted], staged: false, message: "delete only", amend: false, snapshot: snapshot)
        #expect(try await fixture.git(["ls-tree", "--name-only", "HEAD"]).text == "old.txt")
        snapshot = try await repository.status()
        let renamed = try await repository.captureSelection("new.txt", snapshot: snapshot)
        _ = try await repository.createCommit(
            selections: [renamed], staged: false, message: "rename only", amend: false, snapshot: snapshot)
        #expect(try await fixture.git(["ls-tree", "--name-only", "HEAD"]).text == "new.txt")
        #expect(try await repository.status().entries.isEmpty)
    }

    @Test func stagedRenameCanDiscardOnlyNewPathWorkingChanges() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("old.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "base"])
        _ = try await fixture.git(["mv", "old.txt", "new.txt"])
        try fixture.write("new.txt", "working\n")
        let repository = try #require(await GitRepository.open(root: fixture.root))
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("new.txt", snapshot: snapshot)
        _ = try await repository.fileAction(.discardUnstaged, selections: [selection], snapshot: snapshot)
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("new.txt"), encoding: .utf8) == "base\n")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("old.txt").path))
        #expect(try await repository.status().entries.first?.staged == true)
    }

    @Test func worktreeConfigurationAndBOMIncludesCannotBypassExecutionPolicy() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "base"])
        let bare = fixture.base.appendingPathComponent("remote.git")
        _ = try await fixture.git(["init", "--bare", "--template=", bare.path], directory: fixture.base)
        let repository = try #require(await GitRepository.open(root: fixture.root))
        _ = try await repository.setRemote(name: "Origin", url: bare.path, replacing: false)
        #expect(try await repository.remotes().first?.name == "Origin")
        _ = try await fixture.git(["config", "extensions.worktreeConfig", "true"])
        _ = try await fixture.git(["config", "--worktree", "remote.Origin.uploadpack", "must-not-execute"])
        let remote = try #require(try await repository.remotes().first)
        await #expect(throws: GitFailure.self) { try await repository.fetch(remote: remote) }
        let configURL = fixture.root.appendingPathComponent(".git/config")
        let original = try String(contentsOf: configURL, encoding: .utf8)
        try Data(("\u{feff}[include]\npath = ../extra.cfg\n" + original).utf8).write(to: configURL)
        await #expect(throws: GitFailure.self) { try await repository.status() }
    }

    @Test func parentSymlinkAndLargeDiffFailClosedWithoutReadingWholeFile() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        let outside = fixture.base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("outside".utf8).write(to: outside.appendingPathComponent("secret"))
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("link"), withDestinationURL: outside)
        let repository = try #require(await GitRepository.open(root: fixture.root))
        #expect(throws: GitFailure.self) {
            try GitFileAccess.diskDigest("link/secret", repository: repository.identity)
        }
        let large = fixture.root.appendingPathComponent("large.txt")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 8_388_609)
        try handle.close()
        let diff = try await repository.diff(path: "large.txt", comparison: .working)
        #expect(diff.rows.isEmpty && diff.selection == nil)
        #expect(diff.message?.contains("8 MiB") == true)
    }

    @Test func malformedRecordsAndHunksAreErrorsInsteadOfTraps() throws {
        #expect(throws: GitFailure.self) { try GitOutputParser.status(Data("2 R. N...\0".utf8)) }
        #expect(throws: GitFailure.self) { try GitOutputParser.commits(Data("missing\0fields\0".utf8)) }
        #expect(throws: GitFailure.self) { try GitDiffParser.rows("@@ - + @@\n+a") }
        #expect(throws: GitFailure.self) { try GitDiffParser.rows("@@ -9223372036854775807 +1 @@\n a") }
        #expect(throws: GitFailure.self) {
            try GitOutputParser.changedFiles(Data(String(repeating: "M\0file\0", count: 20_001).utf8))
        }
        var status = Data((0..<20_000).map { "? path\($0)\0" }.joined().utf8)
        #expect(try GitOutputParser.status(status).entries.count == 20_000)
        status.append(Data("? over-budget\0".utf8))
        #expect(throws: GitFailure.self) { try GitOutputParser.status(status) }
    }

    @Test func discardConfirmationVersionAndOldPushPlanAreNotRecaptured() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "base"])
        let bare = fixture.base.appendingPathComponent("remote.git")
        _ = try await fixture.git(["init", "--bare", "--template=", bare.path], directory: fixture.base)
        let repository = try #require(await GitRepository.open(root: fixture.root))
        _ = try await repository.setRemote(name: "origin", url: bare.path, replacing: false)
        let remote = try #require(try await repository.remotes().first)
        let plan = try await repository.pushPlan(remote: remote, target: "main", snapshot: repository.status())
        try fixture.write("a.txt", "reviewed\n")
        let snapshot = try await repository.status()
        let approved = try await repository.captureSelection("a.txt", snapshot: snapshot)
        try fixture.write("a.txt", "new external content\n")
        await #expect(throws: GitFailure.self) {
            try await repository.fileAction(.discardUnstaged, selections: [approved], snapshot: snapshot)
        }
        #expect(
            try String(contentsOf: fixture.root.appendingPathComponent("a.txt"), encoding: .utf8)
                == "new external content\n")
        _ = try await fixture.git(["add", "a.txt"])
        _ = try await fixture.git(["commit", "-m", "external advance"])
        await #expect(throws: GitFailure.self) { try await repository.push(plan, remote: remote) }
        #expect(
            try await fixture.git(
                ["--git-dir=" + bare.path, "for-each-ref", "--format=%(objectname)"], directory: fixture.base
            ).text.isEmpty)
    }

    @Test func linkedWorktreeRequiresExplicitManagementDirectoryGrant() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(["commit", "-m", "base"])
        let worktree = fixture.base.appendingPathComponent("linked")
        _ = try await fixture.git(
            [
                "--git-dir=" + fixture.root.appendingPathComponent(".git").path, "--work-tree=" + fixture.root.path,
                "worktree", "add", "-b", "topic", worktree.path,
            ], directory: fixture.base)
        await #expect(throws: GitFailure.self) { try await GitRepository.open(root: worktree) }
        let repository = try #require(
            await GitRepository.open(
                root: worktree, authorizedDirectories: [fixture.root.appendingPathComponent(".git")]))
        #expect(try await repository.status().branch == "topic")
        try Data("worktree change\n".utf8).write(to: worktree.appendingPathComponent("a.txt"))
        let snapshot = try await repository.status()
        let selection = try await repository.captureSelection("a.txt", snapshot: snapshot)
        _ = try await repository.createCommit(
            selections: [selection], staged: false, message: "linked commit", amend: false, snapshot: snapshot)
        #expect(try await repository.status().entries.isEmpty)
        #expect(try await fixture.git(["show", "main:a.txt"]).text == "base")
    }

    @Test func historyOutputLimitAndFixedShellTimeoutAreReaped() async throws {
        let fixture = try await GitFixture.make()
        defer { fixture.remove() }
        try fixture.write("a.txt", "base\n")
        _ = try await fixture.git(["add", "."])
        _ = try await fixture.git(
            ["commit", "-F", "-"],
            input: Data(("oversized fixture\n\n" + String(repeating: "x", count: 8_500_000) + "\n").utf8))
        let repository = try #require(await GitRepository.open(root: fixture.root))
        await #expect(throws: GitFailure.self) { try await repository.history(GitHistoryQuery()) }
        #expect(try await repository.status().entries.isEmpty)
        // A fixed, self-owned shell builtin loop exercises timeout/reap. This
        // deliberately overrides the runner flag; public repository APIs never
        // accept arbitrary argv and always disable fsmonitor. No GUI/network.
        await #expect(throws: GitFailure.self) {
            try await GitProcess.run(
                executable: fixture.executable, repository: nil, home: GitFileAccess.canonical(fixture.root),
                arguments: ["-c", "core.fsmonitor=/bin/sh -c 'while :; do :; done'", "status", "--porcelain"],
                network: true, timeout: .milliseconds(100))
        }
        #expect(try await repository.status().entries.isEmpty)
    }
}

private final class GitFixture: @unchecked Sendable {
    let base: URL
    let root: URL
    let executable: URL
    private init(base: URL, root: URL, executable: URL) {
        self.base = base
        self.root = root
        self.executable = executable
    }
    static func make() async throws -> GitFixture {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCodeGitFixture-" + UUID().uuidString)
        let root = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fixture = GitFixture(base: base, root: root, executable: try GitToolchain.installedExecutable())
        _ = try await fixture.git(["init", "--template=", "-b", "main"])
        _ = try await fixture.git(["config", "user.name", "HyCode Fixture"])
        _ = try await fixture.git(["config", "user.email", "fixture@example.invalid"])
        return fixture
    }
    func write(_ path: String, _ text: String) throws {
        let target = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
    }
    func git(_ arguments: [String], directory: URL? = nil, input: Data? = nil) async throws -> GitProcessResult {
        let result = try await GitProcess.run(
            executable: executable, repository: nil, home: GitFileAccess.canonical(directory ?? root),
            arguments: arguments, input: input, write: true)
        guard result.status == 0 else { throw GitFailure("Fixture Git: " + result.diagnostic) }
        return result
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
}
