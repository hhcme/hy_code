import Foundation

/// Owns one repository's process context. A scheduler lease spans each complete
/// operation (including preview/validation), rather than each individual command.
public actor GitRepository {
    public nonisolated let identity: GitRepositoryIdentity
    let executable: URL
    let home: URL
    static let logFormat = "%H%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%D%x00%B"

    private init(identity: GitRepositoryIdentity, executable: URL, home: URL) {
        self.identity = identity
        self.executable = executable
        self.home = home
    }
    deinit { try? FileManager.default.removeItem(at: home) }

    public static func open(root: URL, executable: URL? = nil, authorizedDirectories: [URL] = []) async throws
        -> GitRepository?
    {
        let repository = try await Task.detached(priority: .utility) {
            guard let identity = try GitFileAccess.discover(root: root, authorizedDirectories: authorizedDirectories)
            else { return nil as GitRepository? }
            let tool = try executable ?? GitToolchain.installedExecutable()
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("HyCodeGit-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            return GitRepository(identity: identity, executable: tool, home: try GitFileAccess.canonical(home))
        }.value
        if let repository { try await repository.checkVersion() }
        return repository
    }
    private func checkVersion() async throws {
        let result = try await command(["--version"])
        let parts = result.text.split(separator: " ").dropFirst(2).first?.split(separator: ".") ?? []
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]),
            major > 2 || (major == 2 && minor >= 48)
        else {
            throw GitFailure("Git 需要 2.48 或更新版本；当前安装的版本不在受限执行适配范围")
        }
    }
    func lease<T: Sendable>(write: Bool = false, _ action: (isolated GitRepository) async throws -> T) async throws -> T
    {
        let token = try await GitScheduler.shared.acquire(scope: identity.commonDirectory.path, write: write)
        do {
            try Task.checkCancellation()
            let result = try await action(self)
            await GitScheduler.shared.release(token)
            return result
        } catch {
            await GitScheduler.shared.release(token)
            throw error
        }
    }
    func command(
        _ arguments: [String], input: Data? = nil, environment: [String: String] = [:],
        write: Bool = false, network: Bool = false, ssh: Bool = false, limit: Int = 8_388_608,
        allowed: Set<Int32> = [0], timeout: Duration = .seconds(20), remoteDirectory: URL? = nil
    ) async throws -> GitProcessResult {
        let result = try await GitProcess.run(
            executable: executable, repository: identity, home: home, arguments: arguments, input: input,
            environment: environment, write: write, network: network, ssh: ssh, remoteDirectory: remoteDirectory,
            limit: limit,
            timeout: timeout)
        guard allowed.contains(result.status) else {
            if result.diagnostic.contains("identity unknown")
                || result.diagnostic.contains("unable to auto-detect email")
            {
                throw GitFailure("当前仓库缺少提交身份，请在 Git 的“仓库身份与远端”设置姓名与邮箱；不会读取或修改全局 Git 身份")
            }
            throw GitFailure(result.diagnostic.isEmpty ? "Git 操作失败（退出 \(result.status)）" : result.diagnostic)
        }
        return result
    }

    public func status() async throws -> GitStatusSnapshot { try await lease { try await $0.readStatus() } }
    func readStatus() async throws -> GitStatusSnapshot {
        let index = try GitFileAccess.index(identity)
        let result = try await command([
            "status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all", "--ignore-submodules=none",
        ])
        let after = try GitFileAccess.index(identity)
        guard index == after else { throw GitFailure("Git 暂存区正在变化，请刷新重试") }
        let parsed = try GitOutputParser.status(result.stdout)
        var operation: String?
        for (name, title) in [
            ("MERGE_HEAD", "合并中"), ("rebase-merge", "变基中"), ("rebase-apply", "变基/应用补丁中"), ("CHERRY_PICK_HEAD", "拣选中"),
            ("REVERT_HEAD", "还原中"),
        ] {
            if (try? GitFileAccess.info(identity.directory.appendingPathComponent(name))) != nil {
                operation = title
                break
            }
        }
        return GitStatusSnapshot(
            repository: identity, head: parsed.head, branch: parsed.branch, upstream: parsed.upstream,
            ahead: parsed.ahead, behind: parsed.behind, entries: parsed.entries,
            indexDigest: GitFileAccess.digest(after), operation: operation, capturedAt: Date())
    }

    public func references() async throws -> [GitReference] {
        try await lease { owner in
            let result = try await owner.command([
                "for-each-ref", "--count=10001", "--sort=refname",
                "--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00",
                "refs/heads", "refs/remotes", "refs/tags",
            ])
            let refs = try GitOutputParser.references(result.stdout)
            guard refs.count <= 10_000 else { throw GitFailure("Git 引用超过 10,000 项，请缩小仓库范围") }
            return refs
        }
    }

    public func history(_ query: GitHistoryQuery, tips: [String] = [], offset: Int = 0) async throws -> GitHistoryPage {
        try await lease { owner in
            guard offset >= 0, offset < 100_000, query.text.utf8.count <= 512, query.author.utf8.count <= 512 else {
                throw GitFailure("Git 日志查询超过范围")
            }
            var ends = tips
            if ends.isEmpty {
                if query.allReferences {
                    let refs = try await owner.command([
                        "for-each-ref", "--count=1001", "--format=%(objectname)", "refs/heads", "refs/remotes",
                        "refs/tags",
                    ])
                    ends = Array(Set(refs.text.split(separator: "\n").map(String.init))).sorted()
                    guard ends.count <= 1000 else { throw GitFailure("全部引用过多，请选择一个分支查看日志") }
                } else {
                    let reference = query.reference ?? "HEAD"
                    let resolved = try await owner.command(
                        ["rev-parse", "--verify", "--end-of-options", reference + "^{commit}"], allowed: [0, 128])
                    if resolved.status == 0 { ends = [resolved.text] }
                }
            }
            guard !ends.isEmpty else { return GitHistoryPage(commits: [], tips: [], nextOffset: nil) }
            guard ends.allSatisfy(GitOutputParser.object) else { throw GitFailure("日志端点无效") }
            var args = [
                "log", "--topo-order", "-z", "--format=" + Self.logFormat, "--max-count=201", "--skip=\(offset)",
                "--no-show-signature", "--fixed-strings",
            ]
            if !query.text.isEmpty { args.append("--grep=" + query.text) }
            if !query.author.isEmpty { args.append("--author=" + query.author) }
            if let since = query.since, let until = query.until,
                Calendar.current.startOfDay(for: since) > Calendar.current.startOfDay(for: until)
            {
                throw GitFailure("开始日期不能晚于结束日期")
            }
            if let date = query.since {
                args.append("--since=@\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))")
            }
            if let date = query.until,
                let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))
            {
                args.append("--until=@\(Int(end.timeIntervalSince1970) - 1)")
            }
            args += ends + ["--"]
            if !query.path.isEmpty { args.append(try GitOutputParser.path(query.path)) }
            let result = try await owner.command(args)
            let commits = try GitOutputParser.commits(result.stdout)
            return GitHistoryPage(
                commits: Array(commits.prefix(200)), tips: ends, nextOffset: commits.count > 200 ? offset + 200 : nil)
        }
    }

    public func commit(_ object: String) async throws -> GitCommit {
        try await lease { owner in
            guard GitOutputParser.object(object) else { throw GitFailure("提交对象无效") }
            let result = try await owner.command([
                "log", "-1", "-z", "--format=" + Self.logFormat, "--no-show-signature", object, "--",
            ])
            guard let value = try GitOutputParser.commits(result.stdout).first else { throw GitFailure("未找到提交") }
            return value
        }
    }
    public func findCommit(_ prefix: String) async throws -> GitCommit {
        try await lease { owner in
            let prefix = prefix.lowercased()
            guard (4...64).contains(prefix.utf8.count),
                prefix.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { throw GitFailure("请提供至少 4 位十六进制提交哈希") }
            let object = try await owner.command(["rev-parse", "--verify", "--end-of-options", prefix + "^{commit}"])
                .text
            guard GitOutputParser.object(object), object.hasPrefix(prefix) else {
                throw GitFailure("未找到唯一的提交对象，请提供更长哈希")
            }
            let result = try await owner.command([
                "log", "-1", "-z", "--format=" + Self.logFormat, "--no-show-signature", object, "--",
            ])
            guard let commit = try GitOutputParser.commits(result.stdout).first, commit.object == object else {
                throw GitFailure("提交定位失败")
            }
            return commit
        }
    }

    public func files(in object: String, parent: String? = nil) async throws -> [GitCommitFile] {
        try await lease { owner in
            guard GitOutputParser.object(object), parent == nil || GitOutputParser.object(parent!) else {
                throw GitFailure("提交对象无效")
            }
            let args =
                parent.map {
                    ["diff", "--name-status", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", $0, object, "--"]
                }
                ?? ["diff-tree", "--root", "-r", "--no-commit-id", "--name-status", "-z", "--no-renames", object, "--"]
            return try GitOutputParser.changedFiles(await owner.command(args).stdout)
        }
    }

    public func captureSelection(_ path: String, snapshot: GitStatusSnapshot) async throws -> GitSelection {
        try await lease { owner in try await owner.selection(path, snapshot: snapshot) }
    }
    public func captureSelections(_ paths: [String], snapshot: GitStatusSnapshot) async throws -> [GitSelection] {
        try await lease { owner in
            let current = try await owner.readStatus()
            guard current.head == snapshot.head, current.indexDigest == snapshot.indexDigest else {
                throw GitFailure("仓库状态已改变，请重新选择")
            }
            let entries = Dictionary(uniqueKeysWithValues: current.entries.map { ($0.path, $0) })
            return try paths.map { path in
                try Task.checkCancellation()
                guard let entry = entries[path], !entry.conflicted, !entry.submodule else {
                    throw GitFailure("文件已改变或需要专用处理")
                }
                return try owner.makeSelection(entry, snapshot: current)
            }
        }
    }
    func selection(_ path: String, snapshot: GitStatusSnapshot) async throws -> GitSelection {
        let current = try await readStatus()
        guard current.head == snapshot.head, current.indexDigest == snapshot.indexDigest,
            let entry = current.entries.first(where: { $0.path == path }), !entry.conflicted, !entry.submodule
        else {
            throw GitFailure("仓库或暂存区已改变，或文件需要专用处理；请重新查看差异")
        }
        return try makeSelection(entry, snapshot: current)
    }
    private func makeSelection(_ entry: GitStatusEntry, snapshot current: GitStatusSnapshot) throws -> GitSelection {
        var digests: [String: String] = [:]
        for item in entry.paths { digests[item] = try GitFileAccess.diskDigest(item, repository: identity) }
        return GitSelection(
            path: entry.path, paths: entry.paths, head: current.head, indexDigest: current.indexDigest,
            diskDigests: digests, indexObject: entry.indexObject, headObject: entry.headObject,
            bothLayersChanged: entry.staged && entry.unstaged)
    }

    public func diff(path: String, comparison: GitComparison, snapshot: GitStatusSnapshot? = nil) async throws
        -> GitDiff
    {
        try await lease { owner in try await owner.readDiff(path: path, comparison: comparison, snapshot: snapshot) }
    }
    func diffProjection(_ arguments: [String], allowed: Set<Int32>) async throws -> (String, [GitDiffRow]) {
        let result = try await command(arguments, allowed: allowed)
        guard let patch = String(data: result.stdout, encoding: .utf8) else {
            throw GitFailure("差异不是有效 UTF-8，无法逐行显示")
        }
        return (patch, try GitDiffParser.rows(patch))
    }
    private func readDiff(path: String, comparison: GitComparison, snapshot: GitStatusSnapshot?) async throws -> GitDiff
    {
        _ = try GitOutputParser.path(path)
        let status = try await readStatus()
        let entry = status.entries.first { $0.path == path }
        let paths = entry?.paths ?? [path]
        var candidate: GitSelection?
        var args = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames", "--unified=20000"]
        var left = "HEAD · " + (status.head.map { String($0.prefix(8)) } ?? "空基线")
        var right = "工作区（已保存）"
        var sourceObjects: [String] = []
        var disk = false
        var allowed: Set<Int32> = [0]
        switch comparison {
        case .working:
            disk = true
            if let head = status.head {
                args.append(head)
                sourceObjects.append(head)
            }
            if status.head == nil || entry?.untracked == true {
                args = [
                    "diff", "--no-index", "--no-ext-diff", "--no-textconv", "--no-color", "--unified=20000", "--",
                    "/dev/null", path,
                ]
                left = "空基线"
                allowed = [0, 1]
            } else {
                args += ["--"] + paths
            }
        case .staged:
            args += ["--cached"] + (status.head.map { [$0] } ?? []) + ["--"] + paths
            if let head = status.head { sourceObjects.append(head) }
            if let entry, GitOutputParser.object(entry.indexObject) { sourceObjects.append(entry.indexObject) }
            right = "暂存区 · index"
        case .unstaged:
            disk = true
            args += ["--"] + paths
            left = "暂存区 · index"
            if let entry, GitOutputParser.object(entry.indexObject) { sourceObjects.append(entry.indexObject) }
        case .commit(let object, let parent):
            guard GitOutputParser.object(object), parent == nil || GitOutputParser.object(parent!) else {
                throw GitFailure("历史差异对象无效")
            }
            sourceObjects = [object] + (parent.map { [$0] } ?? [])
            left = parent.map { "父提交 · " + String($0.prefix(8)) } ?? "空基线"
            right = "提交 · " + String(object.prefix(8))
            if let parent {
                args += [parent, object, "--", path]
            } else {
                args = [
                    "show", "--format=", "--root", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
                    "--unified=20000", object, "--", path,
                ]
            }
        case .objects(let a, let b):
            guard GitOutputParser.object(a), GitOutputParser.object(b) else { throw GitFailure("比较对象无效") }
            sourceObjects = [a, b]
            left = String(a.prefix(8))
            right = String(b.prefix(8))
            args += [a, b, "--", path]
        }
        var size: Int64 = 0
        var metadataOnly: String?
        if disk, let info = try? GitFileAccess.info(identity.root.appendingPathComponent(path)) {
            if info.st_mode & 0o170000 != 0o100000 {
                metadataOnly = "链接、子模块或特殊文件只显示 Git 元数据，不读取目标内容"
            } else {
                size += info.st_size
            }
        }
        for object in sourceObjects where !object.allSatisfy({ $0 == "0" }) {
            let values = object == entry?.indexObject ? [object] : paths.map { object + ":" + $0 }
            for value in values {
                let result = try await command(["cat-file", "-s", value], allowed: [0, 128])
                if result.status == 0, let bytes = Int64(result.text), bytes >= 0 {
                    if bytes > 8_388_608 { metadataOnly = "文件超过 8 MiB 差异读取预算；未完成全文审查，可打开源文件" } else { size += bytes }
                }
            }
        }
        if size > 8_388_608 { metadataOnly = "比较输入合计超过 8 MiB；未完成全文差异审查，可打开源文件" }
        if entry?.submodule == true || entry?.conflicted == true { metadataOnly = "此项为子模块或未解决冲突，请使用专用 Git 工具处理" }
        if let message = metadataOnly {
            return GitDiff(
                id: UUID(), path: path, comparison: comparison, leftTitle: left, rightTitle: right, patch: "", rows: [],
                unifiedRows: [], leftWidth: 0, rightWidth: 0, message: message, differenceRows: [], selection: nil)
        }
        if disk, entry != nil { candidate = try await selection(path, snapshot: snapshot ?? status) }
        let patch: String
        let rows: [GitDiffRow]
        do {
            (patch, rows) = try await diffProjection(args, allowed: allowed)
        } catch let failure as GitFailure where failure.code == .resourceBudget {
            // Keep ordinary files in full source context. A large unchanged
            // region falls back to bounded hunks, with explicit omitted rows.
            var compact = args
            if let option = compact.firstIndex(of: "--unified=20000") { compact[option] = "--unified=4" }
            (patch, rows) = try await diffProjection(compact, allowed: allowed)
        }
        var text: GitTextComparison?
        var textNotice: String?
        var editableWorkingText = false
        if !rows.contains(where: { $0.kind == .header }) {
            do {
                let sources = try await textSources(path: path, comparison: comparison, status: status, entry: entry)
                text = try GitTextComparison.make(left: sources.0, right: sources.1, rows: rows)
                if disk, entry?.worktreeStatus != "D", !(entry?.indexStatus == "D" && entry?.unstaged != true) {
                    editableWorkingText = !(try TextFileIO.needsPaging(root: identity.root, path: path))
                    if !editableWorkingText { textNotice = "此文件使用分段编辑；差异只读，可打开源文件编辑" }
                }
            } catch is CancellationError { throw CancellationError() } catch {
                textNotice = "只读差异：" + error.localizedDescription
            }
        } else {
            textNotice = "当前已省略未修改的上下文；只读显示，可打开源文件编辑"
        }
        if comparison == .working || comparison == .staged || comparison == .unstaged {
            guard try GitFileAccess.digest(GitFileAccess.index(identity)) == status.indexDigest else {
                throw GitFailure("生成差异期间暂存区发生变化，请刷新后重新审查")
            }
        }
        if let candidate {
            for (item, digest) in candidate.diskDigests
            where try GitFileAccess.diskDigest(item, repository: identity) != digest {
                throw GitFailure("生成差异期间文件发生变化，请刷新后重新审查")
            }
        }
        let unified = rows.flatMap { row -> [GitDiffRow] in
            if row.kind != .changed { return [row] }
            return [
                GitDiffRow(
                    id: row.id, leftNumber: row.leftNumber, rightNumber: nil, left: row.left, right: nil,
                    kind: .removed, leftChange: row.leftChange, rightChange: nil),
                GitDiffRow(
                    id: row.id, leftNumber: nil, rightNumber: row.rightNumber, left: nil, right: row.right,
                    kind: .added, leftChange: nil, rightChange: row.rightChange),
            ]
        }
        let message: String?
        if patch.isEmpty {
            message = "这两个版本没有差异"
        } else if patch.components(separatedBy: "\n").contains(where: {
            $0 == "GIT binary patch" || $0.hasPrefix("Binary files ")
        }) {
            message = "二进制内容不提供文本比较"
        } else if rows.isEmpty {
            message = "文件路径或属性发生变化，没有文本行差异"
        } else {
            message = nil
        }
        let widths = try GitDiffText.widths(rows)
        var diff = GitDiff(
            id: UUID(), path: path, comparison: comparison, leftTitle: left, rightTitle: right, patch: patch,
            rows: rows, unifiedRows: unified,
            leftWidth: widths.left, rightWidth: widths.right,
            message: message ?? textNotice, differenceRows: GitDiffParser.changeStarts(rows), selection: candidate)
        diff.text = text
        diff.editableWorkingText = editableWorkingText
        return diff
    }
}
