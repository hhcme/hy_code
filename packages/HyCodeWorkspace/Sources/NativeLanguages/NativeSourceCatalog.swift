import Foundation

/// One bounded, metadata-only catalog shared by the three native language
/// owners. Files are read separately through anchored descriptors, never here.
public struct NativeSourceCatalog: Sendable {
    public struct File: Sendable, Equatable {
        public let path: String
        public let language: NativeCodeLanguage
        public let modified: Date
        public let size: Int
    }
    public let files: [File]
    public let limited: Bool
    public static func scan(root: URL) throws -> Self {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey,
        ]
        var unreadable = false
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants],
                errorHandler: { _, _ in
                    unreadable = true
                    return true
                })
        else {
            throw LanguageServiceFailure("无法扫描语言源文件")
        }
        var files: [File] = []
        var bytes = 0
        var entries = 0
        var limited = false
        var parts: [String] = []
        while let url = walker.nextObject() as? URL {
            try Task.checkCancellation()
            entries += 1
            guard entries <= 50_000 else {
                limited = true
                break
            }
            parts = Array(parts.prefix(max(0, walker.level - 1)))
            parts.append(url.lastPathComponent)
            let path = parts.joined(separator: "/")
            guard ProjectSourceCatalog.allows(path),
                !parts.contains(where: { [".gradle", "out", "DerivedData", ".metadata"].contains($0) }),
                let info = try? url.resourceValues(forKeys: keys), info.isSymbolicLink != true
            else {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    walker.skipDescendants()
                }
                continue
            }
            if info.isDirectory == true { continue }
            guard info.isRegularFile == true, let language = NativeCodeLanguage.detect(path) else { continue }
            let size = info.fileSize ?? Int.max
            guard size <= 1_048_576 else {
                limited = true
                continue
            }
            guard files.count < 2_000, bytes + size <= 32 * 1024 * 1024 else {
                limited = true
                break
            }
            bytes += size
            files.append(
                File(path: path, language: language, modified: info.contentModificationDate ?? .distantPast, size: size)
            )
        }
        return Self(files: files.sorted { $0.path < $1.path }, limited: limited || unreadable)
    }
    public static func read(path: String, root: URL) throws -> String {
        guard ProjectSourceCatalog.allows(path) else { throw LanguageServiceFailure("源文件路径无效") }
        let data = try PreviewFileIO.read(root: root, path: path, limit: 1_048_576)
        let text: String?
        if data.starts(with: [0xff, 0xfe]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xfe, 0xff]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else {
            text = String(data: data.starts(with: [0xef, 0xbb, 0xbf]) ? data.dropFirst(3) : data, encoding: .utf8)
        }
        guard let text, !text.contains("\0"), text.utf8.count <= 1_048_576 else {
            throw LanguageServiceFailure("语义源文件不是支持的文本或超过 1 MiB")
        }
        return text
    }
}
