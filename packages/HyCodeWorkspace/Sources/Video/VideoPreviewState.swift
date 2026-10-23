import Foundation

public enum VideoPreviewFormat {
    public static func matches(_ path: String) -> Bool {
        ["mp4", "mov", "m4v"].contains((path as NSString).pathExtension.lowercased())
    }
}

/// One seek in flight; intermediate drag positions are superseded. Completion
/// must belong to the same document generation before calling complete().
public struct VideoPreviewSeek: Sendable {
    public private(set) var inFlight: Double?
    public private(set) var pending: Double?
    public init() {}
    public mutating func request(_ seconds: Double, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, seconds.isFinite else { return nil }
        let target = min(duration, max(0, seconds))
        if inFlight != nil {
            pending = target
            return nil
        }
        inFlight = target
        return target
    }
    public mutating func complete() -> Double? {
        let previous = inFlight
        inFlight = nil
        guard let target = pending else { return nil }
        pending = nil
        guard target != previous else { return nil }
        inFlight = target
        return target
    }
}

public enum VideoPreviewTime {
    public static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 360_000_000 else { return "—:—" }
        let value = Int(seconds)
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
