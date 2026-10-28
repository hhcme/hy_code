import CryptoKit
import Darwin
import Foundation

/// HyCode-owned local credentials, outside projects and Codex runtime homes.
/// The directory is 0700 and each bounded UTF-8 record is 0600. No system
/// credential service, authentication context or permission dialog is used.
public actor CodexCredentials {
    public let directory: URL
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .resolvingSymlinksInPath().appendingPathComponent("HyCode/Credentials/Codex", isDirectory: true)
    }
    public init(directory: URL = CodexCredentials.defaultDirectory) { self.directory = directory.standardizedFileURL }
    public func read(_ account: String) throws -> String? {
        let name = try Self.recordName(account)
        guard let vault = try CodexCredentialDirectory(directory, create: false),
            let data = try vault.read(name)
        else { return nil }
        guard let value = String(data: data, encoding: .utf8), Self.validSecret(value) else {
            throw LanguageServiceFailure("本地 API Key 文件内容无效，请在模型服务设置重新填写")
        }
        return value
    }
    public func write(_ value: String, account: String) throws {
        guard Self.validSecret(value) else { throw LanguageServiceFailure("API Key 为空、过长或包含控制字符") }
        let name = try Self.recordName(account)
        guard let vault = try CodexCredentialDirectory(directory, create: true) else { throw POSIXError(.ENOENT) }
        try vault.write(Data(value.utf8), name: name)
    }
    static func recordName(_ account: String) throws -> String {
        guard !account.isEmpty, account.utf8.count <= 1024,
            !account.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw LanguageServiceFailure("本地密钥账户标识无效") }
        return SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined() + ".key"
    }
    private static func validSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

/// Short cross-process leases and directory-relative descriptors prevent
/// partial writes and symlink/FIFO/hardlink substitution. Descriptors never
/// survive exec; only this object owns and closes them.
private final class CodexCredentialDirectory {
    private let directoryFD: Int32
    private let lockFD: Int32
    init?(_ url: URL, create: Bool) throws {
        let path = url.standardizedFileURL
        guard path.resolvingSymlinksInPath().path == path.path else {
            throw LanguageServiceFailure("本地密钥目录包含符号链接，已停止访问")
        }
        var initial = stat()
        if lstat(path.path, &initial) != 0 {
            guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard create else { return nil }
            try FileManager.default.createDirectory(
                at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let folder = open(path.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard folder >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var status = stat()
        guard fstat(folder, &status) == 0, status.st_mode & S_IFMT == S_IFDIR, status.st_uid == geteuid(),
            fchmod(folder, 0o700) == 0
        else {
            close(folder)
            throw LanguageServiceFailure("本地密钥目录不属于当前用户或无法设置私有权限")
        }
        let lock = openat(folder, ".lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else {
            close(folder)
            throw LanguageServiceFailure("无法取得本地密钥存储锁")
        }
        do { try Self.regular(lock) } catch {
            close(lock)
            close(folder)
            throw error
        }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock)
            close(folder)
            throw LanguageServiceFailure("本地密钥正在由另一个配置任务使用，请稍后重试")
        }
        directoryFD = folder
        lockFD = lock
    }
    deinit {
        close(lockFD)
        close(directoryFD)
    }
    func read(_ name: String) throws -> Data? {
        let fd = openat(directoryFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw LanguageServiceFailure("无法读取本地 API Key 文件，请在模型服务设置重新填写")
        }
        defer { close(fd) }
        try Self.regular(fd)
        var bytes = [UInt8](repeating: 0, count: 16_385)
        var used = 0
        while used < bytes.count {
            let count = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: used), buffer.count - used)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw POSIXError(.EIO) }
            if count == 0 { break }
            used += count
        }
        guard used <= 16_384 else { throw LanguageServiceFailure("本地 API Key 文件超过 16 KiB 预算") }
        return Data(bytes.prefix(used))
    }
    func write(_ data: Data, name: String) throws {
        // Reject even a dangling symlink instead of replacing it silently.
        var target = stat()
        if fstatat(directoryFD, name, &target, AT_SYMLINK_NOFOLLOW) == 0 {
            guard target.st_mode & S_IFMT == S_IFREG, target.st_uid == geteuid(), target.st_nlink == 1 else {
                throw LanguageServiceFailure("本地密钥目标不是当前用户的独立普通文件")
            }
        } else if errno != ENOENT {
            throw POSIXError(.EIO)
        }
        let temporary = ".key-" + UUID().uuidString
        let fd = openat(directoryFD, temporary, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer {
            close(fd)
            _ = unlinkat(directoryFD, temporary, 0)
        }
        var written = 0
        while written < data.count {
            let count = data.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: written), $0.count - written)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw POSIXError(.EIO) }
            written += count
        }
        guard fsync(fd) == 0, renameat(directoryFD, temporary, directoryFD, name) == 0 else { throw POSIXError(.EIO) }
    }
    private static func regular(_ fd: Int32) throws {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
            value.st_uid == geteuid(), value.st_nlink == 1, value.st_size <= 16_384,
            fchmod(fd, 0o600) == 0
        else { throw LanguageServiceFailure("本地密钥存储必须是当前用户的独立普通文件，且不超过 16 KiB") }
    }
}
