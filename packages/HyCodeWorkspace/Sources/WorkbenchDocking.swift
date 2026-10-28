import Foundation

public enum WorkbenchCorner: String, CaseIterable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    public var isLeading: Bool { self == .topLeading || self == .bottomLeading }
    public var isTop: Bool { self == .topLeading || self == .topTrailing }
}

public enum WorkbenchTool: String, CaseIterable, Identifiable, Sendable {
    case project, search, structure, commit, git, terminal, debug, analysis, problems, information, openTabs, workspace,
        codex
    public var id: String { rawValue }
}

/// Sole owner of tool placement, ordering and selection. Every tool has exactly one
/// home; one selected tool per corner is visible, and nil means that corner is closed.
public struct WorkbenchDocking: Equatable, Sendable {
    public private(set) var groups: [WorkbenchCorner: [WorkbenchTool]] = [
        .topLeading: [.project, .search, .structure, .commit],
        .topTrailing: [.codex, .information, .analysis],
        .bottomLeading: [.git, .terminal, .debug, .problems],
        .bottomTrailing: [.openTabs, .workspace],
    ]
    public private(set) var active: [WorkbenchCorner: WorkbenchTool] = [.topLeading: .project, .topTrailing: .codex]
    public init() {}

    public func corner(of tool: WorkbenchTool) -> WorkbenchCorner? {
        WorkbenchCorner.allCases.first { groups[$0, default: []].contains(tool) }
    }
    public func isVisible(_ tool: WorkbenchTool) -> Bool { active.values.contains(tool) }
    public mutating func toggle(_ tool: WorkbenchTool) {
        guard let corner = corner(of: tool) else { return }
        active[corner] = active[corner] == tool ? nil : tool
    }
    public mutating func hide(_ tool: WorkbenchTool) {
        guard let corner = corner(of: tool), active[corner] == tool else { return }
        active[corner] = nil
    }

    /// Index is an insertion slot in the destination's original order. Reordering
    /// preserves selection. An open tool carries its panel to the new corner;
    /// moving an inactive button does not open or replace a panel.
    public mutating func move(_ tool: WorkbenchTool, to corner: WorkbenchCorner, at index: Int) {
        guard let source = self.corner(of: tool), let oldIndex = groups[source]?.firstIndex(of: tool) else { return }
        let wasActive = active[source] == tool
        let slot = min(max(0, index), groups[corner, default: []].count)
        groups[source]?.remove(at: oldIndex)
        let insertion = source == corner && slot > oldIndex ? slot - 1 : slot
        groups[corner, default: []].insert(tool, at: min(insertion, groups[corner, default: []].count))
        if source != corner, wasActive {
            active[source] = nil
            active[corner] = tool
        }
    }

    public var visibility: WorkbenchVisibility {
        WorkbenchVisibility(
            project: active[.topLeading] != nil, information: active[.topTrailing] != nil,
            openTabs: active[.bottomLeading] != nil, workspace: active[.bottomTrailing] != nil)
    }
}
