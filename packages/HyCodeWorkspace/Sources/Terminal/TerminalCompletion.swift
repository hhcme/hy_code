import Darwin
import Foundation

/// A shell report describes the editable buffer, never inferred from output text.
public struct TerminalPromptState: Codable, Equatable, Sendable {
    public let token: String
    public let phase: String
    public let line: String
    public let cursor: Int
    public let directory: String
    public var acceptance: String? = nil

    public static func decode(_ bytes: Data, token: String) -> Self? {
        guard bytes.count <= 8192, let value = try? JSONDecoder().decode(Self.self, from: bytes),
            value.token == token, ["edit", "finish"].contains(value.phase),
            value.line.utf8.count <= 4096, value.directory.utf8.count <= 4096,
            value.directory.hasPrefix("/"), value.cursor >= 0,
            value.cursor <= value.line.unicodeScalars.count,
            !value.line.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
            !value.directory.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { return nil }
        return value
    }
}

public struct TerminalCompletionRequest: Sendable {
    public let line: String
    public let words: [String]
    public let prefix: String
    private let quote: Unicode.Scalar?

    /// Single simple command, caret at the end. Compound expressions stay with
    /// the shell's own completion; no evaluation, subprocess or history read.
    public static func parse(line: String, cursor: Int) -> Self? {
        guard line.utf8.count <= 4096, cursor == line.unicodeScalars.count else { return nil }
        var words: [String] = []
        var current = ""
        var quote: Unicode.Scalar?
        var escaped = false
        var started = false
        for scalar in line.unicodeScalars {
            guard scalar.value >= 32, scalar.value != 127 else { return nil }
            if escaped {
                if quote == "\"", !"\\\"$\u{60}".unicodeScalars.contains(scalar) {
                    current.unicodeScalars.append("\\")
                }
                current.unicodeScalars.append(scalar)
                escaped = false
                started = true
            } else if scalar == "\\", quote != "'" {
                escaped = true
                started = true
            } else if scalar == "'", quote != "\"" {
                quote = quote == nil ? scalar : nil
                started = true
            } else if scalar == "\"", quote != "'" {
                quote = quote == nil ? scalar : nil
                started = true
            } else if quote == nil, scalar == " " {
                if started { words.append(current) }
                current = ""
                started = false
            } else {
                // Avoid guessing expansion, pipelines, redirects and comments.
                if quote != "'", "$\u{60}".unicodeScalars.contains(scalar) { return nil }
                if quote == nil, "|;&<>(){}*?[]!#".unicodeScalars.contains(scalar) { return nil }
                current.unicodeScalars.append(scalar)
                started = true
            }
        }
        guard !escaped, words.count <= 32 else { return nil }
        return Self(line: line, words: words, prefix: current, quote: quote)
    }

    fileprivate func suffix(for value: String, directory: Bool) -> String? {
        guard value.hasPrefix(prefix), value != prefix || !directory,
            !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { return nil }
        let remaining = String(value.dropFirst(prefix.count))
        var encoded = ""
        for scalar in remaining.unicodeScalars {
            if quote == "'" {
                encoded += scalar == "'" ? "'\\''" : String(scalar)
            } else if quote == "\"" {
                if "\\\"$\u{60}".unicodeScalars.contains(scalar) { encoded += "\\" }
                encoded.unicodeScalars.append(scalar)
            } else {
                if !"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-".unicodeScalars.contains(
                    scalar)
                    && scalar.isASCII
                {
                    encoded += "\\"
                }
                encoded.unicodeScalars.append(scalar)
            }
        }
        if directory { return encoded + "/" }
        if let quote { encoded.unicodeScalars.append(quote) }
        return encoded + " "
    }
}

public struct TerminalCompletionCandidate: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case command, subcommand, option, folder, file }
    public let value: String
    public let detail: String
    public let kind: Kind
    public let suffix: String
    public var id: String { kind.rawValue + ":" + value }
}

public enum TerminalCompletionProvider {
    /// Call from a utility task. At most one directory / 512 entries are read;
    /// paths outside the explicitly authorized workspace are never enumerated.
    public static func suggestions(
        for request: TerminalCompletionRequest, directory: URL, root: URL
    ) -> [TerminalCompletionCandidate] {
        var result: [TerminalCompletionCandidate] = []
        let entries = TerminalCommandCatalog.entries(words: request.words, prefix: request.prefix)
        for entry in entries where entry.value.hasPrefix(request.prefix) && entry.value != request.prefix {
            guard let suffix = request.suffix(for: entry.value, directory: false) else { continue }
            result.append(.init(value: entry.value, detail: entry.detail, kind: entry.kind, suffix: suffix))
        }
        if !request.words.isEmpty || request.prefix.contains("/") {
            result.append(contentsOf: paths(for: request, directory: directory, root: root))
        }
        return Array(result.prefix(40))
    }

    private static func contained(_ path: URL, in root: URL) -> Bool {
        root.path == "/" || path.path == root.path || path.path.hasPrefix(root.path + "/")
    }
    private static func openDirectory(_ target: URL, root: URL) -> Int32 {
        guard contained(target, in: root) else { return -1 }
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return -1 }
        let relative = String(target.path.dropFirst(root.path == "/" ? 1 : root.path.count))
        for component in relative.split(separator: "/") {
            let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            close(descriptor)
            guard next >= 0 else { return -1 }
            descriptor = next
        }
        return descriptor
    }
    private static func paths(
        for request: TerminalCompletionRequest, directory: URL, root: URL
    ) -> [TerminalCompletionCandidate] {
        let prefix = request.prefix
        guard !prefix.hasPrefix("-"), !prefix.hasPrefix("~") else { return [] }
        let slash = prefix.lastIndex(of: "/")
        let parent = slash.map { String(prefix[...$0]) } ?? ""
        let leaf = slash.map { String(prefix[prefix.index(after: $0)...]) } ?? prefix
        let target = (parent.hasPrefix("/") ? URL(fileURLWithPath: parent) : directory.appendingPathComponent(parent))
            .resolvingSymlinksInPath().standardizedFileURL
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let descriptor = openDirectory(target, root: root)
        guard descriptor >= 0 else { return [] }
        guard let handle = fdopendir(descriptor) else {
            close(descriptor)
            return []
        }
        defer { closedir(handle) }
        var result: [TerminalCompletionCandidate] = []
        var count = 0
        while count < 512, !Task.isCancelled, let entry = readdir(handle) {
            count += 1
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(validatingCString: $0) }
            }
            guard let name, name != ".", name != "..", name.hasPrefix(leaf),
                !name.hasPrefix(".") || leaf.hasPrefix(".")
            else { continue }
            var info = stat()
            guard fstatat(dirfd(handle), name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG else { continue }
            let isDirectory = kind == S_IFDIR
            if request.words.first == "cd", !isDirectory { continue }
            let value = parent + name
            guard let suffix = request.suffix(for: value, directory: isDirectory) else { continue }
            result.append(
                .init(
                    value: value, detail: isDirectory ? "目录" : "项目文件",
                    kind: isDirectory ? .folder : .file, suffix: suffix))
        }
        return result.sorted {
            if $0.kind != $1.kind { return $0.kind == .folder }
            return $0.value.localizedStandardCompare($1.value) == .orderedAscending
        }
    }
}
