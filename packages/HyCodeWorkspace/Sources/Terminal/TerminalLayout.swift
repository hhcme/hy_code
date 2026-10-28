import Foundation

public enum TerminalSplitAxis: String, Codable, Sendable { case horizontal, vertical }

public indirect enum TerminalSplitLayout: Equatable, Sendable {
    case pane(UUID)
    case split(TerminalSplitAxis, TerminalSplitLayout, TerminalSplitLayout)

    public var panes: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .split(_, let first, let second): first.panes + second.panes
        }
    }
    func splitting(_ id: UUID, with new: UUID, axis: TerminalSplitAxis) -> Self {
        switch self {
        case .pane(let existing): existing == id ? .split(axis, self, .pane(new)) : self
        case .split(let direction, let first, let second):
            .split(direction, first.splitting(id, with: new, axis: axis), second.splitting(id, with: new, axis: axis))
        }
    }
    func removing(_ id: UUID) -> Self? {
        switch self {
        case .pane(let existing): existing == id ? nil : self
        case .split(let axis, let first, let second):
            switch (first.removing(id), second.removing(id)) {
            case (nil, let other), (let other, nil): other
            case (let a?, let b?): .split(axis, a, b)
            }
        }
    }
}

public struct TerminalTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public private(set) var layout: TerminalSplitLayout
    public private(set) var activePane: UUID
    public init(title: String) {
        id = UUID()
        self.title = title
        activePane = UUID()
        layout = .pane(activePane)
    }
    public mutating func select(_ pane: UUID) {
        if layout.panes.contains(pane) { activePane = pane }
    }
    @discardableResult public mutating func split(_ axis: TerminalSplitAxis) -> UUID? {
        guard layout.panes.count < 4 else { return nil }
        let id = UUID()
        layout = layout.splitting(activePane, with: id, axis: axis)
        activePane = id
        return id
    }
    /// Returns false when the tab's last pane was removed; the owner removes the tab.
    @discardableResult public mutating func remove(_ pane: UUID) -> Bool {
        guard let next = layout.removing(pane) else { return false }
        layout = next
        if activePane == pane { activePane = next.panes[0] }
        return true
    }
}
