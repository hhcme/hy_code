import Foundation

public struct TerminalFileReference: Sendable {
    public let url: URL
    public let line: Int
    public let column: Int

    /// This performs filesystem work and must be called off the UI thread.
    /// OSC links/cwd are untrusted hints, never a new file-access authorization.
    public static func resolve(_ text: String, directory: URL, root: URL) throws -> Self {
        guard text.utf8.count < 8192, !text.contains("\0") else { throw TerminalFailure("终端文件路径无效") }
        let path: String
        if let url = URL(string: text), let scheme = url.scheme, scheme == "file" {
            guard url.host == nil || url.host == "" || url.host == "localhost" else {
                throw TerminalFailure("终端仅打开本地项目文件")
            }
            path = url.path
        } else if text.contains("://") {
            throw TerminalFailure("此入口仅支持当前项目内的文件和目录")
        } else {
            path = text
        }
        var candidate = path
        var line = 1
        var column = 1
        func absolute(_ path: String) -> URL {
            path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        }
        if !FileManager.default.fileExists(atPath: absolute(path).path),
            let suffix = path.range(of: #":[0-9]+(?::[0-9]+)?$"#, options: .regularExpression)
        {
            let parts = path[suffix].dropFirst().split(separator: ":")
            guard let parsed = Int(parts[0]), parsed > 0, parsed <= 100_000_000 else {
                throw TerminalFailure("终端文件行号无效")
            }
            line = parsed
            if parts.count == 2 {
                guard let parsed = Int(parts[1]), parsed > 0, parsed <= 100_000_000 else {
                    throw TerminalFailure("终端文件列号无效")
                }
                column = parsed
            }
            candidate = String(path[..<suffix.lowerBound])
        }
        let canonical = absolute(candidate).standardizedFileURL.resolvingSymlinksInPath()
        let root = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard canonical.path == root || canonical.path.hasPrefix(root == "/" ? "/" : root + "/") else {
            throw TerminalFailure("该路径不在当前授权项目内，请通过打开入口访问")
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &directory) else {
            throw TerminalFailure("终端引用的文件或目录不存在")
        }
        return Self(
            url: URL(fileURLWithPath: canonical.path, isDirectory: directory.boolValue), line: line, column: column)
    }
}
