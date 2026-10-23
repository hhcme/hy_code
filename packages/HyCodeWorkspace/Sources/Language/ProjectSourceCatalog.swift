import Darwin
import Foundation

public struct ProjectSourceFile: Sendable, Equatable {
    public let path: String
    public let language: WebLanguage
    public let size: Int
    public let modified: Date
    public func uri(in root: URL) -> String { root.appendingPathComponent(path).absoluteString }
}

/// Read-only discovery for analysis. It never creates editor documents or reads
/// dependencies/build output. Call from a utility task, never MainActor.
public struct ProjectSourceCatalog: Sendable {
    public let files: [ProjectSourceFile]
    public let hasDart: Bool
    public let skipped: Int
    public let limited: Bool
    public static let excluded: Set<String> = [
        "node_modules", ".git", ".hg", ".svn", ".dart_tool", ".pub-cache", "build", "dist", "coverage",
        ".next", ".nuxt", ".output", ".turbo", ".cache", "Pods", "vendor", "target", ".build",
    ]
    public static func allows(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        return !parts.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
            && !parts.contains("..") && !parts.contains { excluded.contains(String($0)) }
            && !parts.contains { $0.hasPrefix(".") && ![".github", ".vscode"].contains(String($0)) }
    }
    public static func scan(root: URL, fileLimit: Int = 5_000, byteLimit: Int = 64 * 1024 * 1024) throws -> Self {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]
        var failed = false
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in
                    failed = true
                    return true
                })
        else {
            throw LanguageServiceFailure("无法扫描项目源文件")
        }
        var files: [ProjectSourceFile] = []
        var bytes = 0
        var entries = 0
        var skipped = 0
        var hasDart = false
        var limited = false
        var components: [String] = []
        while let url = walker.nextObject() as? URL {
            try Task.checkCancellation()
            entries += 1
            if entries > 50_000 {
                limited = true
                break
            }
            components = Array(components.prefix(max(0, walker.level - 1)))
            components.append(url.lastPathComponent)
            let path = components.joined(separator: "/")
            guard allows(path) else {
                walker.skipDescendants()
                continue
            }
            guard let info = try? url.resourceValues(forKeys: Set(keys)), info.isSymbolicLink != true else {
                walker.skipDescendants()
                skipped += 1
                continue
            }
            if info.isDirectory == true { continue }
            if url.pathExtension.lowercased() == "dart" || url.lastPathComponent == "pubspec.yaml" { hasDart = true }
            guard info.isRegularFile == true, let language = WebLanguage.detect(path) else { continue }
            let size = info.fileSize ?? Int.max
            guard size <= 1_048_576 else {
                skipped += 1
                continue
            }
            guard files.count < fileLimit, bytes + size <= byteLimit else {
                limited = true
                break
            }
            bytes += size
            files.append(
                ProjectSourceFile(
                    path: path, language: language, size: size, modified: info.contentModificationDate ?? .distantPast))
        }
        return Self(
            files: files.sorted { $0.path < $1.path }, hasDart: hasDart, skipped: skipped,
            limited: limited || failed)
    }
    public static func read(_ file: ProjectSourceFile, root: URL) throws -> String {
        guard allows(file.path) else { throw LanguageServiceFailure("分析路径越界") }
        var fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw LanguageServiceFailure("无法读取项目") }
        defer { Darwin.close(fd) }
        let parts = file.path.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { throw LanguageServiceFailure("分析路径为空") }
        for part in parts.dropLast() {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw LanguageServiceFailure("分析目录不可访问或是链接") }
            Darwin.close(fd)
            fd = next
        }
        let input = openat(fd, parts.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard input >= 0 else { throw LanguageServiceFailure("分析文件不可访问或是链接") }
        defer { Darwin.close(input) }
        var metadata = stat()
        guard fstat(input, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
            metadata.st_size <= 1_048_576
        else { throw LanguageServiceFailure("分析文件超过 1 MiB 或不是普通文件") }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(input, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw LanguageServiceFailure("分析读取失败") }
            if count == 0 { break }
            guard data.count + count <= 1_048_576 else { throw LanguageServiceFailure("分析文件读取期间变大") }
            data.append(contentsOf: chunk.prefix(count))
        }
        let text: String?
        if data.starts(with: [0xff, 0xfe]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xfe, 0xff]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            text = String(data: data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data, encoding: .utf8)
        }
        guard let text, !text.contains("\0") else { throw LanguageServiceFailure("分析文件不是支持的文本编码") }
        return text
    }
    public static func inspect(path: String, root: URL) -> ProjectSourceFile? {
        guard allows(path), let language = WebLanguage.detect(path) else { return nil }
        let url = root.appendingPathComponent(path)
        guard canonicalPath(url.path) == canonicalPath(root.path).map({ $0 + "/" + path }),
            let value = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
            ]),
            value.isRegularFile == true, value.isSymbolicLink != true, let size = value.fileSize, size <= 1_048_576
        else { return nil }
        return ProjectSourceFile(
            path: path, language: language, size: size, modified: value.contentModificationDate ?? .distantPast)
    }
    static func canonicalPath(_ path: String) -> String? {
        guard let value = realpath(path, nil) else { return nil }
        defer { free(value) }
        return String(cString: value)
    }
}
