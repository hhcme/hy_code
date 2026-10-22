import Foundation

enum WorkspaceCanonicalPath {
    /// Resolve the nearest existing ancestor, including symlinked parents of a
    /// nonexistent leaf. Foundation's whole-path resolver can leave those out.
    static func resolve(_ value: URL) throws -> URL {
        var current = value.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            guard parent != current, missing.count < 256 else { throw LanguageServiceFailure("文件路径无法规范化") }
            missing.append(current.lastPathComponent)
            current = parent
        }
        current = current.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { current.appendPathComponent(component) }
        return current.standardizedFileURL
    }
}
