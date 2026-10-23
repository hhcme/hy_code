import Darwin
import Foundation

/// Anchored regular-file reads, independent of the editable text size/encoding
/// policy. Never passes a file URL to a decoder (which could resolve it again).
enum PreviewFileIO {
    static let maximumBytes = 64 * 1024 * 1024
    private final class Descriptor {
        let value: Int32
        init(_ value: Int32) throws {
            guard value >= 0 else { throw failure("无法读取图片：" + String(cString: strerror(errno))) }
            self.value = value
        }
        deinit { Darwin.close(value) }
    }
    private static func failure(_ message: String) -> WorkspaceFailure {
        WorkspaceFailure(code: "image_read", message: message)
    }
    static func read(root: URL, path: String) throws -> Data {
        try Task.checkCancellation()
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard root.isFileURL, !root.path.contains("\0"), !parts.isEmpty,
            parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") })
        else {
            throw failure("图片路径必须位于已打开的目录内")
        }
        var directory = try Descriptor(Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        for part in parts.dropLast() {
            try Task.checkCancellation()
            directory = try Descriptor(openat(directory.value, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }
        let file = try Descriptor(openat(directory.value, parts.last!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        var before = stat()
        guard fstat(file.value, &before) == 0, before.st_mode & S_IFMT == S_IFREG else {
            throw failure("此条目不是普通图片文件")
        }
        guard before.st_size >= 0, before.st_size <= maximumBytes else { throw failure("图片文件超过 64 MiB 预览上限") }
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(file.value, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("读取图片失败")
            }
            if count == 0 { break }
            guard result.count + count <= maximumBytes else { throw failure("图片文件超过 64 MiB 预览上限") }
            result.append(contentsOf: chunk.prefix(count))
        }
        var after = stat()
        guard fstat(file.value, &after) == 0, TextFileIO.Version(before) == TextFileIO.Version(after) else {
            throw failure("读取期间图片已变化，请重新载入")
        }
        return result
    }
}
