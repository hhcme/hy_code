/// Main-thread reservations bridge the time between accepting native input and
/// its serialized Rust acknowledgement. An older response cannot grant capacity
/// already reserved by newer typing. This model contains no text or UI objects.
public struct LargeEditBudget {
    public private(set) var bytes: Int
    public private(set) var pieces: Int
    public var hasPendingEdits: Bool { !pending.isEmpty }
    private var pending: [UInt64: Int] = [:]
    private var acknowledged: UInt64 = 0
    public init(bytes: Int, pieces: Int) {
        self.bytes = bytes
        self.pieces = pieces
    }
    public func permits(bytes: Int) -> Bool { bytes >= 0 && bytes <= self.bytes && pieces >= 3 }
    public mutating func reserve(revision: UInt64, bytes: Int) {
        pending[revision] = bytes
        self.bytes -= bytes
        pieces -= 3
    }
    public mutating func acknowledge(bytes: Int, pieces: Int, revision: UInt64) {
        guard revision >= acknowledged else { return }
        acknowledged = revision
        pending = pending.filter { $0.key > revision }
        self.bytes = max(0, bytes - pending.values.reduce(0, +))
        self.pieces = max(0, pieces - pending.count * 3)
    }
}
