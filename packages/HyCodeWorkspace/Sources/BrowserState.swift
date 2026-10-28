import Foundation

public enum BrowserLocation: Hashable, Sendable {
    case directory(String)
    case file(WorkspaceEntry)
    case gitDiff(GitDiffLocation)

    public var path: String {
        switch self {
        case .directory(let path): path
        case .file(let entry): entry.relativePath
        case .gitDiff(let location): location.path
        }
    }
    public var isDirectory: Bool {
        if case .directory = self { return true }
        return false
    }
    public var isGitDiff: Bool {
        if case .gitDiff = self { return true }
        return false
    }
    public var documentPath: String? {
        switch self {
        case .file(let entry): return entry.relativePath
        case .gitDiff(let location):
            return location.comparison == .working || location.comparison == .unstaged ? location.path : nil
        case .directory: return nil
        }
    }
    public var tabIdentity: String {
        if case .gitDiff(let location) = self { return "git\0" + location.key }
        return (isDirectory ? "directory\0" : "file\0") + path
    }
    public var title: String { (isGitDiff ? "差异: " : "") + (path.split(separator: "/").last.map(String.init) ?? "项目") }
    public var parentDirectory: String? {
        if isDirectory && path.isEmpty { return nil }
        return path.split(separator: "/").dropLast().joined(separator: "/")
    }
    public func resolvingFile(in entries: [WorkspaceEntry]) -> BrowserLocation {
        guard case .file = self, let updated = entries.first(where: { $0.relativePath == path }) else { return self }
        return updated.isDirectory ? .directory(updated.relativePath) : .file(updated)
    }
}

public struct BrowserTab: Identifiable, Sendable {
    public let id: UUID
    public var location: BrowserLocation
    public var isPreview: Bool
}

public struct BrowserTabs: Sendable {
    public private(set) var tabs: [BrowserTab] = []
    public private(set) var activeID: UUID?
    public var active: BrowserTab? { tabs.first { $0.id == activeID } }
    public var documentPaths: Set<String> { Set(tabs.compactMap { $0.location.documentPath }) }
    public func retainsDocument(_ path: String, excluding id: UUID) -> Bool {
        tabs.contains { $0.id != id && $0.location.documentPath == path }
    }
    public mutating func pinDocument(_ path: String) {
        for index in tabs.indices where tabs[index].location.documentPath == path { tabs[index].isPreview = false }
    }
    public func fileTab(path: String) -> BrowserTab? {
        tabs.first { tab in
            if case .file(let entry) = tab.location { return entry.relativePath == path }
            return false
        }
    }
    public init() {}

    public mutating func open(_ location: BrowserLocation, preview: Bool) {
        // Directories belong to the project tree, never the central document tabs.
        guard !location.isDirectory else { return }
        if let index = tabs.firstIndex(where: {
            $0.location.tabIdentity == location.tabIdentity
        }) {
            tabs[index].location = location
            activeID = tabs[index].id
            if !preview { tabs[index].isPreview = false }
            return
        }
        let tab = BrowserTab(id: UUID(), location: location, isPreview: preview)
        if preview, let index = tabs.firstIndex(where: \.isPreview) { tabs[index] = tab } else { tabs.append(tab) }
        activeID = tab.id
    }

    public mutating func activate(_ id: UUID) {
        if tabs.contains(where: { $0.id == id }) { activeID = id }
    }
    public mutating func pin(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPreview = false
    }
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if activeID == id { activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
    }

    public mutating func updateFileMetadata(from entries: [WorkspaceEntry]) {
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0) })
        for index in tabs.indices {
            if case .file(let oldEntry) = tabs[index].location,
                let updated = byPath[oldEntry.relativePath], !updated.isDirectory
            {
                tabs[index].location = .file(updated)
            }
        }
    }
}

public struct NavigationHistory: Sendable {
    private var locations: [BrowserLocation] = []
    private var position = -1
    public var canGoBack: Bool { position > 0 }
    public var canGoForward: Bool { position + 1 < locations.count }
    public init() {}

    public mutating func visit(_ location: BrowserLocation) {
        if position >= 0, locations[position].tabIdentity == location.tabIdentity {
            locations[position] = location
            return
        }
        locations = Array(locations.prefix(position + 1))
        locations.append(location)
        if locations.count > 200 { locations.removeFirst() }
        position = locations.count - 1
    }
    public mutating func back() -> BrowserLocation? {
        guard canGoBack else { return nil }
        position -= 1
        return locations[position]
    }
    public mutating func forward() -> BrowserLocation? {
        guard canGoForward else { return nil }
        position += 1
        return locations[position]
    }
}
