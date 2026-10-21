import Foundation

public struct DartHoverDefinition: Sendable {
    public let targets: [LSPLocation]
    public let complete: Bool
    public init(_ targets: [LSPLocation]) {
        self.targets = Array(targets.prefix(32))
        complete = targets.count <= 32
    }
}
public struct DartHoverEntry: Sendable {
    public var content: DartHoverContent?
    public var definition: DartHoverDefinition?
    public init(content: DartHoverContent? = nil, definition: DartHoverDefinition? = nil) {
        self.content = content
        self.definition = definition
    }
}

/// One active worker and one latest desired symbol. Pointer changes within a
/// symbol do not reset dwell or requests. Sixteen revision/context-bound LRU
/// entries include negative results, so moving back does not repeat SDK work.
public struct DartHoverState {
    public struct Request: Sendable, Equatable {
        public let serial: UInt64
        public let context: UInt64
        public let range: NSRange
    }
    public private(set) var target: NSRange?
    public private(set) var active: Request?
    public private(set) var context: UInt64 = 0
    private var serial: UInt64 = 0
    private var cache: [NSRange: DartHoverEntry] = [:]
    private var order: [NSRange] = []
    public init() {}
    public mutating func reset(context: UInt64) {
        self.context = context
        target = nil
        serial &+= 1
        cache.removeAll()
        order.removeAll()
        // The cancelled worker retains its slot until it actually finishes.
    }
    @discardableResult public mutating func move(to range: NSRange?, expedite: Bool = false) -> Bool {
        guard target != range || expedite else { return false }
        target = range
        serial &+= 1
        return true
    }
    public mutating func entry(for range: NSRange) -> DartHoverEntry? {
        guard let entry = cache[range] else { return nil }
        order.removeAll { $0 == range }
        order.append(range)
        return entry
    }
    public mutating func begin() -> Request? {
        guard active == nil, let range = target else { return nil }
        let request = Request(serial: serial, context: context, range: range)
        active = request
        return request
    }
    public func isCurrent(_ request: Request) -> Bool {
        request.context == context && request.serial == serial && request.range == target
    }
    public mutating func store(_ entry: DartHoverEntry, for request: Request) {
        guard request.context == context else { return }
        cache[request.range] = entry
        order.removeAll { $0 == request.range }
        order.append(request.range)
        while order.count > 16 { cache[order.removeFirst()] = nil }
    }
    /// True means a newer pointer/context target needs service. A→B→A still
    /// reschedules after a cancelled A worker, even though the range matches.
    @discardableResult public mutating func finish(_ request: Request) -> Bool {
        guard active == request else { return false }
        active = nil
        return target != nil && !isCurrent(request)
    }
}
