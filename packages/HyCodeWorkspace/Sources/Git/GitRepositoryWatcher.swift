import CoreServices
import Foundation

/// Git needs .git and untracked file events too; the language source watcher
/// deliberately excludes these, so it cannot own repository invalidation.
public final class GitRepositoryWatcher: @unchecked Sendable {
    private final class Sink: @unchecked Sendable {
        let root: String
        let receive: @Sendable ([String], Bool) -> Void
        init(root: String, receive: @escaping @Sendable ([String], Bool) -> Void) {
            self.root = root
            self.receive = receive
        }
    }
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "HyCode.GitEvents", qos: .utility)
    public init(root: URL, receive: @escaping @Sendable ([String], Bool) -> Void) throws {
        let sink = Sink(root: try CodexSandbox.canonicalPath(root), receive: receive)
        let owner = Unmanaged.passRetained(sink)
        var context = FSEventStreamContext(
            version: 0, info: owner.toOpaque(), retain: nil,
            release: { if let value = $0 { Unmanaged<Sink>.fromOpaque(value).release() } }, copyDescription: nil)
        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, info, count, paths, flags, _ in
                    guard let info else { return }
                    let sink = Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue()
                    let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                    var values = Set<String>()
                    var rescan = count > 256
                    for index in 0..<min(256, count) {
                        if flags[index]
                            & UInt32(
                                kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                                    | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0
                        {
                            rescan = true
                        }
                        let path = String(cString: paths[index])
                        if path.hasPrefix(sink.root + "/") {
                            values.insert(String(path.dropFirst(sink.root.count + 1)))
                        }
                    }
                    if !values.isEmpty || rescan { sink.receive(values.sorted(), rescan) }
                }, &context, [sink.root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        else {
            owner.release()
            throw GitFailure("无法监听 Git 仓库变化，可手动刷新")
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            stop()
            throw GitFailure("Git 仓库监听未启动，请手动刷新")
        }
    }
    public func stop() {
        lock.lock()
        let current = stream
        stream = nil
        lock.unlock()
        if let current {
            FSEventStreamStop(current)
            FSEventStreamInvalidate(current)
            FSEventStreamRelease(current)
        }
    }
    deinit { stop() }
}
