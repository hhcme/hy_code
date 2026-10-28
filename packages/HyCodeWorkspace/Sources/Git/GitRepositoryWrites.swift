import Darwin
import Foundation

extension GitRepository {
    func localConfiguration() async throws -> [String: [String]] {
        var values: [String: [String]] = [:]
        for scope in ["--local", "--worktree"] {
            if scope == "--worktree",
                !["true", "yes", "on", "1"].contains(values["extensions.worktreeconfig"]?.last?.lowercased() ?? "false")
            {
                continue
            }
            let result = try await command(["config", scope, "--no-includes", "--null", "--list"])
            for record in try GitOutputParser.fields(result.stdout) where !record.isEmpty {
                let parts = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(parts[0])
                if key == "include.path" || key.lowercased().hasPrefix("includeif.") {
                    throw GitFailure("受限 Git 不读取仓库配置中的 include/includeIf")
                }
                values[key, default: []].append(parts.count == 2 ? String(parts[1]) : "")
            }
        }
        return values
    }
    func checkWritePolicy(content: Bool = false, paths: [String] = [], network: Bool = false) async throws {
        try GitFileAccess.validateMetadata(identity)
        let config = try await localConfiguration()
        if config["commit.gpgsign"]?.last.map({ ["true", "yes", "on", "1"].contains($0.lowercased()) }) == true {
            throw GitFailure("此仓库要求签名提交；当前受限 Git 不执行外部签名程序，也不会自动关闭签名，请使用专用 Git 工具提交")
        }
        var hooks = identity.commonDirectory.appendingPathComponent("hooks")
        if let path = config["core.hookspath"]?.last, path != "/dev/null" {
            hooks = path.hasPrefix("/") ? URL(fileURLWithPath: path) : identity.root.appendingPathComponent(path)
            guard
                ([identity.authorizedRoot] + identity.additionalAuthorizedDirectories).contains(where: {
                    GitFileAccess.contains($0, hooks.standardizedFileURL)
                })
            else {
                throw GitFailure("Git hooks 路径在授权项目之外；当前受限模式不执行或跳过它们")
            }
        }
        if FileManager.default.fileExists(atPath: hooks.path) {
            let physical = try GitFileAccess.canonical(hooks)
            guard
                ([identity.authorizedRoot] + identity.additionalAuthorizedDirectories).contains(where: {
                    GitFileAccess.contains($0, physical)
                })
            else { throw GitFailure("Git hooks 越出授权项目") }
            let names = try FileManager.default.contentsOfDirectory(atPath: hooks.path)
            guard names.count <= 128 else { throw GitFailure("Git hooks 数量超过检查预算") }
            let executableHooks: Set<String> = [
                "applypatch-msg", "pre-applypatch", "post-applypatch", "pre-commit", "pre-merge-commit",
                "prepare-commit-msg", "commit-msg", "post-commit", "pre-rebase", "post-checkout", "post-merge",
                "pre-push", "pre-receive", "update", "proc-receive", "post-receive", "post-update",
                "reference-transaction", "push-to-checkout", "pre-auto-gc", "post-rewrite", "sendemail-validate",
            ]
            if names.contains(where: {
                executableHooks.contains($0)
                    && FileManager.default.isExecutableFile(atPath: hooks.appendingPathComponent($0).path)
            }) {
                throw GitFailure("仓库存在可执行 Git hooks；此版本的受限模式不执行项目 hooks，也不会静默跳过，请使用专用 Git 工具完成此操作")
            }
        }
        if content {
            if config.keys.contains(where: { $0.hasPrefix("filter.") }) {
                throw GitFailure("仓库配置了外部内容过滤器；受限 Git 不运行过滤器，也不会将未过滤内容提交")
            }
            if !paths.isEmpty {
                let result = try await command(["check-attr", "-z", "--stdin", "--all"], input: pathData(paths))
                let attributes = try GitOutputParser.fields(result.stdout)
                var index = 0
                while index + 2 < attributes.count {
                    if attributes[index + 1] == "filter", !["unset", "unspecified"].contains(attributes[index + 2]) {
                        throw GitFailure("所选文件需要 Git 内容过滤器（例如 LFS）；请使用已配置过滤器的专用 Git 工具处理")
                    }
                    index += 3
                }
            }
        }
        if network,
            config.keys.contains(where: {
                $0.hasPrefix("url.") || $0.hasPrefix("http.") || $0.hasPrefix("credential.") || $0 == "core.gitproxy"
                    || ($0.hasPrefix("remote.")
                        && [".vcs", ".uploadpack", ".receivepack", ".proxy"].contains(where: $0.hasSuffix))
            })
        {
            throw GitFailure("仓库包含自定义 URL、HTTP、凭据或传输助手配置；当前受限远端适配不执行这些设置，请使用专用 Git 工具")
        }
    }
    func pathData(_ paths: [String]) -> Data { Data((paths.joined(separator: "\0") + "\0").utf8) }
    func requireSnapshot(_ snapshot: GitStatusSnapshot, allowOperation: Bool = false) async throws -> GitStatusSnapshot
    {
        let current = try await readStatus()
        guard current.head == snapshot.head, current.branch == snapshot.branch,
            current.indexDigest == snapshot.indexDigest
        else {
            throw GitFailure("Git 分支或暂存区已改变，请刷新并重新审查")
        }
        guard !current.hasConflicts, allowOperation || current.operation == nil else {
            throw GitFailure("仓库有冲突或尚未完成的 Git 操作；请先在专用 Git 工具中完成或中止")
        }
        return current
    }
    func validateSelections(_ selections: [GitSelection], snapshot: GitStatusSnapshot) throws {
        for selection in selections {
            guard selection.head == snapshot.head, selection.indexDigest == snapshot.indexDigest else {
                throw GitFailure("提交勾选来自旧版本，请重新查看差异并勾选")
            }
            guard !selection.bothLayersChanged else {
                throw GitFailure("同一文件同时包含暂存与未暂存变化；请使用暂存区模式明确提交来源")
            }
            for (path, digest) in selection.diskDigests {
                guard try GitFileAccess.diskDigest(path, repository: identity) == digest else {
                    throw GitFailure("所选文件在审查后发生变化，未提交；请刷新并重新勾选")
                }
            }
        }
    }

    public func createCommit(
        selections: [GitSelection], staged: Bool, message: String, amend: Bool, snapshot: GitStatusSnapshot
    ) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            if !staged { _ = try GitPartialSelection.retainedBytes(selections) }
            let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, !message.contains("\0"), message.utf8.count <= 65_536 else {
                throw GitFailure("提交消息不能为空或超过 64 KiB")
            }
            var current = try await owner.requireSnapshot(snapshot)
            guard current.branch != nil else { throw GitFailure("分离 HEAD 状态暂不创建提交，请先创建或切换分支") }
            guard !amend || current.head != nil else { throw GitFailure("尚无可修正的提交") }
            guard staged || !selections.isEmpty || amend else { throw GitFailure("请先选择本次提交的文件") }
            let paths = Array(Set(selections.flatMap(\.paths))).sorted()
            try await owner.checkWritePolicy(content: !staged, paths: paths)
            if !staged { try owner.validateSelections(selections, snapshot: current) }
            let partial = staged ? [] : selections.filter { $0.partial != nil }
            if !partial.isEmpty { try await owner.checkPartialPolicy(partial.map(\.path)) }
            let reservation = try GitIndexReservation(repository: owner.identity)
            let oldIndex = try GitFileAccess.index(owner.identity)
            guard GitFileAccess.digest(oldIndex) == snapshot.indexDigest else { throw GitFailure("预留期间 Git 暂存区发生变化") }
            let candidate = owner.home.appendingPathComponent("candidate-" + UUID().uuidString)
            let reconciled = owner.home.appendingPathComponent("reconcile-" + UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: candidate)
                try? FileManager.default.removeItem(at: reconciled)
            }
            let candidateEnvironment = ["GIT_INDEX_FILE": candidate.path]
            if staged, !oldIndex.isEmpty {
                try oldIndex.write(to: candidate, options: .withoutOverwriting)
            } else if let head = current.head {
                _ = try await owner.command(["read-tree", head], environment: candidateEnvironment, write: true)
            } else {
                _ = try await owner.command(["read-tree", "--empty"], environment: candidateEnvironment, write: true)
            }
            let wholePaths = Array(Set(selections.filter { $0.partial == nil }.flatMap(\.paths))).sorted()
            if !staged, !wholePaths.isEmpty {
                _ = try await owner.command(
                    ["add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul"], input: owner.pathData(wholePaths),
                    environment: candidateEnvironment, write: true)
            }
            for selection in partial {
                guard let part = selection.partial else { continue }
                let object = try await owner.command(
                    ["hash-object", "-w", "--stdin"], input: part.contents, write: true
                ).text
                guard GitOutputParser.object(object) else { throw GitFailure("部分提交对象无效") }
                let entry = Data((part.mode + " " + object + "\t" + selection.path + "\0").utf8)
                _ = try await owner.command(
                    ["update-index", "-z", "--index-info"], input: entry,
                    environment: candidateEnvironment, write: true)
            }
            let tree = try await owner.command(["write-tree"], environment: candidateEnvironment, write: true).text
            guard GitOutputParser.object(tree) else { throw GitFailure("候选提交树无效") }
            if !amend {
                if let head = current.head {
                    let previous = try await owner.command(["rev-parse", "--verify", head + "^{tree}"]).text
                    guard tree != previous else { throw GitFailure("所选内容没有可提交的变化") }
                } else {
                    let list = try await owner.command(["ls-tree", tree], limit: 1_048_576)
                    guard !list.stdout.isEmpty else { throw GitFailure("初始提交没有文件") }
                }
            }
            // Precompute a new real index from the original index and the
            // selected tree, keeping every unselected staged entry unchanged.
            let reconciliationEnvironment = ["GIT_INDEX_FILE": reconciled.path]
            if staged {
                try GitFileAccess.smallFile(candidate, limit: 67_108_864).write(
                    to: reconciled, options: .withoutOverwriting)
            } else {
                if oldIndex.isEmpty {
                    _ = try await owner.command(
                        ["read-tree", "--empty"], environment: reconciliationEnvironment, write: true)
                } else {
                    try oldIndex.write(to: reconciled, options: .withoutOverwriting)
                }
                let preserved = Set(partial.filter { $0.partial?.preserveIndex == true }.map(\.path))
                for batch in owner.pathBatches(paths.filter { !preserved.contains($0) }) {
                    let entries = try await owner.command(
                        ["ls-files", "--stage", "-z", "--"] + batch, environment: candidateEnvironment)
                    var updates = Data()
                    for path in batch {
                        updates.append(
                            Data(("0 " + String(repeating: "0", count: tree.count) + "\t" + path + "\0").utf8))
                    }
                    updates.append(entries.stdout)
                    _ = try await owner.command(
                        ["update-index", "-z", "--index-info"], input: updates, environment: reconciliationEnvironment,
                        write: true)
                }
            }
            try reservation.prepare(GitFileAccess.smallFile(reconciled, limit: 67_108_864))
            var args = ["commit-tree", tree]
            var environment = candidateEnvironment
            if amend, let head = current.head {
                let result = try await owner.command(["log", "-1", "-z", "--format=" + Self.logFormat, head, "--"])
                guard let original = try GitOutputParser.commits(result.stdout).first else {
                    throw GitFailure("无法读取修正提交的作者和父提交")
                }
                args += original.parents.flatMap { ["-p", $0] }
                environment["GIT_AUTHOR_NAME"] = original.author
                environment["GIT_AUTHOR_EMAIL"] = original.email
                environment["GIT_AUTHOR_DATE"] = try await owner.command(["show", "-s", "--format=%aI", head, "--"])
                    .text
            } else if let head = current.head {
                args += ["-p", head]
            }
            args += ["-F", "-"]
            let commit = try await owner.command(
                args, input: Data((message + "\n").utf8), environment: environment, write: true
            ).text
            guard GitOutputParser.object(commit) else { throw GitFailure("Git 没有返回有效的新提交") }
            current = try await owner.requireSnapshot(snapshot)
            if !staged { try owner.validateSelections(selections, snapshot: current) }
            if !partial.isEmpty { try await owner.checkPartialPolicy(partial.map(\.path)) }
            guard let branch = current.branch else { throw GitFailure("Git 分支已改变，未更新引用") }
            let ref = "refs/heads/" + branch
            let old = current.head ?? String(repeating: "0", count: commit.count)
            // A local CAS is a short, bounded commit point. Once dispatched,
            // cancellation waits for it and index installation rather than
            // converting an already committed ref into an abandoned index.
            do {
                _ = try await Task.detached(priority: .utility) {
                    try await owner.command(
                        [
                            "update-ref", "--no-deref", "-m", amend ? "HyCode: amend" : "HyCode: commit", ref, commit,
                            old,
                        ], write: true)
                }.value
            } catch {
                let committed = try? await Task.detached(priority: .utility) {
                    try await owner.command(["rev-parse", "--verify", "--end-of-options", ref]).text == commit
                }.value
                if committed != true { throw error }
            }
            let activeRef = try? await Task.detached(priority: .utility) {
                try await owner.command(["symbolic-ref", "-q", "HEAD"]).text
            }.value
            guard activeRef == ref else {
                reservation.preserveForRecovery()
                throw GitFailure(
                    "本地分支 \(branch) 已提交 \(commit.prefix(8))，但外部改变了 HEAD；当前索引未覆盖，候选索引保留于 .git/index.lock，请核对恢复，不要重复提交")
            }
            // Once the ref transaction succeeds this is a committed operation;
            // do not observe cancellation between it and index installation.
            try reservation.install(description: "本地分支 \(branch) 已提交 \(commit.prefix(8))")
            return GitWriteResult(
                summary: amend ? "已修正上次提交" : "本地提交完成", commit: commit, workingTreeChanged: false,
                detail: String(commit.prefix(8)))
        }
    }

    public func fileAction(_ action: GitFileAction, selections: [GitSelection], snapshot: GitStatusSnapshot)
        async throws -> GitWriteResult
    {
        try await lease(write: true) { owner in
            let current = try await owner.requireSnapshot(snapshot)
            guard !selections.isEmpty else { throw GitFailure("请先选择文件") }
            for selection in selections {
                guard selection.head == current.head, selection.indexDigest == current.indexDigest else {
                    throw GitFailure("文件选择已过期")
                }
                for (path, digest) in selection.diskDigests
                where try GitFileAccess.diskDigest(path, repository: owner.identity) != digest {
                    throw GitFailure("文件在审查后改变，未执行 Git 修改")
                }
            }
            let paths = Array(
                Set(
                    selections.flatMap { selection -> [String] in
                        if action == .discardUnstaged { return [selection.path] }
                        if action == .stage, let entry = current.entries.first(where: { $0.path == selection.path }),
                            "RC".contains(entry.indexStatus)
                        {
                            return [selection.path]
                        }
                        return selection.paths
                    })
            ).sorted()
            try await owner.checkWritePolicy(content: true, paths: paths)
            let reservation = try GitIndexReservation(repository: owner.identity)
            let originalIndex = try GitFileAccess.index(owner.identity)
            guard GitFileAccess.digest(originalIndex) == snapshot.indexDigest else { throw GitFailure("操作前暂存区已经变化") }
            let candidate = owner.home.appendingPathComponent("file-action-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: candidate) }
            let environment = ["GIT_INDEX_FILE": candidate.path]
            if originalIndex.isEmpty {
                _ = try await owner.command(["read-tree", "--empty"], environment: environment, write: true)
            } else {
                try originalIndex.write(to: candidate, options: .withoutOverwriting)
            }
            let args: [String]
            let title: String
            let disk: Bool
            switch action {
            case .stage:
                args = ["add", "-A"]
                title = "已暂存所选文件"
                disk = false
            case .unstage:
                if let head = current.head {
                    args = ["restore", "--staged", "--source=" + head]
                } else {
                    args = ["rm", "--cached", "--force", "--ignore-unmatch"]
                }
                title = "已取消暂存，工作版本保留"
                disk = false
            case .discardUnstaged:
                guard
                    !selections.contains(where: { selection in
                        current.entries.first(where: { $0.path == selection.path })?.untracked == true
                    })
                else { throw GitFailure("未跟踪文件不能以丢弃更改名义删除") }
                let tree = try await owner.command(["write-tree"], environment: environment, write: true).text
                guard GitOutputParser.object(tree) else { throw GitFailure("暂存区比较基线无效") }
                args = ["restore", "--worktree", "--source=" + tree]
                title = "已将未暂存内容恢复到暂存区版本"
                disk = true
            case .restoreHead:
                guard let head = current.head else { throw GitFailure("尚无 HEAD，不能恢复") }
                guard
                    !selections.contains(where: { selection in
                        current.entries.first(where: { $0.path == selection.path })?.untracked == true
                    })
                else { throw GitFailure("未跟踪文件不能以恢复 HEAD 名义删除") }
                args = ["restore", "--staged", "--worktree", "--source=" + head]
                title = "已恢复所选文件到 HEAD"
                disk = true
            }
            let result = try await owner.command(
                args + ["--pathspec-from-file=-", "--pathspec-file-nul"], input: owner.pathData(paths),
                environment: environment, write: true)
            _ = try await owner.requireSnapshot(snapshot)
            if action == .stage || action == .unstage {
                for selection in selections {
                    for (path, digest) in selection.diskDigests
                    where try GitFileAccess.diskDigest(path, repository: owner.identity) != digest {
                        throw GitFailure("准备索引期间工作版本发生变化，原暂存区保留，请重新审查")
                    }
                }
            }
            if action != .discardUnstaged {
                try reservation.prepare(GitFileAccess.smallFile(candidate, limit: 67_108_864))
                try reservation.install(description: "文件操作已完成准备")
            }
            return GitWriteResult(summary: title, commit: nil, workingTreeChanged: disk, detail: result.diagnostic)
        }
    }

    public func createBranch(name: String, start: String, switchTo: Bool, snapshot: GitStatusSnapshot) async throws
        -> GitWriteResult
    {
        try await lease(write: true) { owner in
            _ = try await owner.requireSnapshot(snapshot)
            try await owner.checkWritePolicy()
            try await owner.validateBranch(name)
            guard GitOutputParser.object(start) else { throw GitFailure("分支起点无效") }
            let args =
                switchTo ? ["switch", "--no-recurse-submodules", "-c", name, start] : ["branch", "--", name, start]
            _ = try await owner.command(args, write: true)
            return GitWriteResult(
                summary: switchTo ? "已创建并切换分支 \(name)" : "已创建分支 \(name)", commit: nil, workingTreeChanged: switchTo,
                detail: "")
        }
    }
    public func switchBranch(_ reference: GitReference, snapshot: GitStatusSnapshot) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            _ = try await owner.requireSnapshot(snapshot)
            try await owner.checkWritePolicy()
            guard !reference.tag, GitOutputParser.object(reference.object) else { throw GitFailure("请选择本地或远端分支") }
            let resolved = try await owner.command(["rev-parse", "--verify", "--end-of-options", reference.name]).text
            guard resolved == reference.object else { throw GitFailure("目标分支已更新，请刷新后重试") }
            let args =
                reference.remote
                ? ["switch", "--no-recurse-submodules", "--track", reference.shortName]
                : ["switch", "--no-recurse-submodules", "--no-guess", "--", reference.shortName]
            _ = try await owner.command(args, write: true)
            return GitWriteResult(
                summary: "已切换到 \(reference.shortName)", commit: nil, workingTreeChanged: true, detail: "")
        }
    }
    public func deleteBranch(_ reference: GitReference, snapshot: GitStatusSnapshot) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            _ = try await owner.requireSnapshot(snapshot)
            try await owner.checkWritePolicy()
            guard reference.name.hasPrefix("refs/heads/"), !reference.current else {
                throw GitFailure("只能安全删除未使用的本地分支")
            }
            let value = try await owner.command(["rev-parse", "--verify", "--end-of-options", reference.name]).text
            guard value == reference.object else { throw GitFailure("分支已更新，请刷新后再删除") }
            _ = try await owner.command(["branch", "-d", "--", reference.shortName], write: true)
            return GitWriteResult(
                summary: "已删除已合并分支 \(reference.shortName)", commit: nil, workingTreeChanged: false, detail: "")
        }
    }
    func validateBranch(_ name: String) async throws {
        guard !name.isEmpty, name.utf8.count <= 1024, !name.hasPrefix("-"), !name.contains("\0"), !name.contains("\n")
        else { throw GitFailure("分支名称无效") }
        _ = try await command(["check-ref-format", "--branch", name])
    }
    func pathBatches(_ paths: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var bytes = 0
        for path in paths {
            if bytes + path.utf8.count > 60_000, !current.isEmpty {
                result.append(current)
                current = []
                bytes = 0
            }
            current.append(path)
            bytes += path.utf8.count + 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    public func setIdentity(name: String, email: String) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 256,
                email.contains("@"), email.utf8.count <= 256,
                ![name, email].contains(where: {
                    $0.contains("\n") || $0.contains("\0") || $0.contains("<") || $0.contains(">")
                })
            else { throw GitFailure("请填写有效的提交姓名与邮箱") }
            _ = try await owner.command(["config", "--local", "user.name", name], write: true)
            _ = try await owner.command(["config", "--local", "user.email", email], write: true)
            return GitWriteResult(summary: "已设置当前仓库的提交身份", commit: nil, workingTreeChanged: false, detail: "未修改全局配置")
        }
    }
}
