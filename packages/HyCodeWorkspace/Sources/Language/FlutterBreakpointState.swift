import Foundation

/// Disk-line baseline and the current unsaved projection have one owner. Only
/// successful saves commit a projection; discard restores the last disk lines.
public struct FlutterBreakpointStore: Sendable {
    public private(set) var projected: [String: [FlutterBreakpoint]]
    public private(set) var persisted: [String: [FlutterBreakpoint]]
    public private(set) var dirty: Set<String> = []
    public init(saved: [String: [FlutterBreakpoint]] = [:]) {
        projected = saved
        persisted = saved
    }
    public mutating func set(_ values: [FlutterBreakpoint], path: String) {
        projected[path] = values.isEmpty ? nil : values
        if !dirty.contains(path) { persisted[path] = projected[path] }
    }
    public mutating func edit(path: String, range: LSPRange, text: String) {
        dirty.insert(path)
        if let values = projected[path] {
            projected[path] = FlutterBreakpoint.relocate(values, range: range, text: text)
        }
    }
    public mutating func saved(path: String, snapshot: [FlutterBreakpoint], clean: Bool) {
        let values = clean ? (projected[path] ?? []) : snapshot
        persisted[path] = values.isEmpty ? nil : values
        if clean { dirty.remove(path) }
    }
    public mutating func discard(path: String) {
        projected[path] = persisted[path]
        dirty.remove(path)
    }
}

public struct FlutterBreakpointResolution: Sendable {
    public struct Entry: Sendable {
        public let path: String
        public let requested: Int
        public var actual: Int
        public var verified: Bool
        public var json: JSONValue {
            JSONValue(["path": path, "requested": requested, "actual": actual, "verified": verified])
        }
    }
    public private(set) var entries: [Int: Entry] = [:]
    private var pending: [Int: JSONValue] = [:]
    public init() {}
    public mutating func response(path: String, requested: [FlutterBreakpoint], result: JSONValue) {
        entries = entries.filter { $0.value.path != path }
        for (value, wanted) in zip(result["breakpoints"].array.prefix(1_000), requested.filter(\.enabled)) {
            guard let id = value["id"].int, entries.count < 1_000 else { continue }
            let line = value["line"].int ?? wanted.line
            entries[id] = Entry(
                path: path, requested: wanted.line, actual: line, verified: value["verified"] == .bool(true))
            if let event = pending.removeValue(forKey: id) { receive(event) }
        }
    }
    public mutating func receive(_ event: JSONValue) {
        guard let id = event["body"]["breakpoint"]["id"].int else { return }
        guard var value = entries[id] else {
            if pending.count < 1_000 {
                let point = event["body"]["breakpoint"]
                pending[id] = JSONValue([
                    "body": [
                        "reason": String((event["body"]["reason"].string ?? "").prefix(32)),
                        "breakpoint": [
                            "id": id, "line": point["line"].int ?? 0, "verified": point["verified"] == .bool(true),
                        ],
                    ]
                ])
            }
            return
        }
        let point = event["body"]["breakpoint"]
        value.verified = event["body"]["reason"].string != "removed" && point["verified"] == .bool(true)
        if let line = point["line"].int, line > 0, line <= 10_000_000 { value.actual = line }
        entries[id] = value
    }
    public var snapshot: JSONValue { .array(entries.keys.sorted().compactMap { entries[$0]?.json }) }
}
