import Darwin
import Foundation

/// A child in a new process group, created atomically before exec. The only
/// mutable state is protected by lock. Keep the exited leader waitable until
/// its group has been reclaimed, so delayed cancellation cannot signal a reused
/// PID. Descendants that explicitly leave the group are outside this contract.
final class OwnedToolProcess: @unchecked Sendable {
    let pid: pid_t
    let stdout: FileHandle
    let stderr: FileHandle
    private let lock = NSLock()
    private var reaped = false

    private init(pid: pid_t, stdout: FileHandle, stderr: FileHandle) {
        self.pid = pid
        self.stdout = stdout
        self.stderr = stderr
    }

    static func launch(
        executable: URL, arguments: [String], directory: URL, input: FileHandle? = nil,
        environment additions: [String: String] = [:], removingEnvironment: Set<String> = []
    ) throws -> OwnedToolProcess {
        let out = Pipe()
        let err = Pipe()
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        func check(_ code: Int32) throws {
            if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var defaults = sigset_t()
        var mask = sigset_t()
        sigemptyset(&defaults)
        sigemptyset(&mask)
        for signal in [SIGINT, SIGTERM, SIGHUP, SIGPIPE] { sigaddset(&defaults, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        try check(
            posix_spawnattr_setflags(
                &attributes,
                Int16(
                    POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
                )))
        if let input {
            try check(posix_spawn_file_actions_adddup2(&actions, input.fileDescriptor, STDIN_FILENO))
        } else {
            try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        }
        try check(posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, STDERR_FILENO))
        if #available(macOS 26, *) {
            try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
        } else {
            try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        }
        var environment = ProcessInfo.processInfo.environment
        environment.merge(additions) { _, new in new }
        for key in removingEnvironment { environment[key] = nil }
        environment["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        environment["DART_SUPPRESS_ANALYTICS"] = "true"
        let argv = (["/usr/bin/nice", "-n", "10", executable.path] + arguments).map { strdup($0) }
        let envp = environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) }
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        guard argv.allSatisfy({ $0 != nil }), envp.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        var pid: pid_t = 0
        let result = (argv + [nil]).withUnsafeBufferPointer { args in
            (envp + [nil]).withUnsafeBufferPointer { env in
                posix_spawn(&pid, "/usr/bin/nice", &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        try check(result)
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        return OwnedToolProcess(pid: pid, stdout: out.fileHandleForReading, stderr: err.fileHandleForReading)
    }

    func signal(_ value: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if !reaped { _ = kill(-pid, value) }
    }

    /// Blocking, called once on a utility worker. No GUI/application host.
    func wait() -> Int32 {
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0 {
            if errno != EINTR { return -1 }
        }
        lock.lock()
        defer { lock.unlock() }
        // The leader has exited. Any remaining group members are abandoned
        // workers and must not retain output pipes or continue writing files.
        _ = kill(-pid, SIGKILL)
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, 0) } while result < 0 && errno == EINTR
        reaped = true
        guard result == pid else { return -1 }
        return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
    }
}
