import CryptoKit
import Darwin
import Foundation

/// Blocking file work runs on the repository's utility task, never MainActor.
/// No-follow descriptors and the process sandbox cover independent boundaries.
enum GitFileAccess {
    static func canonical(_ url: URL) throws -> URL {
        guard let pointer = realpath(url.path, nil) else { throw GitFailure("Git 路径不可访问") }
        defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer)).standardizedFileURL
    }
    static func contains(_ root: URL, _ url: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }
    static func info(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return value
    }
    static func smallFile(_ url: URL, limit: Int = 1_048_576, optional: Bool = false) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0, optional, errno == ENOENT { return Data() }
        guard descriptor >= 0 else { throw GitFailure("无法安全读取 Git 元数据：\(url.lastPathComponent)") }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
            before.st_size >= 0, before.st_size <= limit
        else { throw GitFailure("Git 元数据不是独立普通文件或超过读取预算：\(url.lastPathComponent)") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw GitFailure("读取 Git 文件失败") }
            if count == 0 { break }
            guard data.count + count <= limit else { throw GitFailure("Git 文件超过读取预算") }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, stable(before, after) else { throw GitFailure("读取期间 Git 文件发生变化") }
        return data
    }
    static func stable(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size && a.st_mode == b.st_mode
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func diskDigest(_ path: String, repository: GitRepositoryIdentity) throws -> String {
        _ = try GitOutputParser.path(path)
        let parts = path.split(separator: "/").map(String.init)
        var parent = open(repository.root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw GitFailure("无法安全打开 Git 工作树") }
        defer { close(parent) }
        for component in parts.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            if next < 0, errno == ENOENT { return "missing" }
            guard next >= 0 else { throw GitFailure("Git 文件父路径包含链接或不可访问的目录") }
            close(parent)
            parent = next
        }
        let leaf = parts[parts.count - 1]
        var metadata = stat()
        if fstatat(parent, leaf, &metadata, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw GitFailure("无法检查 Git 文件") }
            return "missing"
        }
        if metadata.st_mode & S_IFMT == S_IFLNK {
            var target = [CChar](repeating: 0, count: 16_385)
            let count = readlinkat(parent, leaf, &target, target.count)
            guard count >= 0, count < target.count else { throw GitFailure("Git 链接目标过长") }
            var after = stat()
            guard fstatat(parent, leaf, &after, AT_SYMLINK_NOFOLLOW) == 0, stable(metadata, after) else {
                throw GitFailure("Git 链接在读取期间改变")
            }
            let bytes = target.prefix(count).map { UInt8(bitPattern: $0) }
            return "link:" + digest(Data(bytes))
        }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else {
            throw GitFailure("不支持提交目录、硬链接或特殊文件，请使用专用 Git 工具处理")
        }
        let descriptor = openat(parent, leaf, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw GitFailure("无法读取提交候选文件") }
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, stable(metadata, before) else { throw GitFailure("Git 文件已改变") }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 262_144)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw GitFailure("计算 Git 文件版本失败") }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        var named = stat()
        guard fstat(descriptor, &after) == 0, stable(before, after),
            fstatat(parent, leaf, &named, AT_SYMLINK_NOFOLLOW) == 0, stable(after, named)
        else {
            throw GitFailure("Git 文件读取期间发生变化，请重新查看差异")
        }
        return "file:\(metadata.st_mode & 0o777):" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func discover(root: URL, authorizedDirectories: [URL] = []) throws -> GitRepositoryIdentity? {
        let root = try canonical(root)
        let grants = try authorizedDirectories.map(canonical)
        let marker = root.appendingPathComponent(".git")
        var markerInfo = stat()
        if lstat(marker.path, &markerInfo) != 0 {
            guard errno == ENOENT else { throw GitFailure("不能访问项目的 Git 目录") }
            // Do not gain ancestor access merely by opening a child directory.
            return nil
        }
        let directory: URL
        if markerInfo.st_mode & S_IFMT == S_IFDIR {
            directory = try canonical(marker)
        } else if markerInfo.st_mode & S_IFMT == S_IFREG {
            let bytes = try smallFile(marker, limit: 16_384)
            guard let text = String(data: bytes, encoding: .utf8), text.hasPrefix("gitdir: ") else {
                throw GitFailure("Git 工作树指针无效")
            }
            let pointer = String(text.dropFirst(8)).trimmingCharacters(in: .newlines)
            directory = try canonical(
                pointer.hasPrefix("/") ? URL(fileURLWithPath: pointer) : root.appendingPathComponent(pointer))
        } else {
            throw GitFailure("Git 管理入口不允许是符号链接或特殊文件")
        }
        guard ([root] + grants).contains(where: { contains($0, directory) }) else {
            throw GitFailure("Git 管理目录在项目授权范围之外，请主动授权包含它的 Git 公共管理目录", code: .authorization)
        }
        let commonBytes = try smallFile(directory.appendingPathComponent("commondir"), limit: 16_384, optional: true)
        var common = directory
        if !commonBytes.isEmpty {
            guard let value = String(data: commonBytes, encoding: .utf8) else { throw GitFailure("Git 公共目录无效") }
            let pointer = value.trimmingCharacters(in: .newlines)
            common = try canonical(
                pointer.hasPrefix("/") ? URL(fileURLWithPath: pointer) : directory.appendingPathComponent(pointer))
        }
        guard ([root] + grants).contains(where: { contains($0, common) }) else {
            throw GitFailure("共享 Git 管理目录需要额外的项目访问授权", code: .authorization)
        }
        let identity = GitRepositoryIdentity(
            root: root, directory: directory, commonDirectory: common, authorizedRoot: root,
            additionalAuthorizedDirectories: grants)
        try validateMetadata(identity)
        return identity
    }

    static func validateMetadata(_ repository: GitRepositoryIdentity) throws {
        for url in [repository.directory, repository.commonDirectory] {
            guard try canonical(url) == url, try info(url).st_mode & S_IFMT == S_IFDIR else {
                throw GitFailure("Git 管理目录已改变")
            }
        }
        for url in [
            repository.commonDirectory.appendingPathComponent("config"),
            repository.directory.appendingPathComponent("config.worktree"),
        ] {
            let data = try smallFile(url, optional: true)
            guard let text = String(data: data, encoding: .utf8) else { throw GitFailure("Git 配置不是 UTF-8") }
            // Reject include sections before Git parses them, including quoted
            // section spellings. No config values or contents enter diagnostics.
            let logical = text.replacingOccurrences(of: "\u{feff}", with: "")
                .replacingOccurrences(of: "\\\r\n", with: "").replacingOccurrences(of: "\\\n", with: "")
            for line in logical.components(separatedBy: .newlines) {
                let value = line.trimmingCharacters(in: .whitespaces).lowercased()
                if value.hasPrefix("["), value.contains("include") {
                    throw GitFailure("仓库 Git 配置含外部 include；当前受限模式不读取，请在专用 Git 工具中处理")
                }
            }
        }
        let alternates = repository.commonDirectory.appendingPathComponent("objects/info/alternates")
        let alternateData = try smallFile(alternates, limit: 65_536, optional: true)
        if !alternateData.isEmpty { throw GitFailure("此版本不读取带外部 alternates 的 Git 对象库") }
    }

    static func index(_ repository: GitRepositoryIdentity) throws -> Data {
        try smallFile(repository.directory.appendingPathComponent("index"), limit: 67_108_864, optional: true)
    }
}
