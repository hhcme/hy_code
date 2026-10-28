import Foundation

extension GitRepository {
    func textSources(path: String, comparison: GitComparison, status: GitStatusSnapshot, entry: GitStatusEntry?)
        async throws -> (String, String)
    {
        func blob(_ object: String?) async throws -> String {
            guard let object, !object.allSatisfy({ $0 == "0" }) else { return "" }
            let blobObject: String
            if let colon = object.firstIndex(of: ":") {
                let tree = String(object[..<colon])
                let file = String(object[object.index(after: colon)...])
                let args =
                    tree.isEmpty
                    ? ["ls-files", "--stage", "-z", "--", file]
                    : ["ls-tree", "--full-name", "-z", tree, "--", file]
                let entry = try await command(args)
                guard !entry.stdout.isEmpty else { return "" }
                let record = entry.stdout.split(separator: 0, omittingEmptySubsequences: true)
                guard record.count == 1, let tab = record[0].firstIndex(of: 9),
                    let header = String(data: record[0][..<tab], encoding: .utf8)
                else {
                    throw GitFailure("Git 文本版本不是单个完整条目")
                }
                let fields = header.split(separator: " ")
                guard fields.count == 3, tree.isEmpty ? fields[2] == "0" : fields[1] == "blob" else {
                    throw GitFailure("此版本不是普通文本对象")
                }
                blobObject = String(tree.isEmpty ? fields[1] : fields[2])
            } else {
                blobObject = object
            }
            guard GitOutputParser.object(blobObject) else { throw GitFailure("Git 文本对象无效") }
            let result = try await command(["cat-file", "blob", blobObject])
            return try GitTextComparison.decode(result.stdout)
        }
        func disk() throws -> String {
            if entry?.worktreeStatus == "D" || entry?.indexStatus == "D" && entry?.unstaged != true { return "" }
            return try GitTextComparison.decode(TextFileIO.read(root: identity.root, path: path).bytes)
        }
        let oldPath = entry?.originalPath ?? path
        switch comparison {
        case .working:
            let a = entry?.untracked == true ? nil : status.head.map { $0 + ":" + oldPath }
            return try await (blob(a), disk())
        case .staged:
            return try await (blob(status.head.map { $0 + ":" + oldPath }), blob(entry?.indexObject ?? ":" + path))
        case .unstaged:
            return try await (blob(entry?.indexObject ?? ":" + path), disk())
        case .commit(let object, let parent):
            return try await (blob(parent.map { $0 + ":" + path }), blob(object + ":" + path))
        case .objects(let a, let b): return try await (blob(a + ":" + path), blob(b + ":" + path))
        }
    }

    /// Read-only comparison of a revision-checked buffer snapshot against the
    /// already reviewed immutable baseline. Scratch files live in the private
    /// Git home, never the workspace or index; the result cannot be committed.
    public func preview(_ base: GitDiff, buffer: String) async throws -> GitDiff {
        try await lease { owner in
            guard base.comparison == .working || base.comparison == .unstaged, let sources = base.text,
                sources.left.text.utf8.count + buffer.utf8.count <= 8_388_608, !buffer.contains("\0")
            else { throw GitFailure("当前比较不能生成编辑预览", code: .resourceBudget) }
            let directory = owner.home.appendingPathComponent("preview-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let left = directory.appendingPathComponent("before")
            let right = directory.appendingPathComponent("after")
            for (url, text) in [(left, sources.left.text), (right, buffer)] {
                guard
                    FileManager.default.createFile(
                        atPath: url.path, contents: Data(text.utf8),
                        attributes: [.posixPermissions: 0o600])
                else {
                    throw GitFailure("无法创建私有差异快照")
                }
            }
            let (patch, rows) = try await owner.diffProjection(
                [
                    "diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=20000", "--",
                    left.path, right.path,
                ], allowed: [0, 1])
            let text = try GitTextComparison.make(left: sources.left.text, right: buffer, rows: rows)
            let widths = try GitDiffText.widths(rows)
            let message: String?
            if patch.isEmpty {
                message = base.patch.isEmpty ? "这两个版本没有差异" : base.message ?? "正文与左侧相同；已保存版本仍有 Git 更改"
            } else {
                message = nil
            }
            var result = GitDiff(
                id: UUID(), path: base.path, comparison: base.comparison, leftTitle: base.leftTitle,
                rightTitle: "工作区", patch: patch, rows: rows, unifiedRows: GitDiffParser.unified(rows),
                leftWidth: widths.left, rightWidth: widths.right, message: message,
                differenceRows: GitDiffParser.changeStarts(rows), selection: nil)
            result.text = text
            result.editableWorkingText = base.editableWorkingText
            return result
        }
    }
}
