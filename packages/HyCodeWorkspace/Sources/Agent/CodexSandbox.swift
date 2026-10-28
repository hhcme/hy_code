import Darwin
import Foundation

/// Outer macOS sandbox is also applied to the app-server and Code Mode host.
/// Codex's inner command sandbox alone does not restrict agent file reads.
public enum CodexSandbox {
    public static func arguments(
        executable: URL, root: URL, home: URL, mode: CodexAccessMode, runtimeArguments: [String]
    ) throws -> [String] {
        guard executable.lastPathComponent == "codex", executable.deletingLastPathComponent().lastPathComponent == "bin"
        else {
            throw LanguageServiceFailure("Codex 运行目录布局无效")
        }
        let runtime = executable.deletingLastPathComponent().deletingLastPathComponent()
        return ["-p", try policy(runtime: runtime, root: root, home: home, mode: mode), executable.path]
            + runtimeArguments
    }
    static func policy(
        runtime: URL, root: URL, home: URL, mode: CodexAccessMode,
        protectedDirectories: [URL] = [CodexCredentials.defaultDirectory]
    ) throws -> String {
        func quote(_ value: String) throws -> String { try CodexWireLiteral.string(value) }
        let reads = [
            "/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db/dyld",
            "/Library/Apple/System", "/Library/Preferences", "/dev", "/private/var/run",
            try canonicalPath(runtime), try canonicalPath(root), try canonicalPath(home),
        ]
        let writes = [try canonicalPath(home)] + (mode == .workspaceWrite ? [try canonicalPath(root)] : [])
        // macOS dyld and SQLite canonicalize/open directory ancestors. Grant
        // directory entries on that chain, never the contents of sibling files.
        var ancestors = Set<String>()
        for path in [runtime, root, home] {
            var parent = (try canonicalPath(path) as NSString).deletingLastPathComponent
            while parent != "/" {
                ancestors.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        let readRules = try
            (reads.map { "(subpath " + (try quote($0)) + ")" }
            + ancestors.sorted().map { "(literal " + (try quote($0)) + ")" }).joined(separator: " ")
        let writeRules = try writes.map { "(subpath " + (try quote($0)) + ")" }.joined(separator: " ")
        var protections: [String] = []
        for directory in protectedDirectories {
            let path = try physicalDestination(directory)
            protections.append("(deny file-read* file-write* (subpath " + (try quote(path)) + "))")
            // A broad workspace must not rename a vault ancestor and then read
            // credentials under an unprotected alias inside the same root.
            var parent = (path as NSString).deletingLastPathComponent
            while parent != "/" {
                protections.append("(deny file-write* (literal " + (try quote(parent)) + "))")
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        let policy = """
            (version 1)
            (allow default)
            (deny file-read-data (require-not (require-any (literal "/") \(readRules))))
            (deny file-write* (require-not (require-any \(writeRules) (literal "/dev/null") (literal "/dev/tty"))))
            \(protections.joined(separator: "\n"))
            """
        return policy
    }
    /// Policy must protect the destination before the first key is saved too.
    private static func physicalDestination(_ url: URL) throws -> String {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        var info = stat()
        while lstat(existing.path, &info) != 0 {
            guard errno == ENOENT, existing.path != "/" else { throw POSIXError(.ENOENT) }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        let base = try canonicalPath(existing)
        return missing.reversed().reduce(base) { ($0 as NSString).appendingPathComponent($1) }
    }
    static func canonicalPath(_ url: URL) throws -> String {
        // Foundation can shorten /private/var to /var on macOS. Seatbelt matches
        // the kernel's physical path, so its filters must use POSIX realpath.
        guard let pointer = realpath(url.path, nil) else { throw POSIXError(.ENOENT) }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
