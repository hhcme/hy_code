import Darwin
import Foundation

/// macOS file access for the text prototype. Calls are blocking and belong on a
/// document worker, never the UI actor. Only regular, singly-linked files below
/// the chosen root are replaced; each path component is opened without symlinks.
enum TextFileIO {
    static let maximumBytes = 8 * 1024 * 1024
    struct Version: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        init(_ info: stat) {
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec
            changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }
    struct Snapshot: Sendable {
        let bytes: Data
        let version: Version
    }
    private final class Descriptor {
        let value: Int32
        init(_ value: Int32) throws {
            guard value >= 0 else { throw posixFailure() }
            self.value = value
        }
        deinit { Darwin.close(value) }
    }
    private struct Target {
        let parent: Descriptor
        let file: Descriptor
        let name: String
        let info: stat
    }
    private static func target(root: URL, path: String) throws -> Target {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw WorkspaceFailure(code: "invalid_path", message: "文件路径必须位于项目内")
        }
        var directory = try Descriptor(Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        for part in parts.dropLast() {
            directory = try Descriptor(openat(directory.value, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }
        let name = parts.last!
        let file = try Descriptor(openat(directory.value, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        var info = stat()
        guard fstat(file.value, &info) == 0 else { throw posixFailure() }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw WorkspaceFailure(code: "not_regular", message: "此条目不是普通文本文件")
        }
        guard info.st_nlink == 1 else {
            throw WorkspaceFailure(code: "hard_link", message: "暂不编辑具有多个硬链接的文件")
        }
        guard info.st_size <= maximumBytes else {
            throw WorkspaceFailure(code: "text_too_large", message: "当前文本编辑上限为 8 MiB")
        }
        return Target(parent: directory, file: file, name: name, info: info)
    }
    private static func read(_ file: Int32) throws -> Data {
        guard lseek(file, 0, SEEK_SET) >= 0 else { throw posixFailure() }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(file, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw posixFailure()
            }
            if count == 0 { return data }
            guard data.count + count <= maximumBytes else {
                throw WorkspaceFailure(code: "text_too_large", message: "当前文本编辑上限为 8 MiB")
            }
            data.append(contentsOf: chunk.prefix(count))
        }
    }
    static func read(root: URL, path: String) throws -> Snapshot {
        let target = try target(root: root, path: path)
        let data = try read(target.file.value)
        var after = stat()
        guard fstat(target.file.value, &after) == 0 else { throw posixFailure() }
        guard Version(target.info) == Version(after) else { throw conflict() }
        return Snapshot(bytes: data, version: Version(after))
    }
    static func save(
        root: URL, path: String, expected: Snapshot, bytes: Data, cancellation: DocumentSaveCancellation? = nil
    ) throws -> Snapshot {
        try cancellation?.check()
        let url = root.appendingPathComponent(path, isDirectory: false)
        var coordinationError: NSError?
        var outcome: Result<Snapshot, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            coordinated in
            outcome = Result {
                guard coordinated.standardizedFileURL == url.standardizedFileURL else {
                    throw WorkspaceFailure(code: "file_moved", message: "文件位置已变化，请重新打开")
                }
                return try saveAnchored(
                    root: root, path: path, expected: expected, bytes: bytes, cancellation: cancellation)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw WorkspaceFailure(code: "coordination_failed", message: "未能协调文件保存") }
        return try outcome.get()
    }
    private static func saveAnchored(
        root: URL, path: String, expected: Snapshot, bytes: Data, cancellation: DocumentSaveCancellation?
    ) throws -> Snapshot {
        try cancellation?.check()
        guard bytes.count <= maximumBytes else { throw WorkspaceFailure(code: "text_too_large", message: "文本超过 8 MiB") }
        let target = try target(root: root, path: path)
        guard flock(target.file.value, LOCK_EX | LOCK_NB) == 0 else { throw posixFailure() }
        defer { flock(target.file.value, LOCK_UN) }
        guard Version(target.info) == expected.version, try read(target.file.value) == expected.bytes else {
            throw conflict()
        }
        guard target.info.st_mode & 0o222 != 0 else {
            throw WorkspaceFailure(code: "read_only", message: "文件为只读，未写入更改")
        }
        guard target.info.st_flags & UInt32(UF_IMMUTABLE | SF_IMMUTABLE | UF_APPEND | SF_APPEND) == 0 else {
            throw WorkspaceFailure(code: "read_only", message: "文件受到不可修改标记保护")
        }
        // Opening without truncation asks the kernel about this user's actual
        // access, including ACLs; any write bit alone is not a permission grant.
        let writable = try Descriptor(
            openat(target.parent.value, target.name, O_WRONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC))
        var writableInfo = stat()
        guard fstat(writable.value, &writableInfo) == 0 else { throw posixFailure() }
        guard Version(writableInfo) == expected.version else { throw conflict() }
        let temporaryName = ".hycode-save-" + UUID().uuidString
        let temporary = try Descriptor(
            openat(target.parent.value, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600))
        var installed = false
        defer { if !installed { unlinkat(target.parent.value, temporaryName, 0) } }
        try bytes.withUnsafeBytes { raw in
            var written = 0
            while written < raw.count {
                try cancellation?.check()
                let count = Darwin.write(temporary.value, raw.baseAddress!.advanced(by: written), raw.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixFailure()
                }
                guard count > 0 else { throw posixFailure() }
                written += count
            }
        }
        guard fcopyfile(target.file.value, temporary.value, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw posixFailure()
        }
        guard futimens(temporary.value, nil) == 0 else { throw posixFailure() }
        guard fsync(temporary.value) == 0 else { throw posixFailure() }
        var current = stat()
        guard fstatat(target.parent.value, target.name, &current, AT_SYMLINK_NOFOLLOW) == 0 else { throw conflict() }
        guard Version(current) == expected.version, try read(target.file.value) == expected.bytes else {
            throw conflict()
        }
        var afterRead = stat()
        guard fstat(target.file.value, &afterRead) == 0,
            fstatat(target.parent.value, target.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
            Version(afterRead) == expected.version, Version(current) == expected.version
        else { throw conflict() }
        var saved = stat()
        guard fstat(temporary.value, &saved) == 0 else { throw posixFailure() }
        try cancellation?.check()
        guard renameat(target.parent.value, temporaryName, target.parent.value, target.name) == 0 else {
            throw posixFailure()
        }
        installed = true
        // A successful rename is the commit point. Do not report an unsaved
        // buffer after committing merely because directory fsync is unsupported.
        _ = fsync(target.parent.value)
        var committed = stat()
        if fstat(temporary.value, &committed) == 0 { saved = committed }
        return Snapshot(bytes: bytes, version: Version(saved))
    }
    private static func conflict() -> WorkspaceFailure {
        WorkspaceFailure(code: "external_change", message: "文件已在外部修改，未覆盖磁盘内容。可保留编辑或重新载入。")
    }
    private static func posixFailure() -> WorkspaceFailure {
        let code = errno
        return WorkspaceFailure(code: "file_io_\(code)", message: String(cString: strerror(code)))
    }
}
