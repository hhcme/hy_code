import Foundation

/// One row identity and order is shared by rendering, keyboard selection,
/// hover hit-testing and actions, including the two appearances of an MM file.
public struct GitChangeListRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let entry: GitStatusEntry?
    public let staged: Bool
    public let expanded: Bool

    public static func ordered(_ entries: [GitStatusEntry], grouping: Bool = false) -> [GitStatusEntry] {
        let locale = Locale(identifier: "en_US_POSIX")
        let prepared = entries.map { entry in
            (
                entry: entry, name: (entry.path as NSString).lastPathComponent.lowercased(with: locale),
                directory: (entry.path as NSString).deletingLastPathComponent
            )
        }
        return prepared.sorted { a, b in
            if grouping, a.directory != b.directory { return a.directory < b.directory }
            let order = a.name.compare(b.name, options: .numeric, locale: locale)
            return order == .orderedSame
                ? a.entry.path.utf8.lexicographicallyPrecedes(b.entry.path.utf8)
                : order == .orderedAscending
        }.map(\.entry)
    }
    public static func reviewPaths(_ entries: [GitStatusEntry], path: String, grouping: Bool = false) -> [String] {
        let untracked = entries.first { $0.path == path }?.untracked == true
        return ordered(entries.filter { $0.untracked == untracked }, grouping: grouping).map(\.path)
    }
    public static func make(
        entries: [GitStatusEntry], stagedMode: Bool, grouping: Bool,
        collapsed: Set<String>, expanded: Bool
    ) -> [Self] {
        let entries = ordered(entries, grouping: grouping && !stagedMode)
        func files(_ entries: [GitStatusEntry], staged: Bool) -> [Self] {
            entries.map {
                Self(
                    id: (staged ? "index\0" : "work\0") + $0.path, title: nil, entry: $0,
                    staged: staged, expanded: false)
            }
        }
        func section(_ id: String, _ title: String, _ entries: [GitStatusEntry], staged: Bool) -> [Self] {
            let open = !collapsed.contains(id)
            return [Self(id: id, title: "\(title) · \(entries.count)", entry: nil, staged: staged, expanded: open)]
                + (open ? files(entries, staged: staged) : [])
        }
        if stagedMode {
            return section("staged", "已暂存", entries.filter(\.staged), staged: true)
                + section("unstaged", "未暂存", entries.filter { $0.unstaged || $0.untracked }, staged: false)
        }
        let tracked = entries.filter { !$0.untracked }
        let untracked = entries.filter(\.untracked)
        var result: [Self] = []
        if expanded {
            if grouping {
                let groups = Dictionary(grouping: tracked) { ($0.path as NSString).deletingLastPathComponent }
                result = groups.keys.sorted().flatMap { directory in
                    section(
                        "directory\0" + directory, directory.isEmpty ? "项目根目录" : directory,
                        groups[directory] ?? [], staged: false)
                }
            } else {
                result = files(tracked, staged: false)
            }
        }
        if !untracked.isEmpty {
            result += section("untracked", "未进行版本管理的文件", untracked, staged: false)
        }
        return result
    }
}
