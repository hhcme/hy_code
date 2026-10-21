import Foundation

public struct RecentProject: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public var bookmark: Data?
    public var id: String { path }
    public var name: String {
        let component = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return component.isEmpty ? path : component
    }
    public var initials: String {
        let parts = name.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " })
        return String((parts.count > 1 ? parts.prefix(2).compactMap(\.first) : Array(name.prefix(2)))).uppercased()
    }
    public var colorIndex: Int {
        Int(path.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 } % 6)
    }
    public init(path: String, bookmark: Data? = nil) {
        self.path = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        self.bookmark = bookmark
    }
}

/// Local switcher history; a remembered path is never an automatic access grant.
public struct RecentProjects: Codable, Equatable, Sendable {
    public private(set) var records: [RecentProject] = []
    public private(set) var startupPath: String?
    public var startupProject: RecentProject? { records.first { $0.path == startupPath } }
    public init() {}
    private enum CodingKeys: String, CodingKey { case records, startupPath }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = Array(try container.decode([RecentProject].self, forKey: .records).prefix(30))
        // Older versions only persisted MRU history. Migrate once; an explicit
        // null means the user closed the project and must survive round-trips.
        startupPath =
            container.contains(.startupPath)
            ? try container.decodeIfPresent(String.self, forKey: .startupPath) : records.first?.path
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
        try container.encode(startupPath, forKey: .startupPath)
    }
    public mutating func remember(_ project: RecentProject) {
        let old = records.first { $0.path == project.path }
        records.removeAll { $0.path == project.path }
        var project = project
        if project.bookmark == nil { project.bookmark = old?.bookmark }
        records.insert(project, at: 0)
        records = Array(records.prefix(30))
        startupPath = project.path
    }
    public mutating func closeWorkspace() { startupPath = nil }
    public mutating func updateBookmark(_ bookmark: Data, path: String) {
        if let index = records.firstIndex(where: { $0.path == path }) { records[index].bookmark = bookmark }
    }
}
