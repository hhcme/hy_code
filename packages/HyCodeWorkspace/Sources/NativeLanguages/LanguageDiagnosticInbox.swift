import Foundation

/// Bounded latest-per-URI queue. Tickets survive dequeue so a newer event or
/// native edit invalidates an in-flight decode even at the same LSP version.
public struct LanguageDiagnosticInbox: Sendable {
    public struct Message: Sendable {
        public let uri: String
        public let version: Int?
        public let ticket: UUID
        public let values: [JSONValue]
    }
    private var pending: [String: Message] = [:]
    private var order: [String] = []
    private var tickets: [String: UUID] = [:]
    public init() {}
    public var count: Int { pending.count }
    @discardableResult public mutating func offer(uri: String, version: Int?, values: [JSONValue]) -> Bool {
        guard pending[uri] != nil || pending.count < 32, tickets[uri] != nil || tickets.count < 2000 else {
            return false
        }
        let ticket = UUID()
        if pending[uri] == nil { order.append(uri) }
        pending[uri] = Message(uri: uri, version: version, ticket: ticket, values: Array(values.prefix(1000)))
        tickets[uri] = ticket
        return true
    }
    public mutating func take() -> Message? {
        guard !order.isEmpty else { return nil }
        return pending.removeValue(forKey: order.removeFirst())
    }
    public func isCurrent(_ message: Message) -> Bool { tickets[message.uri] == message.ticket }
    public mutating func remove(_ uri: String) {
        tickets[uri] = nil
        pending[uri] = nil
        order.removeAll { $0 == uri }
    }
    public mutating func reset() {
        pending.removeAll()
        order.removeAll()
        tickets.removeAll()
    }
}
