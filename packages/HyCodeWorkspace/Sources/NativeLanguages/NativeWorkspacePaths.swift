import Darwin
import Foundation

public enum NativeWorkspacePaths {
    public static func physical(_ url: URL) throws -> URL {
        var current = url.standardizedFileURL
        var suffix: [String] = []
        while true {
            if let path = realpath(current.path, nil) {
                defer { free(path) }
                var result = URL(fileURLWithPath: String(cString: path))
                for part in suffix.reversed() { result.appendPathComponent(part) }
                return result
            }
            let parent = current.deletingLastPathComponent()
            guard parent != current, suffix.count < 256 else { throw LanguageServiceFailure("无法规范化工具缓存路径") }
            suffix.append(current.lastPathComponent)
            current = parent
        }
    }
    public static func cacheIsOutsideProject(root: URL, cache: URL) throws -> Bool {
        let root = try physical(root).path
        let cache = try physical(cache).path
        return root != "/" && root != cache && !cache.hasPrefix(root + "/")
    }
}
