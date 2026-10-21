import Foundation

public struct WorkspaceEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case directory, file, symlink, other }
    public let name: String
    public let relativePath: String
    public let kind: Kind
    public let size: UInt64?
    public let modifiedMs: UInt64?
    public var id: String { relativePath }
    public var isDirectory: Bool { kind == .directory }
    public var projectRelativePath: String { relativePath.isEmpty ? "." : relativePath }

    /// Display/copy/reveal share one file-URL representation, including literal
    /// percent signs and Unicode. Supply the known kind to avoid a synchronous
    /// metadata probe. This does not grant, resolve, or canonicalize file access.
    public func url(relativeTo root: URL) -> URL {
        if relativePath.hasPrefix("/") { return URL(fileURLWithPath: relativePath, isDirectory: isDirectory) }
        return relativePath.isEmpty ? root : root.appendingPathComponent(relativePath, isDirectory: isDirectory)
    }

    public init(name: String, relativePath: String, kind: Kind, size: UInt64? = nil, modifiedMs: UInt64? = nil) {
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modifiedMs = modifiedMs
    }

    enum CodingKeys: String, CodingKey {
        case name, kind, size
        case relativePath = "relative_path"
        case modifiedMs = "modified_ms"
    }
}

public struct DirectorySnapshot: Decodable, Sendable {
    public let relativePath: String
    public let entries: [WorkspaceEntry]
    public let skipped: Int
    public let truncated: Bool
    enum CodingKeys: String, CodingKey {
        case entries, skipped, truncated
        case relativePath = "relative_path"
    }
}

public struct WorkspaceFailure: Error, Decodable, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
}
