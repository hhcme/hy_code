import Foundation

/// Incremental package:test JSON reporter projection. Output text is owned by
/// the separate bounded console; this retains at most 1,000 test summaries.
public struct FlutterTestResults: Sendable {
    public struct Item: Sendable, Identifiable {
        public let id: Int
        public var name: String
        public var status: String
        public var error = ""
    }
    public private(set) var items: [Int: Item] = [:]
    public private(set) var done = false
    public private(set) var success = false
    public private(set) var limited = false
    private var line = ""
    private var discardLine = false
    public init() {}
    public mutating func append(_ chunk: String) {
        let parts = chunk.components(separatedBy: "\n")
        for (index, part) in parts.enumerated() {
            if !discardLine, line.utf8.count + part.utf8.count <= 65_536 {
                line += part
            } else {
                limited = true
                discardLine = true
                line = ""
            }
            if index < parts.count - 1 {
                if !discardLine, let event = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) {
                    receive(event)
                }
                line = ""
                discardLine = false
            }
        }
    }
    public mutating func receive(_ event: JSONValue) {
        switch event["type"].string {
        case "testStart":
            guard let id = event["test"]["id"].int, items.count < 1_000 else {
                limited = true
                return
            }
            items[id] = Item(id: id, name: String((event["test"]["name"].string ?? "测试").prefix(2_000)), status: "运行中")
        case "testDone":
            guard let id = event["testID"].int, var item = items[id] else { return }
            item.status = event["skipped"] == .bool(true) ? "跳过" : event["result"].string == "success" ? "通过" : "失败"
            items[id] = item
        case "error":
            guard let id = event["testID"].int, var item = items[id] else { return }
            item.error = String((event["error"].string ?? "").prefix(4_000))
            items[id] = item
        case "done":
            done = true
            success = event["success"] == .bool(true)
        default: break
        }
    }
}

public enum FlutterInspectorTree {
    public struct Row: Sendable, Identifiable {
        public let id: String
        public let valueID: String
        public let label: String
        public let depth: Int
        public let source: LSPLocation?
        public let generation: UUID
    }
    public static func rows(_ response: JSONValue, generation: UUID = UUID()) -> [Row] {
        var result: [Row] = []
        func walk(_ value: JSONValue, key: String, depth: Int) {
            guard depth < 32, result.count < 2_000, case .object = value else { return }
            let location = value["creationLocation"]
            let file = location["file"].string.flatMap(URL.init(string:))
            let line = location["line"].int ?? 0
            let column = location["column"].int ?? 0
            let position = LSPPosition(line: max(0, line - 1), character: max(0, column - 1))
            let source =
                file?.isFileURL == true && line > 0
                ? LSPLocation(uri: file!.absoluteString, range: LSPRange(start: position, end: position)) : nil
            result.append(
                Row(
                    id: key, valueID: String((value["valueId"].string ?? "").prefix(2_000)),
                    label: String((value["description"].string ?? value["name"].string ?? "Widget").prefix(2_000)),
                    depth: depth, source: source, generation: generation))
            for (index, child) in value["children"].array.prefix(2_000).enumerated() {
                walk(child, key: key + "/\(index)", depth: depth + 1)
            }
        }
        let body = response["result"] == .null ? response : response["result"]
        walk(body, key: "root", depth: 0)
        return result
    }
}

extension FlutterBreakpoint {
    /// Conservative line relocation for unsaved protocol deltas. Breakpoints
    /// inside removed lines collapse to the first line, with duplicates removed.
    public static func relocate(_ values: [Self], range: LSPRange, text: String) -> [Self] {
        let added = TextLineIndex(text, unicodeLineSeparators: false).count - 1
        let start = range.start.line + 1
        let end = range.end.line + 1
        var seen = Set<Int>()
        return values.compactMap { value in
            var value = value
            if value.line > end || (value.line == end && range.end.character == 0) {
                value.line += added - (end - start)
            } else if value.line > start {
                value.line = start
            }
            return seen.insert(value.line).inserted ? value : nil
        }.sorted { $0.line < $1.line }
    }
}
