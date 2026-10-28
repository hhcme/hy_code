import Foundation

public struct GitFailure: Error, LocalizedError, Sendable, Equatable {
    public enum Code: Sendable, Equatable { case operation, authorization, resourceBudget }
    public let message: String
    public let code: Code
    public init(_ message: String, code: Code = .operation) {
        self.message = message
        self.code = code
    }
    public var errorDescription: String? { message }
}

public struct GitRepositoryIdentity: Sendable, Equatable, Hashable {
    public let root: URL
    public let directory: URL
    public let commonDirectory: URL
    public let authorizedRoot: URL
    public let additionalAuthorizedDirectories: [URL]
    public var id: String { directory.path }
}

public struct GitStatusEntry: Sendable, Equatable, Identifiable, Hashable {
    public let path: String
    public let originalPath: String?
    public let indexStatus: Character
    public let worktreeStatus: Character
    public let headObject: String
    public let indexObject: String
    public let submodule: Bool
    public var id: String { path }
    public var untracked: Bool { indexStatus == "?" }
    public var conflicted: Bool {
        indexStatus == "U" || worktreeStatus == "U"
            || (indexStatus == "A" && worktreeStatus == "A")
            || (indexStatus == "D" && worktreeStatus == "D")
    }
    public var staged: Bool { !untracked && indexStatus != "." && indexStatus != " " }
    public var unstaged: Bool { !untracked && worktreeStatus != "." && worktreeStatus != " " }
    public var paths: [String] {
        originalPath.flatMap { indexStatus == "R" || worktreeStatus == "R" ? [$0, path] : nil } ?? [path]
    }
    public var label: String {
        if conflicted { return "冲突" }
        if submodule { return "子模块" }
        if untracked { return "未跟踪" }
        if indexStatus == "C" || worktreeStatus == "C" { return "复制" }
        if originalPath != nil { return "重命名" }
        let state = unstaged ? worktreeStatus : indexStatus
        switch state {
        case "A": return "新增"
        case "D": return "删除"
        case "T": return "类型变化"
        default: return "修改"
        }
    }
}

public struct GitStatusSnapshot: Sendable, Equatable {
    public let repository: GitRepositoryIdentity
    public let head: String?
    public let branch: String?
    public let upstream: String?
    public let ahead: Int?
    public let behind: Int?
    public let entries: [GitStatusEntry]
    public let indexDigest: String
    public let operation: String?
    public let capturedAt: Date
    public var branchTitle: String { branch ?? head.map { String($0.prefix(8)) + " · 分离 HEAD" } ?? "尚无提交" }
    public var hasConflicts: Bool { entries.contains(where: \.conflicted) }
}

public enum GitComparison: Sendable, Equatable, Hashable {
    case working, staged, unstaged
    case commit(String, parent: String?)
    case objects(left: String, right: String)
    public var key: String {
        switch self {
        case .working: "working"
        case .staged: "staged"
        case .unstaged: "unstaged"
        case .commit(let object, let parent): "commit:" + object + ":" + (parent ?? "root")
        case .objects(let left, let right): "objects:" + left + ":" + right
        }
    }
}

public struct GitDiffLocation: Hashable, Sendable {
    public let repositoryID: String
    public let path: String
    public let comparison: GitComparison
    public init(repositoryID: String, path: String, comparison: GitComparison) {
        self.repositoryID = repositoryID
        self.path = path
        self.comparison = comparison
    }
    public var key: String { repositoryID + "\0" + comparison.key + "\0" + path }
}

public struct GitDiffRow: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case context, added, removed, changed, header, note
        public var isChange: Bool { self == .added || self == .removed || self == .changed }
    }
    public let id: Int
    public let leftNumber: Int?
    public let rightNumber: Int?
    public let left: String?
    public let right: String?
    public let kind: Kind
    public let leftChange: Range<Int>?
    public let rightChange: Range<Int>?
}

public struct GitDiff: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let path: String
    public let comparison: GitComparison
    public let leftTitle: String
    public let rightTitle: String
    public let patch: String
    public let rows: [GitDiffRow]
    public let unifiedRows: [GitDiffRow]
    public let leftWidth: Double
    public let rightWidth: Double
    public let message: String?
    public let differenceRows: [Int]
    public let selection: GitSelection?
    /// Complete immutable source text, when it fits the text comparison budget.
    /// Never a writable document or a commit candidate.
    public var text: GitTextComparison? = nil
    public var editableWorkingText = false
}

/// The selection binds the displayed change to HEAD, the complete index and
/// selected disk objects. It is never a mutable second document buffer.
public struct GitSelection: Sendable, Equatable {
    public let path: String
    public let paths: [String]
    public let head: String?
    public let indexDigest: String
    public let diskDigests: [String: String]
    public let indexObject: String
    public let headObject: String
    public let bothLayersChanged: Bool
    public internal(set) var partial: GitPartialSelection? = nil
    public func sameRevision(as other: Self) -> Bool {
        path == other.path && paths == other.paths && head == other.head && indexDigest == other.indexDigest
            && diskDigests == other.diskDigests && indexObject == other.indexObject && headObject == other.headObject
            && bothLayersChanged == other.bothLayersChanged
    }
}

public struct GitReference: Sendable, Equatable, Identifiable {
    public let name: String
    public let object: String
    public let current: Bool
    public let upstream: String?
    public var id: String { name }
    public var remote: Bool { name.hasPrefix("refs/remotes/") }
    public var tag: Bool { name.hasPrefix("refs/tags/") }
    public var shortName: String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }
}

public struct GitCommit: Sendable, Equatable, Identifiable {
    public let object: String
    public let parents: [String]
    public let author: String
    public let email: String
    public let authoredAt: Date
    public let committer: String
    public let committerEmail: String
    public let committedAt: Date
    public let decorations: String
    public let message: String
    public var id: String { object }
    public var subject: String { message.components(separatedBy: .newlines).first ?? "" }
}

public struct GitHistoryQuery: Sendable, Equatable {
    public var reference: String?
    public var allReferences = false
    public var text = ""
    public var author = ""
    public var path = ""
    public var since: Date?
    public var until: Date?
    public init() {}
}

public struct GitHistoryPage: Sendable, Equatable {
    public let commits: [GitCommit]
    public let tips: [String]
    public let nextOffset: Int?
}

public struct GitCommitFile: Sendable, Equatable, Identifiable {
    public let path: String
    public let originalPath: String?
    public let status: String
    public var id: String { path }
}

public struct GitRemote: Sendable, Equatable, Identifiable {
    public let name: String
    public let fetchURL: String
    public let pushURL: String
    public var id: String { name }
}

public struct GitWriteResult: Sendable, Equatable {
    public let summary: String
    public let commit: String?
    public let workingTreeChanged: Bool
    public let detail: String
}

public enum GitFileAction: Sendable, Equatable {
    case stage, unstage, discardUnstaged, restoreHead
}

public struct GitPushPlan: Sendable, Equatable {
    public let head: String
    public let localBranch: String
    public let remote: String
    public let targetBranch: String
    public let setUpstream: Bool
    public let previousRemoteObject: String?
    public let commits: [GitCommit]
}
