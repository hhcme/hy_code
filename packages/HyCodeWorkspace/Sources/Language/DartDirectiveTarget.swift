import Foundation

/// A bounded lexical hit-test, not a URI resolver. Only the analyzer can confirm
/// that a directive denotes a library. Ordinary strings keep identifier hits.
public enum DartDirectiveTarget {
    public static func range(at offset: Int, in source: NSString, lines: TextLineIndex) -> NSRange? {
        guard offset >= 0, offset < source.length else { return nil }
        let current = lines.line(at: offset)
        var first = max(0, current - 16)
        while first < current && offset - lines.start(of: first) >= 8_192 { first += 1 }
        let start = lines.start(of: first)
        guard offset - start < 8_192 else { return nil }
        // One forward pass skips comments/strings and visits at most 8,192
        // units total, including when many earlier lines contain directives.
        var scanner = Scanner(source: source, index: start, end: min(source.length, start + 8_192))
        while scanner.index <= offset && scanner.index < scanner.end {
            scanner.trivia()
            guard scanner.index <= offset && scanner.index < scanner.end else { break }
            let before = scanner.index
            if let range = scanner.directive(at: offset) { return range }
            if scanner.index == before { scanner.token() }
        }
        // A truncated window may begin inside an older block comment or string.
        // Retry line-local directive candidates with one additional shared 8K
        // budget, so unknown prefix state cannot swallow a later real import.
        // As always, these candidates require an analyzer-confirmed definition.
        if first > 0 {
            var remaining = 8_192
            for line in stride(from: current, through: first, by: -1) {
                let begin = lines.start(of: line)
                var candidate = Scanner(source: source, index: begin, end: min(source.length, begin + remaining))
                candidate.trivia()
                if candidate.unit() == 42 && candidate.unit(1) == 47 {
                    candidate.index += 2
                    candidate.trivia()
                }
                if let range = candidate.directive(at: offset) { return range }
                remaining -= max(1, candidate.index - begin)
                if remaining <= 0 { break }
            }
        }
        return nil
    }
    private struct Scanner {
        let source: NSString
        var index: Int
        let end: Int
        func unit(_ distance: Int = 0) -> unichar {
            index + distance < end ? source.character(at: index + distance) : 0
        }
        func identifier(_ value: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(value) else { return (0xd800...0xdfff).contains(value) }
            return value == 95 || value == 36 || CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.nonBaseCharacters.contains(scalar)
        }
        mutating func directive(at offset: Int) -> NSRange? {
            guard word("import") || word("export") || word("part") else { return nil }
            trivia()
            if word("of") { trivia() }
            while let uri = literal() {
                if NSLocationInRange(offset, uri) { return uri }
                trivia()
                guard word("if") else { break }
                trivia()
                guard condition() else { break }
                trivia()
            }
            return nil
        }
        mutating func token() {
            let raw = unit() == 114 && [39, 34].contains(unit(1))
            let quote = raw ? unit(1) : unit()
            if quote == 39 || quote == 34 {
                if raw { index += 1 }
                let triple = unit(1) == quote && unit(2) == quote
                index += triple ? 3 : 1
                while index < end {
                    if !triple && [10, 13].contains(unit()) { break }
                    if unit() == quote && (!triple || (unit(1) == quote && unit(2) == quote)) {
                        index += triple ? 3 : 1
                        break
                    }
                    index += unit() == 92 && !raw ? 2 : 1
                }
            } else if identifier(unit()) {
                repeat { index += 1 } while index < end && identifier(unit())
            } else {
                index += 1
            }
        }
        mutating func trivia() {
            while index < end {
                if [9, 10, 13, 32].contains(unit()) {
                    index += 1
                    continue
                }
                if unit() == 47 && unit(1) == 47 {
                    while index < end && ![10, 13].contains(unit()) { index += 1 }
                } else if unit() == 47 && unit(1) == 42 {
                    index += 2
                    var depth = 1
                    while index < end && depth > 0 {
                        if unit() == 47 && unit(1) == 42 {
                            depth += 1
                            index += 2
                        } else if unit() == 42 && unit(1) == 47 {
                            depth -= 1
                            index += 2
                        } else {
                            index += 1
                        }
                    }
                } else {
                    break
                }
            }
        }
        mutating func word(_ text: StaticString) -> Bool {
            text.withUTF8Buffer { bytes in
                guard index + bytes.count < end else { return false }
                for (position, byte) in bytes.enumerated() where unit(position) != unichar(byte) { return false }
                guard !identifier(unit(bytes.count)) else { return false }
                index += bytes.count
                return true
            }
        }
        mutating func literal() -> NSRange? {
            let raw = unit() == 114
            let quote = raw ? unit(1) : unit()
            guard quote == 39 || quote == 34 else { return nil }
            if raw { index += 1 }
            guard unit(1) != quote || unit(2) != quote else { return nil }
            index += 1
            let start = index
            while index < end {
                let value = unit()
                if value == quote {
                    let range = NSRange(location: start, length: index - start)
                    index += 1
                    return range.length > 0 ? range : nil
                }
                guard value != 10 && value != 13 && (raw || value != 36) else { return nil }
                index += value == 92 && !raw ? 2 : 1
            }
            return nil
        }
        mutating func condition() -> Bool {
            guard unit() == 40 else { return false }
            index += 1
            var depth = 1
            while index < end {
                trivia()
                if unit() == 39 || unit() == 34 || unit() == 114 {
                    // A string in a conditional comparison is not a library URI.
                    let before = index
                    if literal() != nil { continue }
                    index = before
                }
                if unit() == 40 { depth += 1 }
                if unit() == 41 { depth -= 1 }
                index += 1
                if depth == 0 { return true }
            }
            return false
        }
    }
}
