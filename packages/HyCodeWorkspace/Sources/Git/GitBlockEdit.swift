import Foundation

/// An immutable, revision-bound native editor operation, not a filesystem patch.
public struct GitBlockEdit: Sendable, Equatable {
    public let range: NSRange
    public let expected: String
    public let replacement: String
    public static func restoring(_ id: Int, in comparison: GitTextComparison) throws -> Self {
        guard let block = comparison.blocks.first(where: { $0.id == id }),
            let left = comparison.left.characterRange(lines: block.left),
            let right = comparison.right.characterRange(lines: block.right)
        else { throw GitFailure("差异块已变化，请等待比较更新") }
        return Self(
            range: right,
            expected: (comparison.right.text as NSString).substring(with: right),
            replacement: (comparison.left.text as NSString).substring(with: left))
    }
}

/// Frozen bytes for a partial commit. Only GitRepository may create/attach one.
/// The visible document remains owned by EditorDocument and is never replaced.
public struct GitPartialSelection: Sendable, Equatable {
    public static let retainedByteLimit = 33_554_432
    public let blocks: Set<Int>
    public var byteCount: Int { contents.count }
    let contents: Data
    let mode: String
    let preserveIndex: Bool

    public static func retainedBytes(_ selections: [GitSelection]) throws -> Int {
        var total = 0
        for value in selections {
            let count = value.partial?.byteCount ?? 0
            guard count <= 8_388_608, count <= retainedByteLimit - total else {
                throw GitFailure("部分提交候选合计超过 32 MiB，请分批提交", code: .resourceBudget)
            }
            total += count
        }
        return total
    }
    static func contents(
        _ comparison: GitTextComparison, selecting ids: Set<Int>, bom: Bool,
        maximumBytes: Int = 8_388_608
    ) throws -> Data {
        guard !ids.isEmpty, ids.isSubset(of: Set(comparison.blocks.map(\.id))) else {
            throw GitFailure("所选差异块已过期，请重新审查")
        }
        let left = comparison.left.text as NSString
        let right = comparison.right.text as NSString
        var output = bom ? Data([0xef, 0xbb, 0xbf]) : Data()
        func append(_ text: String) throws {
            guard output.count + text.utf8.count <= min(8_388_608, maximumBytes) else {
                throw GitFailure("部分提交候选超过单文件或总保留预算，请分批提交", code: .resourceBudget)
            }
            output.append(contentsOf: text.utf8)
        }
        var cursor = 0
        for (index, block) in comparison.blocks.enumerated() where ids.contains(block.id) {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            guard let a = comparison.left.characterRange(lines: block.left),
                let b = comparison.right.characterRange(lines: block.right), a.location >= cursor
            else {
                throw GitFailure("差异块范围无效")
            }
            try append(left.substring(with: NSRange(location: cursor, length: a.location - cursor)))
            try append(right.substring(with: b))
            cursor = NSMaxRange(a)
        }
        try append(left.substring(from: cursor))
        return output
    }
}
