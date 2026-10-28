import Darwin
import Foundation

public enum GitToolchain {
    /// Use the installed binary directly, never the /usr/bin/git installation
    /// shim, xcrun, a shell, a project executable or a PATH lookup.
    public static func installedExecutable() throws -> URL {
        for path in [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/opt/homebrew/bin/git",
        ] where FileManager.default.isExecutableFile(atPath: path) {
            return try GitFileAccess.canonical(URL(fileURLWithPath: path))
        }
        throw GitFailure("未找到已安装的 Git。请自行安装命令行工具后重试；HyCode 不自动启动安装程序")
    }
}

struct GitProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: Data
    var text: String { String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .newlines) }
    var diagnostic: String { GitDiagnostic.redact(String(decoding: stderr, as: UTF8.self)) }
}

enum GitDiagnostic {
    static func redact(_ text: String) -> String {
        String(text.prefix(8192))
            .replacingOccurrences(of: #"(?i)(https?://)[^\s/@]+@"#, with: "$1[redacted]@", options: .regularExpression)
            .components(separatedBy: .newlines).filter {
                let line = $0.lowercased()
                return !line.contains("authorization:") && !line.contains("password=") && !line.contains("token=")
            }.joined(separator: "\n")
    }
}

/// Each invocation owns its process group, readers, timeout and input file.
/// Cancellation does not return before wait/reap and bounded pipe drainage.
enum GitProcess {
    static let configuration = [
        "core.fsmonitor=false", "core.untrackedCache=false", "core.hooksPath=/dev/null",
        "core.pager=cat", "core.editor=false", "core.attributesFile=/dev/null", "core.excludesFile=/dev/null",
        "credential.helper=", "credential.interactive=false", "color.ui=false", "log.showSignature=false",
        "diff.external=", "diff.trustExitCode=false", "submodule.recurse=false",
        "fetch.recurseSubmodules=false", "fetch.writeCommitGraph=false", "fetch.parallel=1",
        "maintenance.auto=false", "gc.auto=0", "pack.threads=1", "index.threads=1",
        "protocol.allow=never", "protocol.file.allow=always", "protocol.https.allow=always",
        "protocol.ssh.allow=always",
        "protocol.ext.allow=never", "protocol.http.allow=never", "protocol.git.allow=never",
        "protocol.ftp.allow=never", "protocol.ftps.allow=never",
        "http.sslVerify=true", "http.followRedirects=false", "transfer.fsckObjects=true",
    ]
    static func run(
        executable: URL, repository: GitRepositoryIdentity?, home: URL, arguments: [String],
        input: Data? = nil, environment extra: [String: String] = [:], write: Bool = false,
        network: Bool = false, ssh: Bool = false, remoteDirectory: URL? = nil, limit: Int = 8_388_608,
        timeout: Duration = .seconds(20)
    ) async throws -> GitProcessResult {
        try Task.checkCancellation()
        if let repository { try GitFileAccess.validateMetadata(repository) }
        let directory = repository?.root ?? home
        let args =
            ["--no-pager", "--no-optional-locks", "--literal-pathspecs", "--no-lazy-fetch", "--no-replace-objects"]
            + configuration.flatMap { ["-c", $0] }
            + (repository.map { ["--git-dir=\($0.directory.path)", "--work-tree=\($0.root.path)"] } ?? [])
            + arguments
        var environment = [
            "HOME": home.path, "XDG_CONFIG_HOME": home.path, "TMPDIR": home.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
            "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false", "SSH_ASKPASS_REQUIRE": "never",
            "GCM_INTERACTIVE": "Never", "GIT_PAGER": "cat", "GIT_EDITOR": "false", "GIT_SEQUENCE_EDITOR": "false",
            "GIT_ATTR_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0", "GIT_NO_LAZY_FETCH": "1",
            "GIT_SSH_VARIANT": "ssh",
            "GIT_SSH_COMMAND":
                "/usr/bin/ssh -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o IdentityFile=none -o AddKeysToAgent=no -o UseKeychain=no",
        ]
        if ssh {
            let hosts = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts").path
            let quoted = "'" + hosts.replacingOccurrences(of: "'", with: "'\\''") + "'"
            environment["GIT_SSH_COMMAND", default: ""] += " -o UserKnownHostsFile=" + quoted
        }
        if ssh, let socket = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"], socket.hasPrefix("/") {
            environment["SSH_AUTH_SOCK"] = socket
        }
        environment.merge(extra) { _, value in value }
        var inputURL: URL?
        var inputHandle: FileHandle?
        if let input {
            let url = home.appendingPathComponent("input-" + UUID().uuidString)
            try input.write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            inputURL = url
            inputHandle = try FileHandle(forReadingFrom: url)
        }
        defer {
            try? inputHandle?.close()
            if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
        }
        let profile = try sandbox(
            executable: executable, repository: repository, home: home, write: write, network: network, ssh: ssh,
            remoteDirectory: remoteDirectory)
        let child = try OwnedToolProcess.launch(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", profile, executable.path] + args, directory: directory, input: inputHandle,
            environment: environment, inheritEnvironment: false)
        let state = GitProcessState(child: child)
        let timer = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: timeout)
                state.stop(.timeout)
            } catch {}
        }
        defer { timer.cancel() }
        async let stdout = capture(child.stdout, limit: limit, state: state)
        async let stderr = capture(child.stderr, limit: 262_144, state: state)
        let status = await withTaskCancellationHandler {
            await ToolBlockingIO.wait(child)
        } onCancel: {
            state.stop(.cancelled)
        }
        let buffers = await (stdout, stderr)
        if let reason = state.reason {
            switch reason {
            case .cancelled: throw CancellationError()
            case .timeout: throw GitFailure("Git 操作超时；写操作可能已部分完成，请刷新核对实际状态")
            case .limit: throw GitFailure("Git 输出超过资源预算；未将截断结果作为完整状态或差异", code: .resourceBudget)
            }
        }
        try Task.checkCancellation()
        return GitProcessResult(status: status, stdout: buffers.0, stderr: buffers.1)
    }
    private static func capture(_ handle: FileHandle, limit: Int, state: GitProcessState) async -> Data {
        defer { try? handle.close() }
        var bytes = Data()
        while true {
            let chunk = await ToolBlockingIO.read(handle, capacity: 65_536)
            if chunk.isEmpty { break }
            let remaining = max(0, limit - bytes.count)
            bytes.append(chunk.prefix(remaining))
            if chunk.count > remaining { state.stop(.limit) }
        }
        return bytes
    }

    static func sandbox(
        executable: URL, repository: GitRepositoryIdentity?, home: URL, write: Bool, network: Bool, ssh: Bool = false,
        remoteDirectory: URL? = nil
    ) throws -> String {
        let core = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
            "libexec/git-core")
        let runtime = executable.deletingLastPathComponent().deletingLastPathComponent()
        func quote(_ value: String) throws -> String { try CodexWireLiteral.string(value) }
        let roots =
            [runtime, repository?.authorizedRoot ?? home, home] + (repository?.additionalAuthorizedDirectories ?? [])
            + (remoteDirectory.map { [$0] } ?? [])
        let physicalRoots = try roots.map { try CodexSandbox.canonicalPath($0) }
        let reads =
            [
                "/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db/dyld", "/Library/Apple/System",
                "/Library/Preferences", "/dev", "/private/var/run",
            ] + physicalRoots
        let writes = [physicalRoots[2]] + (write ? [physicalRoots[1]] + Array(physicalRoots.dropFirst(3)) : [])
        var ancestors = Set<String>()
        for root in physicalRoots {
            var parent = (root as NSString).deletingLastPathComponent
            while parent != "/" {
                ancestors.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        var literals = ancestors
        if ssh {
            let hosts = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts")
            if let physical = try? GitFileAccess.canonical(hosts) { literals.insert(physical.path) }
        }
        let readRules = try
            (reads.map { "(subpath " + (try quote($0)) + ")" }
            + literals.sorted().map { "(literal " + (try quote($0)) + ")" }).joined(separator: " ")
        let writeRules = try writes.map { "(subpath " + (try quote($0)) + ")" }.joined(separator: " ")
        var protections: [String] = []
        for protected in [
            CodexCredentials.defaultDirectory,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains"),
            URL(fileURLWithPath: "/Library/Keychains"),
        ] {
            if let path = try? GitFileAccess.canonical(protected) {
                protections.append("(deny file-read* file-write* (subpath " + (try quote(path.path)) + "))")
            }
        }
        let base = """
            (version 1)
            (allow default)
            (deny file-read-data (require-not (require-any (literal "/") \(readRules))))
            (deny file-write* (require-not (require-any \(writeRules) (literal "/dev/null"))))
            \(protections.joined(separator: "\n"))
            """
        let executables =
            [executable.path, core.appendingPathComponent("git").path]
            + (network
                ? [core.appendingPathComponent("git-remote-https").path, "/usr/bin/ssh", "/bin/sh", "/bin/bash"] : [])
        // Git upload/receive-pack for explicit local remotes are the same Git
        // binary in Apple's layout; allow their fixed git-core entry points.
        let helpers =
            network ? ["git-upload-pack", "git-receive-pack"].map { core.appendingPathComponent($0).path } : []
        let allowed = try
            ((executables + helpers).map { "(literal " + (try quote($0)) + ")" }
            + (network ? ["(subpath " + (try quote(core.path)) + ")"] : [])).joined(separator: " ")
        let denyNetwork = network ? "" : "(deny network*)"
        return base + "\n(deny process-exec (require-not (require-any \(allowed))))\n" + denyNetwork
    }
}

private final class GitProcessState: @unchecked Sendable {
    enum Reason { case cancelled, timeout, limit }
    private let child: OwnedToolProcess
    private let lock = NSLock()
    private var stopped: Reason?
    init(child: OwnedToolProcess) { self.child = child }
    var reason: Reason? {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
    func stop(_ reason: Reason) {
        lock.lock()
        guard stopped == nil else {
            lock.unlock()
            return
        }
        stopped = reason
        lock.unlock()
        child.signal(SIGTERM)
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            self.child.signal(SIGKILL)
        }
    }
}
