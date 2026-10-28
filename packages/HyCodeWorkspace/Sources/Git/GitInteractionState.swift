import Foundation

public struct GitAmendTicket: Sendable, Equatable {
    fileprivate let id: UUID
    public let head: String
    public let messageRevision: UInt64
}

/// A default commit message is an asynchronous suggestion. It cannot replace
/// input typed since the request, or input belonging to a later amend action.
public struct GitAmendRequests: Sendable {
    private var active: GitAmendTicket?
    public init() {}
    public mutating func begin(head: String, messageRevision: UInt64) -> GitAmendTicket {
        let ticket = GitAmendTicket(id: UUID(), head: head, messageRevision: messageRevision)
        active = ticket
        return ticket
    }
    public mutating func cancel() { active = nil }
    public func accepts(_ ticket: GitAmendTicket, head: String?, messageRevision: UInt64) -> Bool {
        active == ticket && head == ticket.head && messageRevision == ticket.messageRevision
    }
}

/// Selection tasks can be superseded per path. An old batch completion must
/// neither reselect a cleared file nor remove a newer task's pending marker.
public struct GitSelectionRequests: Sendable {
    private var active: [String: UUID] = [:]
    public init() {}
    public var pending: Set<String> { Set(active.keys) }
    public mutating func begin(_ paths: [String]) -> UUID {
        let ticket = UUID()
        for path in paths { active[path] = ticket }
        return ticket
    }
    public func accepts(_ ticket: UUID, path: String) -> Bool { active[path] == ticket }
    public mutating func cancel(_ paths: [String]) { for path in paths { active[path] = nil } }
    public mutating func finish(_ ticket: UUID) { active = active.filter { $0.value != ticket } }
}
