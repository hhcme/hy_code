import CoreServices
import Foundation

public struct WorkspaceFileEvents: Sendable {
    public let paths: [String]
    public let rescan: Bool
}

/// One recursive FSEvents stream on a utility dispatch queue. No UI, per-file
/// descriptor fan-out, timer scan, project code or main run loop is used.
public final class WorkspaceSourceWatcher: @unchecked Sendable {
    private final class Sink: @unchecked Sendable {
        let root: String
        let receive: @Sendable (WorkspaceFileEvents) -> Void
        init(root: String, receive: @escaping @Sendable (WorkspaceFileEvents) -> Void) {
            self.root = root
            self.receive = receive
        }
    }
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "HyCode.ProjectFiles", qos: .utility)
    public init(root: URL, receive: @escaping @Sendable (WorkspaceFileEvents) -> Void) throws {
        let sink = Sink(root: ProjectSourceCatalog.canonicalPath(root.path) ?? root.path, receive: receive)
        let owned = Unmanaged.passRetained(sink)
        var context = FSEventStreamContext(
            version: 0, info: owned.toOpaque(), retain: nil,
            release: { value in if let value { Unmanaged<Sink>.fromOpaque(value).release() } }, copyDescription: nil)
        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, context, count, paths, flags, _ in
                    guard let context else { return }
                    let sink = Unmanaged<Sink>.fromOpaque(context).takeUnretainedValue()
                    let values = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
                    var changed = Set<String>()
                    var rescan = count > 256
                    let dropped = UInt32(
                        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
                    let structural = UInt32(
                        kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                            | kFSEventStreamEventFlagItemRenamed)
                    for index in 0..<min(count, 256) {
                        let flag = flags[index]
                        if flag & dropped != 0 { rescan = true }
                        let path = String(cString: values[index])
                        guard path.hasPrefix(sink.root + "/") else { continue }
                        let relative = String(path.dropFirst(sink.root.count + 1))
                        guard ProjectSourceCatalog.allows(relative) else { continue }
                        if flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
                            if flag & structural != 0 { rescan = true }
                        } else {
                            // Local schema dependencies may have any extension.
                            // Consumers filter observed schemas/source languages.
                            changed.insert(relative)
                        }
                    }
                    if !changed.isEmpty || rescan {
                        sink.receive(WorkspaceFileEvents(paths: changed.sorted(), rescan: rescan))
                    }
                }, &context, [sink.root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25,
                UInt32(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                        | kFSEventStreamCreateFlagWatchRoot))
        else {
            owned.release()
            throw LanguageServiceFailure("无法监听项目文件变更")
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            throw LanguageServiceFailure("项目文件监听启动失败")
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
