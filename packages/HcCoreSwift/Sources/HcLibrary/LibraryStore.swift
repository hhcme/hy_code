import Foundation

/// 库内一条文件记录。所有打开过的文件都会复制入库，本条目描述这份副本。
public struct RecentItem: Identifiable, Codable, Hashable {
    public var id: UUID
    /// 展示用名称（导入时的文件名）。
    public var name: String
    /// 副本在库内的相对路径（<uuid>/<文件名>）。
    public var relativePath: String
    public var addedAt: Date
    /// 来源：导入时的原始位置，按需求必须保留。
    public var sourcePath: String

    public init(id: UUID, name: String, relativePath: String, addedAt: Date, sourcePath: String) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.addedAt = addedAt
        self.sourcePath = sourcePath
    }
}

/// 内部文件库：负责把打开过的文件复制进应用沙盒内的库目录，并维护最近打开记录。
/// 记录全部存本地 JSON，数据层不设上限；界面层再按需取最近的若干条。
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var recents: [RecentItem] = []

    private let baseURL: URL

    private var indexURL: URL {
        baseURL.appendingPathComponent("index.json")
    }

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            baseURL = baseDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            baseURL = support.appendingPathComponent("HcFileViewer/Library", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        load()
    }

    public func url(for item: RecentItem) -> URL {
        baseURL.appendingPathComponent(item.relativePath)
    }

    /// 复制入库并记录为最近打开。fileImporter 给出的 URL 带安全作用域，需要临时授权访问。
    @discardableResult
    public func importFile(at sourceURL: URL) throws -> RecentItem {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let relativePath = "\(id.uuidString)/\(sourceURL.lastPathComponent)"
        let destination = baseURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let item = RecentItem(
            id: id,
            name: sourceURL.lastPathComponent,
            relativePath: relativePath,
            addedAt: .now,
            sourcePath: sourceURL.path
        )
        recents.insert(item, at: 0)
        try save()
        return item
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let items = try? decoder.decode([RecentItem].self, from: data) else { return }
        recents = items
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recents).write(to: indexURL, options: .atomic)
    }
}
