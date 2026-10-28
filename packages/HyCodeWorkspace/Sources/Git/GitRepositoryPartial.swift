import Foundation

extension GitRepository {
    func checkPartialPolicy(_ paths: [String]) async throws {
        let config = try await localConfiguration()
        guard ["", "false", "no", "off", "0"].contains(config["core.autocrlf"]?.last?.lowercased() ?? "") else {
            throw GitFailure("此仓库配置了换行转换；当前请按整文件提交")
        }
        let result = try await command(
            ["check-attr", "-z", "--stdin", "filter", "text", "eol", "working-tree-encoding", "ident"],
            input: pathData(paths))
        var fields = try GitOutputParser.fields(result.stdout)
        if fields.last == "" { fields.removeLast() }
        guard fields.count.isMultiple(of: 3) else { throw GitFailure("Git 文本属性无效") }
        for i in stride(from: 0, to: fields.count, by: 3) {
            guard ["unspecified", "unset"].contains(fields[i + 2]) else {
                throw GitFailure("此文件配置了内容或编码转换；当前请按整文件提交")
            }
        }
    }

    /// Capture only saved, complete, ordinary UTF-8 blocks. This never writes an
    /// index/blob. Commit preparation revalidates the same versions and policy.
    public func capturePartialSelection(
        _ diff: GitDiff, blocks: Set<Int>, snapshot: GitStatusSnapshot, maximumBytes: Int = 8_388_608
    ) async throws
        -> GitSelection
    {
        try await lease { owner in
            guard diff.comparison == .working, let expected = diff.selection, let comparison = diff.text,
                !blocks.isEmpty, blocks.isSubset(of: Set(comparison.blocks.map(\.id)))
            else {
                throw GitFailure("请先保存并审查完整工作区差异，再选择变更块")
            }
            var selection = try await owner.selection(diff.path, snapshot: snapshot)
            guard selection.sameRevision(as: expected), !selection.bothLayersChanged else {
                throw GitFailure("差异或暂存区已变化，请重新审查；双层更改请使用暂存区模式")
            }
            if blocks.count == comparison.blocks.count { return selection }
            guard selection.paths == [selection.path], let head = selection.head,
                !selection.headObject.allSatisfy({ $0 == "0" })
            else {
                throw GitFailure("新增、删除或重命名文件请按整文件选择")
            }
            try await owner.checkWritePolicy(content: true, paths: [selection.path])
            try await owner.checkPartialPolicy([selection.path])
            let before = try await owner.command(["cat-file", "blob", selection.headObject]).stdout
            let after = try TextFileIO.read(root: owner.identity.root, path: selection.path).bytes
            let left = try GitTextComparison.decode(before)
            let right = try GitTextComparison.decode(after)
            let bom = before.starts(with: [0xef, 0xbb, 0xbf])
            guard bom == after.starts(with: [0xef, 0xbb, 0xbf]),
                left.utf8.elementsEqual(comparison.left.text.utf8), right.utf8.elementsEqual(comparison.right.text.utf8)
            else {
                throw GitFailure("正文或 BOM 已变化；请重新审查，编码变化按整文件提交")
            }
            let tree = try await owner.command(["ls-tree", "-z", head, "--", selection.path]).stdout
            guard let header = String(data: tree.prefix { $0 != 9 }, encoding: .utf8) else {
                throw GitFailure("文件模式无效")
            }
            let fields = header.split(separator: " ")
            guard fields.count == 3, ["100644", "100755"].contains(fields[0]), fields[1] == "blob",
                fields[2] == selection.headObject
            else { throw GitFailure("部分提交仅支持普通文本文件") }
            let data = try GitPartialSelection.contents(
                comparison, selecting: blocks, bom: bom, maximumBytes: maximumBytes)
            try owner.validateSelections([selection], snapshot: snapshot)
            guard try GitFileAccess.digest(GitFileAccess.index(owner.identity)) == selection.indexDigest else {
                throw GitFailure("准备变更块期间暂存区发生变化，请重新审查")
            }
            selection.partial = GitPartialSelection(
                blocks: blocks, contents: data, mode: String(fields[0]),
                preserveIndex: selection.indexObject != selection.headObject)
            return selection
        }
    }
}
