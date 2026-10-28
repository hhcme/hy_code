import Foundation

extension GitRepository {
    public func remotes() async throws -> [GitRemote] { try await lease { try await $0.readRemotes() } }
    func readRemotes() async throws -> [GitRemote] {
        let config = try await localConfiguration()
        let names = Set(
            config.keys.compactMap { key -> String? in
                guard key.hasPrefix("remote."), key.hasSuffix(".url") else { return nil }
                return String(key.dropFirst(7).dropLast(4))
            })
        return try names.sorted().map { name in
            guard !name.isEmpty, !name.hasPrefix("-"),
                name.allSatisfy({ $0.isLetter || $0.isNumber || "-_".contains($0) })
            else { throw GitFailure("当前受限模式不支持此远端名称") }
            let fetch = config["remote.\(name).url"] ?? []
            let push = config["remote.\(name).pushurl"] ?? fetch
            guard fetch.count == 1, push.count == 1 else { throw GitFailure("一个远端配置了多个 URL；当前只支持明确的单一获取/推送目标") }
            _ = try Self.remoteLocation(fetch[0])
            _ = try Self.remoteLocation(push[0])
            return GitRemote(name: name, fetchURL: fetch[0], pushURL: push[0])
        }
    }
    static func remoteLocation(_ value: String) throws -> URL? {
        guard !value.isEmpty, value.utf8.count <= 4096, !value.hasPrefix("-"),
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespaces.contains($0)
            })
        else { throw GitFailure("远端地址无效；不接受命令、空白或内嵌凭据") }
        if value.hasPrefix("/") { return try GitFileAccess.canonical(URL(fileURLWithPath: value)) }
        if value.hasPrefix("file://"), let url = URL(string: value), url.isFileURL,
            url.host == nil || url.host == "" || url.host == "localhost"
        {
            return try GitFileAccess.canonical(url)
        }
        if let url = URLComponents(string: value), ["https", "ssh"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host, !host.isEmpty, url.password == nil, url.query == nil, url.fragment == nil,
            url.scheme == "ssh" || url.user == nil
        {
            return nil
        }
        if !value.contains("://"), let colon = value.firstIndex(of: ":") {
            let host = String(value[..<colon])
            let path = String(value[value.index(after: colon)...])
            if !host.isEmpty, !path.isEmpty, !host.hasPrefix("-"), !host.contains("/"),
                host.allSatisfy({ $0.isLetter || $0.isNumber || ".-_@".contains($0) })
            {
                return nil
            }
        }
        throw GitFailure("仅支持明确的 HTTPS、SSH 或本地仓库地址；不使用密码 URL 或自定义协议助手")
    }
    public func setRemote(name: String, url: String, replacing: Bool) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            guard !name.isEmpty, name.utf8.count <= 128,
                name.allSatisfy({ $0.isLetter || $0.isNumber || "-_".contains($0) }), !name.hasPrefix("-")
            else { throw GitFailure("远端名称只能包含字母、数字、短横线和下划线") }
            _ = try Self.remoteLocation(url)
            _ = try await owner.command(["remote", replacing ? "set-url" : "add", "--", name, url], write: true)
            return GitWriteResult(summary: "已保存当前仓库远端 \(name)", commit: nil, workingTreeChanged: false, detail: "")
        }
    }
    public func removeRemote(_ name: String) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            guard try await owner.readRemotes().contains(where: { $0.name == name }) else {
                throw GitFailure("远端已改变，请刷新")
            }
            _ = try await owner.command(["remote", "remove", "--", name], write: true)
            return GitWriteResult(summary: "已删除远端 \(name)", commit: nil, workingTreeChanged: false, detail: "本地工作版本保留")
        }
    }
    public func fetch(remote: GitRemote) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            try await owner.checkWritePolicy(network: true)
            guard try await owner.readRemotes().contains(remote) else { throw GitFailure("远端配置已改变，请重新查看目标") }
            let directory = try Self.remoteLocation(remote.fetchURL)
            try await owner.validateLocalRemote(directory)
            let result = try await owner.command(
                [
                    "fetch", "--no-tags", "--no-recurse-submodules", "--no-write-fetch-head",
                    "--upload-pack=git-upload-pack", "--", remote.fetchURL,
                    "+refs/heads/*:refs/remotes/\(remote.name)/*",
                ], write: true, network: true,
                ssh: directory == nil && !remote.fetchURL.lowercased().hasPrefix("https://"),
                timeout: .seconds(90), remoteDirectory: directory)
            return GitWriteResult(
                summary: "已获取 \(remote.name) 的分支引用", commit: nil, workingTreeChanged: false, detail: result.diagnostic)
        }
    }
    public func pullFastForward(remote: GitRemote, snapshot: GitStatusSnapshot) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            let current = try await owner.requireSnapshot(snapshot)
            guard let branch = current.branch, let upstream = current.upstream,
                upstream.hasPrefix(remote.name + "/"), current.entries.isEmpty
            else { throw GitFailure("仅快进拉取需要干净工作树和属于所选远端的上游分支，请先处理本地更改或设置上游") }
            try await owner.checkWritePolicy(content: true, network: true)
            guard try await owner.readRemotes().contains(remote) else { throw GitFailure("远端配置已改变") }
            let target = String(upstream.dropFirst(remote.name.count + 1))
            try await owner.validateBranch(target)
            let directory = try Self.remoteLocation(remote.fetchURL)
            try await owner.validateLocalRemote(directory)
            _ = try await owner.command(
                [
                    "fetch", "--no-tags", "--no-recurse-submodules", "--upload-pack=git-upload-pack", "--",
                    remote.fetchURL,
                    "refs/heads/\(target):refs/remotes/\(remote.name)/\(target)",
                ], write: true, network: true,
                ssh: directory == nil && !remote.fetchURL.lowercased().hasPrefix("https://"),
                timeout: .seconds(90), remoteDirectory: directory)
            let updated = try await owner.readStatus()
            guard updated.branch == branch, updated.head == current.head, updated.indexDigest == current.indexDigest,
                updated.entries.isEmpty
            else { throw GitFailure("获取后本地状态变化，尚未快进，请刷新") }
            let result = try await owner.command(
                ["merge", "--ff-only", "--no-edit", "--no-autostash", "refs/remotes/\(remote.name)/\(target)"],
                write: true)
            return GitWriteResult(
                summary: "已仅快进更新 \(branch)", commit: nil, workingTreeChanged: true, detail: result.text)
        }
    }
    public func pushPlan(remote: GitRemote, target: String, snapshot: GitStatusSnapshot) async throws -> GitPushPlan {
        try await lease { owner in
            let current = try await owner.requireSnapshot(snapshot)
            guard let head = current.head, let branch = current.branch else { throw GitFailure("请先创建本地分支和提交") }
            try await owner.validateBranch(target)
            guard try await owner.readRemotes().contains(remote) else { throw GitFailure("远端配置已改变") }
            let known = try await owner.command(
                ["rev-parse", "--verify", "--end-of-options", "refs/remotes/\(remote.name)/\(target)^{commit}"],
                allowed: [0, 128])
            let range = known.status == 0 ? known.text + ".." + head : head
            let result = try await owner.command([
                "log", "--max-count=201", "-z", "--format=" + Self.logFormat, "--no-show-signature", range, "--",
            ])
            return GitPushPlan(
                head: head, localBranch: branch, remote: remote.name, targetBranch: target,
                setUpstream: current.upstream == nil,
                previousRemoteObject: known.status == 0 ? known.text : nil,
                commits: Array(try GitOutputParser.commits(result.stdout).prefix(200)))
        }
    }
    public func push(_ plan: GitPushPlan, remote: GitRemote) async throws -> GitWriteResult {
        try await lease(write: true) { owner in
            let current = try await owner.readStatus()
            guard current.head == plan.head, current.branch == plan.localBranch, plan.remote == remote.name,
                try await owner.readRemotes().contains(remote)
            else { throw GitFailure("推送预览后分支或远端发生变化，请重新确认") }
            try await owner.validateBranch(plan.targetBranch)
            try await owner.checkWritePolicy(network: true)
            let directory = try Self.remoteLocation(remote.pushURL)
            try await owner.validateLocalRemote(directory)
            let result = try await owner.command(
                [
                    "push", "--porcelain", "--no-follow-tags", "--recurse-submodules=no",
                    "--receive-pack=git-receive-pack", "--", remote.pushURL,
                    "\(plan.head):refs/heads/\(plan.targetBranch)",
                ], write: true, network: true,
                ssh: directory == nil && !remote.pushURL.lowercased().hasPrefix("https://"),
                timeout: .seconds(90), remoteDirectory: directory)
            var detail = result.text + "\n" + result.diagnostic
            // The approved URL and object ID are fixed. Local tracking is a
            // separate best-effort step after the remote accepted the push.
            do {
                if remote.fetchURL == remote.pushURL {
                    _ = try await owner.command(
                        [
                            "update-ref", "--no-deref", "refs/remotes/\(remote.name)/\(plan.targetBranch)", plan.head,
                            plan.previousRemoteObject ?? String(repeating: "0", count: plan.head.count),
                        ], write: true)
                }
            } catch {
                detail += "\n远端推送已成功，本地远端引用未更新：\(error.localizedDescription)"
            }
            do {
                guard plan.setUpstream else {
                    return GitWriteResult(
                        summary: "已推送到 \(remote.name)/\(plan.targetBranch)", commit: plan.head,
                        workingTreeChanged: false, detail: detail)
                }
                let tracking = try await owner.localConfiguration()
                let branchHead = try await owner.command([
                    "rev-parse", "--verify", "--end-of-options", "refs/heads/" + plan.localBranch,
                ]).text
                if branchHead == plan.head, tracking["branch.\(plan.localBranch).remote"] == nil,
                    tracking["branch.\(plan.localBranch).merge"] == nil
                {
                    _ = try await owner.command(
                        ["config", "--local", "branch.\(plan.localBranch).remote", remote.name], write: true)
                    _ = try await owner.command(
                        ["config", "--local", "branch.\(plan.localBranch).merge", "refs/heads/" + plan.targetBranch],
                        write: true)
                } else {
                    detail += "\n推送后本地分支/上游已变化，保留原上游设置"
                }
            } catch {
                detail += "\n远端推送已成功，本地上游配置未完成：\(error.localizedDescription)"
            }
            return GitWriteResult(
                summary: "已推送到 \(remote.name)/\(plan.targetBranch)", commit: plan.head, workingTreeChanged: false,
                detail: detail)
        }
    }
}
