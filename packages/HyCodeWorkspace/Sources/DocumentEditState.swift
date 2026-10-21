import Foundation

public struct DocumentEditState: Sendable {
    public private(set) var revision: UInt64 = 0
    public private(set) var savedRevision: UInt64 = 0
    public var isDirty: Bool { revision != savedRevision }
    public init() {}
    public mutating func edited() { revision += 1 }
    public mutating func saved(_ version: UInt64) {
        // A save that finishes after newer typing only acknowledges its own text.
        if version <= revision { savedRevision = max(savedRevision, version) }
    }
}
