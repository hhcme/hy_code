import Darwin
import Foundation

/// Immutable descriptor owner. pread is independent of file offsets and safe
/// across readers; descriptor closes only when the final in-flight owner exits.
final class VideoPreviewFile: @unchecked Sendable {
    let size: Int64
    private let descriptor: Int32
    private let lease: (any Sendable)?
    private let version: TextFileIO.Version
    static let maximumChunk = 256 * 1024
    static let maximumBytes: Int64 = 64 * 1024 * 1024 * 1024
    static func failure(_ message: String) -> WorkspaceFailure {
        WorkspaceFailure(code: "video_preview", message: message)
    }
    init(root: URL, path: String, keepingAlive lease: (any Sendable)? = nil) throws {
        self.lease = lease
        try Task.checkCancellation()
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard root.isFileURL, !root.path.contains("\0"), !parts.isEmpty,
            parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") })
        else { throw Self.failure("视频路径必须位于已打开的目录内") }
        var directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw Self.failure("无法访问视频所在目录") }
        defer { Darwin.close(directory) }
        for part in parts.dropLast() {
            try Task.checkCancellation()
            let next = openat(directory, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Self.failure("无法访问目录或路径包含符号链接") }
            Darwin.close(directory)
            directory = next
        }
        let file = openat(directory, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw Self.failure("无法打开视频或目标为符号链接") }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_size > 0, info.st_size <= Self.maximumBytes
        else {
            Darwin.close(file)
            throw Self.failure("视频需要是非空普通文件，且不超过 64 GiB")
        }
        descriptor = file
        size = info.st_size
        version = TextFileIO.Version(info)
    }
    deinit { Darwin.close(descriptor) }
    func read(offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, offset <= size, count >= 0, count <= Self.maximumChunk else {
            throw Self.failure("视频读取范围无效")
        }
        try validate()
        let length = min(count, Int(size - offset))
        var bytes = [UInt8](repeating: 0, count: length)
        var done = 0
        while done < length {
            let amount = bytes.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress!.advanced(by: done), length - done, offset + Int64(done))
            }
            if amount < 0, errno == EINTR { continue }
            guard amount > 0 else { throw Self.failure("视频读取失败或文件已变化") }
            done += amount
        }
        try validate()
        return Data(bytes)
    }
    private func validate() throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, version == TextFileIO.Version(info) else {
            throw Self.failure("视频文件已发生变化，请重新载入")
        }
    }
}
