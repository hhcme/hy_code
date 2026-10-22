import Foundation

public struct LSPSnippet: Sendable {
    public let text: String
    public let stops: [NSRange]
    public static func expand(_ source: String) throws -> Self {
        guard source.utf8.count <= 65_536 else { throw LanguageServiceFailure("补全模板过大") }
        var parser = Parser(input: Array(source))
        let result = try parser.parse(depth: 0, closing: false)
        let sorted = result.stops.sorted { a, b in
            let left = a.0 == 0 ? Int.max : a.0
            let right = b.0 == 0 ? Int.max : b.0
            return left == right ? a.1.location < b.1.location : left < right
        }
        return Self(text: result.text, stops: sorted.map(\.1))
    }
    private struct Segment {
        var text = ""
        var length = 0
        var stops: [(Int, NSRange)] = []
        mutating func append(_ value: String) {
            text += value
            length += value.utf16.count
        }
    }
    private struct Parser {
        let input: [Character]
        var offset = 0
        var defaults: [Int: String] = [:]
        mutating func parse(depth: Int, closing: Bool) throws -> Segment {
            guard depth <= 8 else { throw LanguageServiceFailure("补全模板嵌套过深") }
            var output = Segment()
            while offset < input.count {
                let char = input[offset]
                offset += 1
                if char == "}", closing { return output }
                if char == "\\", offset < input.count {
                    output.append(String(input[offset]))
                    offset += 1
                    continue
                }
                guard char == "$", offset < input.count else {
                    output.append(String(char))
                    continue
                }
                let braced = input[offset] == "{"
                if braced { offset += 1 }
                let began = offset
                let numeric = offset < input.count && input[offset].isNumber
                while offset < input.count
                    && (numeric
                        ? input[offset].isNumber
                        : (input[offset].isLetter || input[offset].isNumber || input[offset] == "_"))
                { offset += 1 }
                guard offset > began else { throw LanguageServiceFailure("补全模板占位符无效") }
                let name = String(input[began..<offset])
                let index = Int(name)
                var value = Segment()
                if braced {
                    guard offset < input.count else { throw LanguageServiceFailure("补全模板未闭合") }
                    if input[offset] == ":" {
                        offset += 1
                        value = try parse(depth: depth + 1, closing: true)
                    } else if input[offset] == "|" {
                        offset += 1
                        var choice = ""
                        var first = true
                        var ended = false
                        while offset < input.count {
                            let next = input[offset]
                            offset += 1
                            if next == "\\", offset < input.count {
                                if first { choice.append(input[offset]) }
                                offset += 1
                            } else if next == "|", offset < input.count, input[offset] == "}" {
                                offset += 1
                                ended = true
                                break
                            } else if next == "," {
                                first = false
                            } else if first {
                                choice.append(next)
                            }
                        }
                        guard ended else { throw LanguageServiceFailure("补全候选未闭合") }
                        value.append(choice)
                    } else if input[offset] == "}" {
                        offset += 1
                        value.append(index.flatMap { defaults[$0] } ?? "")
                    } else {
                        throw LanguageServiceFailure("此补全模板包含暂不支持的变换")
                    }
                } else {
                    value.append(index.flatMap { defaults[$0] } ?? "")
                }
                let start = output.length
                output.append(value.text)
                output.stops += value.stops.map {
                    ($0.0, NSRange(location: start + $0.1.location, length: $0.1.length))
                }
                if let index {
                    guard index >= 0, index <= 99 else { throw LanguageServiceFailure("补全占位符编号过大") }
                    defaults[index] = value.text
                    output.stops.append((index, NSRange(location: start, length: value.length)))
                }
                guard output.stops.count <= 200, output.length <= 65_536 else {
                    throw LanguageServiceFailure("补全模板超过预算")
                }
            }
            guard !closing else { throw LanguageServiceFailure("补全模板未闭合") }
            return output
        }
    }
}

public struct LSPSnippetSession {
    private var ranges: [NSRange]
    private var active = 0
    public init(ranges: [NSRange]) { self.ranges = ranges }
    public var current: NSRange? { ranges.indices.contains(active) ? ranges[active] : nil }
    public mutating func advance(backward: Bool, selection: NSRange) -> NSRange? {
        guard let range = current, selection.location >= range.location, NSMaxRange(selection) <= NSMaxRange(range)
        else {
            ranges = []
            return nil
        }
        let next = active + (backward ? -1 : 1)
        guard ranges.indices.contains(next) else {
            ranges = []
            return nil
        }
        active = next
        return ranges[next]
    }
    public mutating func replace(_ edit: NSRange, count: Int) {
        guard let range = current, edit.location >= range.location, NSMaxRange(edit) <= NSMaxRange(range) else {
            ranges = []
            return
        }
        let delta = count - edit.length
        for index in ranges.indices {
            let item = ranges[index]
            if index == active {
                ranges[index].length += delta
            } else if item.location >= NSMaxRange(edit) {
                ranges[index].location += delta
            } else if item.location <= edit.location && NSMaxRange(item) >= NSMaxRange(edit) {
                ranges[index].length += delta
            } else if NSMaxRange(item) > edit.location {
                ranges = []
                return
            }
        }
    }
}
