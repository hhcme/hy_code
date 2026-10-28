import Foundation

enum GitOutputParser {
    struct Status {
        var head: String?
        var branch: String?
        var upstream: String?
        var ahead: Int?
        var behind: Int?
        var entries: [GitStatusEntry] = []
    }
    static func object(_ value: String) -> Bool {
        (value.utf8.count == 40 || value.utf8.count == 64)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func path(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 16_384, !value.hasPrefix("/"), !value.contains("\0"),
            !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                $0 == ".." || $0 == "." || $0.isEmpty || $0.lowercased() == ".git"
            })
        else { throw GitFailure("Git 返回了不受支持的文件路径") }
        return value
    }
    static func fields(_ data: Data) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { throw GitFailure("Git 路径或输出不是有效 UTF-8") }
        return text.components(separatedBy: "\0")
    }
    static func status(_ data: Data) throws -> Status {
        let records = try fields(data)
        var result = Status()
        var index = 0
        var seen = Set<String>()
        while index < records.count {
            let record = records[index]
            index += 1
            if record.isEmpty { continue }
            if record.hasPrefix("# ") {
                if record.hasPrefix("# branch.oid ") {
                    let value = String(record.dropFirst(13))
                    guard value == "(initial)" || object(value) else { throw GitFailure("Git HEAD 对象无效") }
                    result.head = value == "(initial)" ? nil : value
                } else if record.hasPrefix("# branch.head ") {
                    let value = String(record.dropFirst(14))
                    result.branch = value == "(detached)" ? nil : value
                } else if record.hasPrefix("# branch.upstream ") {
                    result.upstream = String(record.dropFirst(18))
                } else if record.hasPrefix("# branch.ab ") {
                    let parts = record.dropFirst(12).split(separator: " ")
                    guard parts.count == 2, parts[0].first == "+", parts[1].first == "-",
                        let ahead = Int(parts[0].dropFirst()), let behind = Int(parts[1].dropFirst()),
                        ahead >= 0, behind >= 0
                    else { throw GitFailure("Git 上游计数无效") }
                    result.ahead = ahead
                    result.behind = behind
                }
                continue
            }
            let entry: GitStatusEntry
            if record.hasPrefix("? ") {
                entry = GitStatusEntry(
                    path: try path(String(record.dropFirst(2))), originalPath: nil,
                    indexStatus: "?", worktreeStatus: "?", headObject: "", indexObject: "", submodule: false)
            } else if record.hasPrefix("1 ") || record.hasPrefix("2 ") || record.hasPrefix("u ") {
                let renamed = record.hasPrefix("2 ")
                let unmerged = record.hasPrefix("u ")
                let count = unmerged ? 10 : renamed ? 9 : 8
                let parts = record.split(separator: " ", maxSplits: count, omittingEmptySubsequences: false)
                guard parts.count == count + 1, parts[1].count == 2 else {
                    throw GitFailure("Git 文件状态记录不完整")
                }
                let codes = Array(parts[1])
                guard codes.allSatisfy({ ". MADRCUT".contains($0) }) else { throw GitFailure("未知 Git 文件状态") }
                var original: String?
                if renamed {
                    guard index < records.count else { throw GitFailure("Git 重命名缺少原路径") }
                    original = try path(records[index])
                    index += 1
                }
                let head = String(parts[unmerged ? 7 : 6])
                let staged = String(parts[unmerged ? 8 : 7])
                guard object(head), object(staged) else { throw GitFailure("Git 状态对象无效") }
                entry = GitStatusEntry(
                    path: try path(String(parts[count])), originalPath: original,
                    indexStatus: codes[0], worktreeStatus: codes[1], headObject: head, indexObject: staged,
                    submodule: parts[2].hasPrefix("S"))
            } else {
                throw GitFailure("不支持的 Git 状态格式")
            }
            guard result.entries.count < 20_000, seen.insert(entry.path).inserted else {
                throw GitFailure("Git 更改超过 20,000 项或包含重复路径，请缩小仓库范围")
            }
            result.entries.append(entry)
        }
        return result
    }

    static func references(_ data: Data) throws -> [GitReference] {
        guard let text = String(data: data, encoding: .utf8) else { throw GitFailure("Git 引用不是 UTF-8") }
        return try text.split(separator: "\n").map { line in
            let parts = line.components(separatedBy: "\0")
            guard parts.count == 5, object(parts[1]), parts[0].hasPrefix("refs/") else {
                throw GitFailure("Git 引用记录无效")
            }
            return GitReference(
                name: parts[0], object: parts[1], current: parts[2] == "*",
                upstream: parts[3].isEmpty ? nil : parts[3])
        }
    }

    static func commits(_ data: Data) throws -> [GitCommit] {
        var records = try fields(data)
        while records.last == "" { records.removeLast() }
        guard records.count.isMultiple(of: 10) else { throw GitFailure("Git 日志记录不完整") }
        var result: [GitCommit] = []
        for index in stride(from: 0, to: records.count, by: 10) {
            let parts = Array(records[index..<(index + 10)])
            let parents = parts[1].split(separator: " ").map(String.init)
            guard object(parts[0]), parents.allSatisfy(object),
                let authored = TimeInterval(parts[4]), let committed = TimeInterval(parts[7]),
                authored.isFinite, committed.isFinite, parts[9].utf8.count <= 65_536
            else { throw GitFailure("Git 提交记录无效或消息超出 64 KiB") }
            result.append(
                GitCommit(
                    object: parts[0], parents: parents, author: parts[2], email: parts[3],
                    authoredAt: Date(timeIntervalSince1970: authored), committer: parts[5], committerEmail: parts[6],
                    committedAt: Date(timeIntervalSince1970: committed), decorations: parts[8],
                    message: parts[9].trimmingCharacters(in: .newlines)))
        }
        return result
    }

    static func changedFiles(_ data: Data) throws -> [GitCommitFile] {
        let parts = try fields(data)
        var result: [GitCommitFile] = []
        var index = 0
        while index < parts.count, !parts[index].isEmpty {
            guard result.count < 20_000 else { throw GitFailure("提交文件列表超过 20,000 项，未把截断列表作为完整范围") }
            let status = parts[index]
            guard index + 1 < parts.count, !status.isEmpty else { throw GitFailure("Git 文件列表不完整") }
            let first = try path(parts[index + 1])
            index += 2
            let renamed = status.hasPrefix("R") || status.hasPrefix("C")
            var original: String?
            var current = first
            if renamed {
                guard index < parts.count else { throw GitFailure("Git 重命名缺少路径") }
                original = first
                current = try path(parts[index])
                index += 1
            }
            result.append(GitCommitFile(path: current, originalPath: original, status: status))
        }
        return result
    }
}
