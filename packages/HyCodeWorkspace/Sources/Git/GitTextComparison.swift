import Foundation

/// TextKit presents each real source continuously. Projected row correspondence
/// is metadata for blocks/scrolling, never padding in text or paragraph layout.
public struct GitTextComparison: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public let offset: Int
        public let row: Int
        public let gapBefore: Int
        public let kind: GitDiffRow.Kind
        public let backgroundKind: GitDiffRow.Kind
        public let change: Range<Int>?
    }
    public struct Side: Sendable, Equatable {
        public let text: String
        public let lines: [Line]
        public let index: TextLineIndex
        public let length: Int
        init(text: String, lines: [Line]) {
            self.text = text
            self.lines = lines
            index = TextLineIndex(text)
            length = text.utf16.count
        }
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.lines == rhs.lines
        }
        public func line(at offset: Int) -> Int {
            var low = 0
            var high = lines.count
            while low < high {
                let middle = (low + high) / 2
                if lines[middle].offset <= offset { low = middle + 1 } else { high = middle }
            }
            return max(0, low - 1)
        }
        public func characterRange(lines: Range<Int>) -> NSRange? {
            guard lines.lowerBound >= 0, lines.upperBound <= index.count else { return nil }
            let start = lines.lowerBound == index.count ? length : index.start(of: lines.lowerBound)
            let end = lines.upperBound == index.count ? length : index.start(of: lines.upperBound)
            return NSRange(location: start, length: end - start)
        }
    }
    public let left: Side
    public let right: Side
    public let rowCount: Int
    public let blocks: [GitDiffBlock]

    /// Selectable read-only representation for compact/unified patches. It is
    /// explicitly not a source document and is never attached for editing.
    public static func projection(_ rows: [GitDiffRow], left: Bool, unified: Bool) -> Side {
        var text = ""
        var lines: [Line] = []
        var offset = 0
        for (index, row) in rows.enumerated() {
            let value = unified ? row.left ?? row.right ?? "" : (left ? row.left : row.right) ?? ""
            let prefix = unified ? row.kind == .added ? "+ " : row.kind == .removed ? "− " : "  " : ""
            lines.append(
                Line(offset: offset, row: index, gapBefore: 0, kind: row.kind, backgroundKind: row.kind, change: nil))
            let part = prefix + value + "\n"
            text += part
            offset += part.utf16.count
        }
        lines.append(
            Line(offset: offset, row: rows.count, gapBefore: 0, kind: .context, backgroundKind: .context, change: nil))
        return Side(text: text, lines: lines)
    }

    static func decode(_ bytes: Data) throws -> String {
        let content = bytes.starts(with: [0xef, 0xbb, 0xbf]) ? bytes.dropFirst(3) : bytes
        guard bytes.count <= 8_388_608, String(data: content, encoding: .utf8) != nil else {
            throw GitFailure("此版本不在 UTF-8 文本差异预算内，可打开源文件", code: .resourceBudget)
        }
        let value = String(decoding: content, as: UTF8.self)
        guard !value.contains("\0") else { throw GitFailure("二进制内容不提供文本比较") }
        return value
    }

    static func make(left: String, right: String, rows: [GitDiffRow]) throws -> Self {
        guard left.utf8.count + right.utf8.count <= 8_388_608 else {
            throw GitFailure("比较输入合计超过 8 MiB", code: .resourceBudget)
        }
        guard !rows.contains(where: { $0.kind == .header }) else {
            throw GitFailure("当前为省略上下文的差异，只读显示；请打开源文件编辑", code: .resourceBudget)
        }
        var sourceRows = rows.filter { $0.kind != .note }
        if sourceRows.isEmpty, left.utf8.elementsEqual(right.utf8) {
            sourceRows = try split(left).enumerated().map { index, text in
                GitDiffRow(
                    id: index, leftNumber: index + 1, rightNumber: index + 1, left: text, right: text,
                    kind: .context, leftChange: nil, rightChange: nil)
            }
        }
        guard sourceRows.count <= 20_000 else { throw GitFailure("文本比较超过 20,000 行", code: .resourceBudget) }
        let count = sourceRows.count + 1  // TextKit's final empty paragraph / blank baseline.
        let blocks = GitDiffBlock.make(sourceRows)
        func side(_ text: String, left: Bool) throws -> Side {
            let parts = try split(text)
            var lines: [Line] = []
            var offset = 0
            var previous = -1
            var blockIndex = 0
            for (rowIndex, row) in sourceRows.enumerated() {
                guard let number = left ? row.leftNumber : row.rightNumber else { continue }
                let raw = left ? row.left : row.right
                let stripBOM =
                    number == 1 && raw?.hasPrefix("\u{feff}") == true
                    && parts.indices.contains(number - 1) && raw?.utf8.elementsEqual(parts[number - 1].utf8) != true
                let value = stripBOM ? String(raw!.dropFirst()) : raw
                guard number == lines.count + 1, parts.indices.contains(number - 1),
                    value?.utf8.elementsEqual(parts[number - 1].utf8) == true
                else {
                    throw GitFailure("差异行与完整文本不一致，请刷新后审查")
                }
                // Bare CR / Unicode separators create different TextKit lines;
                // keep their bounded projection read-only rather than mis-map edits.
                let part = parts[number - 1]
                let hasLF = number < parts.count || text.hasSuffix("\n")
                let body = hasLF && part.hasSuffix("\r") ? String(part.dropLast()) : part
                guard !body.contains("\r"), !body.contains("\u{85}"), !body.contains("\u{2028}"),
                    !body.contains("\u{2029}")
                else {
                    throw GitFailure("此换行格式使用只读差异；请打开源文件编辑")
                }
                let rawChange = left ? row.leftChange : row.rightChange
                let shift = stripBOM ? 1 : 0
                let change = rawChange.map { max(0, $0.lowerBound - shift)..<max(0, $0.upperBound - shift) }
                while blockIndex < blocks.count,
                    (left ? blocks[blockIndex].left : blocks[blockIndex].right).upperBound <= number - 1
                {
                    blockIndex += 1
                }
                let backgroundKind =
                    blockIndex < blocks.count
                        && (left ? blocks[blockIndex].left : blocks[blockIndex].right).contains(number - 1)
                    ? blocks[blockIndex].kind : row.kind
                lines.append(
                    Line(
                        offset: offset, row: rowIndex, gapBefore: rowIndex - previous - 1,
                        kind: row.kind, backgroundKind: backgroundKind, change: change))
                offset += part.utf16.count + 1
                previous = rowIndex
            }
            guard lines.count == parts.count else { throw GitFailure("差异没有覆盖完整文本") }
            if text.isEmpty || text.hasSuffix("\n") {
                lines.append(
                    Line(
                        offset: text.utf16.count, row: count - 1, gapBefore: count - previous - 2,
                        kind: .context, backgroundKind: .context, change: nil))
            }
            return Side(text: text, lines: lines)
        }
        return try Self(
            left: side(left, left: true), right: side(right, left: false), rowCount: count,
            blocks: blocks)
    }

    private static func split(_ text: String) throws -> [String] {
        if text.isEmpty { return [] }
        var count = 0
        for byte in text.utf8 where byte == 10 {
            count += 1
            guard count <= 20_000 else { throw GitFailure("文本比较超过 20,000 行", code: .resourceBudget) }
        }
        guard count + (text.hasSuffix("\n") ? 0 : 1) <= 20_000 else {
            throw GitFailure("文本比较超过 20,000 行", code: .resourceBudget)
        }
        var parts = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { parts.removeLast() }
        guard parts.allSatisfy({ $0.utf16.count <= 16_384 }) else {
            throw GitFailure("文本比较包含超过 16,384 列的长行", code: .resourceBudget)
        }
        return parts
    }
}
