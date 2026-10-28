import Darwin
import Foundation

extension GitRepository {
    /// Local receive/upload-pack runs under our process restrictions as well.
    /// Do not let restricted hook executability silently bypass a server policy.
    /// Only a plain bare repository with a known non-executable config is supported.
    func validateLocalRemote(_ directory: URL?) async throws {
        guard let directory else { return }
        for name in ["commondir", "gitdir", "config.worktree", ".git"] {
            do {
                _ = try GitFileAccess.info(directory.appendingPathComponent(name))
                throw GitFailure("本地远端采用了额外管理布局；当前仅支持普通 bare 仓库，请使用专用 Git 工具")
            } catch let error as POSIXError where error.code == .ENOENT {
                continue
            }
        }
        for name in ["objects", "refs"] {
            let item = directory.appendingPathComponent(name)
            let info = try GitFileAccess.info(item)
            guard info.st_mode & S_IFMT == S_IFDIR,
                GitFileAccess.contains(directory, try GitFileAccess.canonical(item))
            else { throw GitFailure("本地远端不是受支持的普通 bare 仓库") }
        }
        let objectInfo = directory.appendingPathComponent("objects/info")
        do {
            guard try GitFileAccess.info(objectInfo).st_mode & S_IFMT == S_IFDIR else {
                throw GitFailure("本地远端对象元数据目录不安全")
            }
        } catch let error as POSIXError where error.code == .ENOENT {}
        _ = try GitFileAccess.smallFile(directory.appendingPathComponent("HEAD"), limit: 4096)
        let remote = GitRepositoryIdentity(
            root: directory, directory: directory, commonDirectory: directory, authorizedRoot: directory,
            additionalAuthorizedDirectories: [])
        try GitFileAccess.validateMetadata(remote)
        let config = try await GitProcess.run(
            executable: executable, repository: remote, home: home,
            arguments: ["config", "--local", "--no-includes", "--null", "--list"], limit: 1_048_576)
        guard config.status == 0 else { throw GitFailure("本地远端配置无效或不受支持，未执行传输；请使用专用 Git 工具检查") }
        let allowed: Set<String> = [
            "core.repositoryformatversion", "core.filemode", "core.bare", "core.logallrefupdates",
            "core.ignorecase", "core.precomposeunicode", "extensions.objectformat",
            "receive.denynonfastforwards", "receive.denydeletes",
        ]
        var bare = false
        for record in try GitOutputParser.fields(config.stdout) where !record.isEmpty {
            let parts = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0]).lowercased()
            guard allowed.contains(key) else {
                throw GitFailure("本地远端包含当前不支持的自定义配置；不会绕过 hooks 或执行服务器助手，请使用专用 Git 工具")
            }
            if key == "core.bare" {
                bare = parts.count == 2 && ["true", "yes", "on", "1"].contains(parts[1].lowercased())
            }
        }
        guard bare else { throw GitFailure("本地远端当前仅支持普通 bare 仓库，不能向工作树目录直接推送") }
        let hooks = directory.appendingPathComponent("hooks")
        let hookInfo: stat
        do {
            hookInfo = try GitFileAccess.info(hooks)
        } catch let error as POSIXError where error.code == .ENOENT {
            return
        }
        guard hookInfo.st_mode & S_IFMT == S_IFDIR,
            GitFileAccess.contains(directory, try GitFileAccess.canonical(hooks))
        else { throw GitFailure("本地远端 hooks 路径不安全，未执行操作") }
        let names = try FileManager.default.contentsOfDirectory(atPath: hooks.path)
        guard names.count <= 128 else { throw GitFailure("本地远端 hooks 超过检查预算") }
        for name in names where !name.hasSuffix(".sample") {
            let path = hooks.appendingPathComponent(name)
            let hook = try GitFileAccess.info(path)
            guard hook.st_mode & S_IFMT == S_IFREG, hook.st_mode & 0o111 == 0,
                !FileManager.default.isExecutableFile(atPath: path.path)
            else {
                throw GitFailure("本地远端存在可执行 hooks 或不安全项目；当前不会执行或跳过接收策略，请使用专用 Git 工具")
            }
        }
    }
}
