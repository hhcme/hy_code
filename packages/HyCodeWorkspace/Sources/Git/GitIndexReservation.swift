import Darwin
import Foundation

/// The real index is reserved once for a complete commit. Alternate indexes are
/// prepared first; only this owner's inode can be installed or removed.
final class GitIndexReservation {
    let url: URL
    private let target: URL
    private let descriptor: Int32
    private let inode: ino_t
    private var installed = false
    private var preserve = false
    init(repository: GitRepositoryIdentity) throws {
        target = repository.directory.appendingPathComponent("index")
        url = repository.directory.appendingPathComponent("index.lock")
        descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw GitFailure("Git 暂存区被占用；请等待其他操作完成，不要删除外部锁文件") }
        var value = stat()
        guard fstat(descriptor, &value) == 0 else {
            close(descriptor)
            throw GitFailure("无法确认 Git 索引锁身份")
        }
        inode = value.st_ino
    }
    private func ownsPath() -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0 && value.st_ino == inode && value.st_mode & S_IFMT == S_IFREG
            && value.st_nlink == 1
    }
    func prepare(_ data: Data) throws {
        guard ownsPath() else { throw GitFailure("Git 索引锁身份已改变") }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw GitFailure("准备 Git 索引失败") }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw GitFailure("同步 Git 索引失败") }
    }
    func install(description: String) throws {
        guard ownsPath() else {
            preserve = true
            throw GitFailure(description + "，但索引锁被替换；请核对仓库，不要重复操作")
        }
        guard rename(url.path, target.path) == 0 else {
            preserve = true
            throw GitFailure(description + "，索引收尾失败；已准备的索引保留在 .git/index.lock，请用专用工具核对恢复，不要重复操作")
        }
        installed = true
    }
    func preserveForRecovery() { preserve = true }
    deinit {
        close(descriptor)
        if !installed, !preserve, ownsPath() { _ = unlink(url.path) }
    }
}
