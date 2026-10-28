import CHyCodeTerminal
import Darwin
import Dispatch
import Foundation

/// One PTY, one unreaped child, one input queue and at most one output delivery.
/// All descriptors, sources and continuations belong to `queue`. The consumer
/// awaits each output before requesting more, applying PTY backpressure without
/// dropping bytes or accumulating an unbounded stream of MainActor tasks.
public final class TerminalProcess: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hycode.terminal.pty", qos: .utility)
    private var fd: Int32 = -1
    private var pid: pid_t?
    private var reader: DispatchSourceRead?
    private var readerSuspended = true
    private var writer: DispatchSourceWrite?
    private var writerSuspended = true
    private var processSource: DispatchSourceProcess?
    private var input = Data()
    private var outputWaiter: CheckedContinuation<Data?, Never>?
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var exitCode: Int32?
    private var started = false
    private var stopped = false
    private var reaping = false
    private var outputFilter = TerminalOutputFilter()

    public init() {}

    public func start(configuration: TerminalConfiguration, helper: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard !started, !stopped else { throw TerminalFailure("终端会话已关闭") }
                    started = true
                    guard FileManager.default.isExecutableFile(atPath: helper.path),
                        FileManager.default.isExecutableFile(atPath: configuration.shell.path)
                    else { throw TerminalFailure("终端宿主或 Shell 不可执行，请检查应用包与 Shell 路径") }
                    let argv = ([helper.path, configuration.shell.path] + configuration.arguments).map { strdup($0) }
                    let env = configuration.environment.sorted { $0.key < $1.key }.map {
                        strdup($0.key + "=" + $0.value)
                    }
                    defer {
                        for pointer in argv { free(pointer) }
                        for pointer in env { free(pointer) }
                    }
                    guard argv.allSatisfy({ $0 != nil }), env.allSatisfy({ $0 != nil }) else {
                        throw TerminalFailure("无法分配终端参数")
                    }
                    var child: pid_t = 0
                    var master: Int32 = -1
                    let result = (argv + [nil]).withUnsafeBufferPointer { args in
                        (env + [nil]).withUnsafeBufferPointer { vars in
                            hycode_terminal_spawn(
                                helper.path, args.baseAddress, vars.baseAddress,
                                configuration.directory.path, 100, 28, &child, &master)
                        }
                    }
                    guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO) }
                    fd = master
                    pid = child
                    let ownedFD = master
                    let readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
                    readSource.setEventHandler { [self] in readAvailable() }
                    // Closing only here prevents fd reuse while a cancelled event is pending.
                    readSource.setCancelHandler { Darwin.close(ownedFD) }
                    reader = readSource
                    let writeSource = DispatchSource.makeWriteSource(fileDescriptor: master, queue: queue)
                    writeSource.setEventHandler { [self] in writeAvailable() }
                    writer = writeSource
                    let childSource = DispatchSource.makeProcessSource(
                        identifier: child, eventMask: .exit, queue: queue)
                    childSource.setEventHandler { [self] in childExited() }
                    processSource = childSource
                    childSource.resume()
                    continuation.resume()
                } catch {
                    stopped = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func nextOutput() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard fd >= 0, outputWaiter == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                outputWaiter = continuation
                if readerSuspended {
                    readerSuspended = false
                    reader?.resume()
                }
            }
        }
    }

    public func send(_ bytes: Data, onlyWhenShellForeground: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard fd >= 0, !stopped, pid != nil, input.count + bytes.count <= 262_144 else {
                    continuation.resume(throwing: TerminalFailure("终端已关闭或待发送输入超过 256 KiB"))
                    return
                }
                if onlyWhenShellForeground, tcgetpgrp(fd) != pid {
                    continuation.resume(throwing: TerminalFailure("Shell 当前未在编辑命令，请重新选择候选"))
                    return
                }
                input.append(bytes)
                if !input.isEmpty, writerSuspended {
                    writerSuspended = false
                    writer?.resume()
                }
                continuation.resume()
            }
        }
    }

    public func resize(columns: Int, rows: Int) {
        queue.async { [self] in
            guard fd >= 0 else { return }
            _ = hycode_terminal_resize(fd, Int32(min(500, max(2, columns))), Int32(min(300, max(2, rows))))
        }
    }

    public func outputWasLimited() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(
                    returning: outputFilter.oversizedSequences > 0 || outputFilter.unicodeReplacements > 0)
            }
        }
    }
    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let exitCode {
                    continuation.resume(returning: exitCode)
                } else if !started || (stopped && pid == nil) {
                    continuation.resume(returning: -1)
                } else {
                    exitWaiters.append(continuation)
                }
            }
        }
    }

    public func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if !stopped {
                    stopped = true
                    input.removeAll()
                    signal(SIGHUP)
                    queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [self] in signal(SIGTERM) }
                    queue.asyncAfter(deadline: .now() + .milliseconds(750)) { [self] in signal(SIGKILL) }
                    // A dying tty process can wait for the master to close.
                    // Descriptor cleanup must not depend on waitpid completing.
                    queue.asyncAfter(deadline: .now() + .milliseconds(1250)) { [self] in closeIO() }
                }
                continuation.resume()
            }
        }
        _ = await waitForExit()
    }

    private func signal(_ number: Int32) {
        if let pid { hycode_terminal_signal(pid, fd, number) }
    }
    private func readAvailable() {
        guard fd >= 0, let continuation = outputWaiter else { return }
        // UTF-8 repair can expand raw bytes 3x; with an 8 KiB pending OSC this
        // still keeps a delivered chunk within the 32 KiB UI budget.
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        if count > 0 {
            let filtered = outputFilter.append(Data(bytes.prefix(count)))
            guard !filtered.isEmpty else { return }
            outputWaiter = nil
            reader?.suspend()
            readerSuspended = true
            continuation.resume(returning: filtered)
        } else {
            outputWaiter = nil
            continuation.resume(returning: nil)
            closeIO()
        }
    }
    private func writeAvailable() {
        guard fd >= 0 else { return }
        let count = input.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        if count > 0 {
            input.removeFirst(count)
        } else if count < 0, errno != EAGAIN && errno != EINTR {
            input.removeAll()
        }
        if input.isEmpty, !writerSuspended {
            writer?.suspend()
            writerSuspended = true
        }
    }
    private func closeIO() {
        guard fd >= 0 else { return }
        if readerSuspended {
            reader?.resume()
            readerSuspended = false
        }
        if writerSuspended {
            writer?.resume()
            writerSuspended = false
        }
        writer?.cancel()
        writer = nil
        reader?.cancel()
        reader = nil
        fd = -1
        input.removeAll()
        outputWaiter?.resume(returning: nil)
        outputWaiter = nil
    }
    private func childExited() {
        guard !reaping, let child = pid else { return }
        reaping = true
        // Keep the leader unreaped while reclaiming the tty's owned process groups.
        signal(SIGHUP)
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { [self] in
            signal(SIGKILL)
            // Normally EIO ends the reader after its final bytes. Bound a tty
            // held open by deliberately detached jobs, even with no consumer.
            queue.asyncAfter(deadline: .now() + .seconds(1)) { [self] in closeIO() }
            reapExitedChild(child)
        }
    }
    private func reapExitedChild(_ child: pid_t) {
        guard pid == child else { return }
        var status: Int32 = 0
        let result = waitpid(child, &status, WNOHANG)
        if result == 0 || (result < 0 && errno == EINTR) {
            // EVFILT_PROC EXIT may arrive before a tty process is waitable.
            // Keep the I/O queue free to drain/cancel sources and close its PTY.
            queue.asyncAfter(deadline: .now() + .milliseconds(20)) { [self] in reapExitedChild(child) }
            return
        }
        let code = result < 0 ? -1 : status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        pid = nil
        exitCode = code
        stopped = true
        processSource?.cancel()
        processSource = nil
        for waiter in exitWaiters { waiter.resume(returning: code) }
        exitWaiters.removeAll()
    }
}
