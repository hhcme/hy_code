import Foundation

enum GitDiffParser {
    static func unified(_ rows: [GitDiffRow]) -> [GitDiffRow] {
        rows.flatMap { row in
            if row.kind != .changed { return [row] }
            return [
                GitDiffRow(
                    id: row.id, leftNumber: row.leftNumber, rightNumber: nil, left: row.left, right: nil,
                    kind: .removed, leftChange: row.leftChange, rightChange: nil),
                GitDiffRow(
                    id: row.id, leftNumber: nil, rightNumber: row.rightNumber, left: nil, right: row.right,
                    kind: .added, leftChange: nil, rightChange: row.rightChange),
            ]
        }
    }
    static func rows(_ patch: String) throws -> [GitDiffRow] {
        var rows: [GitDiffRow] = []
        var left = 0
        var right = 0
        var active = false
        var previousMarker: Character?
        var removed: [(Int, String)] = []
        var added: [(Int, String)] = []
        var leftNoNewline = false
        var rightNoNewline = false
        var noteRows = 0
        var eofMarkers = 0
        func append(_ l: Int?, _ r: Int?, _ a: String?, _ b: String?, _ kind: GitDiffRow.Kind) {
            var lc: Range<Int>?
            var rc: Range<Int>?
            if kind == .changed, let a, let b {
                let x = Array(a.utf16)
                let y = Array(b.utf16)
                var prefix = 0
                while prefix < min(x.count, y.count), x[prefix] == y[prefix] { prefix += 1 }
                var suffix = 0
                while suffix < min(x.count, y.count) - prefix,
                    x[x.count - suffix - 1] == y[y.count - suffix - 1]
                { suffix += 1 }
                lc = prefix..<(x.count - suffix)
                rc = prefix..<(y.count - suffix)
            }
            if kind == .note { noteRows += 1 }
            rows.append(
                GitDiffRow(
                    id: rows.count, leftNumber: l, rightNumber: r, left: a, right: b, kind: kind, leftChange: lc,
                    rightChange: rc))
        }
        func flush() {
            for index in 0..<max(removed.count, added.count) {
                let a = index < removed.count ? removed[index] : nil
                let b = index < added.count ? added[index] : nil
                append(a?.0, b?.0, a?.1, b?.1, a != nil && b != nil ? .changed : a == nil ? .added : .removed)
            }
            removed.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
            if leftNoNewline || rightNoNewline {
                append(nil, nil, leftNoNewline ? "文件末尾没有换行" : nil, rightNoNewline ? "文件末尾没有换行" : nil, .note)
                leftNoNewline = false
                rightNoNewline = false
            }
        }
        // Enforce row limits before allocating the rest of a dense patch.
        let source = patch as NSString
        var cursor = 0
        while cursor < source.length {
            let newline = source.range(of: "\n", range: NSRange(location: cursor, length: source.length - cursor))
            let end = newline.location == NSNotFound ? source.length : newline.location
            guard end - cursor <= 16_384 else {
                throw GitFailure("差异包含超过 16,384 列的长行；请使用原生大文件编辑查看，不将局部显示当全文", code: .resourceBudget)
            }
            let line = source.substring(with: NSRange(location: cursor, length: end - cursor))
            cursor = newline.location == NSNotFound ? source.length : end + 1
            if rows.count.isMultiple(of: 64) { try Task.checkCancellation() }
            if line.isEmpty {
                flush()
                active = false
                previousMarker = nil
                continue
            }
            if active, line == "\\ No newline at end of file" {
                eofMarkers += 1
                guard eofMarkers <= 32 else { throw GitFailure("差异 EOF 注记超过预算", code: .resourceBudget) }
                if previousMarker == " " {
                    append(nil, nil, "文件末尾没有换行", "文件末尾没有换行", .note)
                } else {
                    if previousMarker == "-" { leftNoNewline = true }
                    if previousMarker == "+" { rightNoNewline = true }
                }
                continue
            }
            if line.hasPrefix("diff --git ") {
                flush()
                active = false
                previousMarker = nil
            } else if line.hasPrefix("@@ ") {
                flush()
                let parts = line.split(separator: " ")
                guard parts.count >= 4, parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
                    let leftPart = parts[1].dropFirst().split(separator: ",").first,
                    let rightPart = parts[2].dropFirst().split(separator: ",").first,
                    let a = Int(leftPart), let b = Int(rightPart), a >= 0, b >= 0,
                    a <= Int.max - 20_000, b <= Int.max - 20_000
                else { throw GitFailure("差异块行号无效") }
                let skippedLeft = max(0, a - max(1, left))
                let skippedRight = max(0, b - max(1, right))
                if skippedLeft > 0 || skippedRight > 0 {
                    append(
                        nil, nil, skippedLeft > 0 ? "··· 已省略 \(skippedLeft) 行 ···" : nil,
                        skippedRight > 0 ? "··· 已省略 \(skippedRight) 行 ···" : nil, .header)
                }
                left = a
                right = b
                active = true
                previousMarker = nil
            } else if active, line.hasPrefix("-") {
                removed.append((left, String(line.dropFirst())))
                left += 1
                previousMarker = "-"
            } else if active, line.hasPrefix("+") {
                added.append((right, String(line.dropFirst())))
                right += 1
                previousMarker = "+"
            } else if active, line.hasPrefix(" ") {
                flush()
                append(left, right, String(line.dropFirst()), String(line.dropFirst()), .context)
                left += 1
                right += 1
                previousMarker = " "
            } else {
                flush()
                active = false
                previousMarker = nil
            }
            guard rows.count - noteRows + max(removed.count, added.count) <= 20_000, noteRows <= 32 else {
                throw GitFailure("差异超过 20,000 行，请使用外部工具查看完整差异", code: .resourceBudget)
            }
        }
        flush()
        guard rows.count - noteRows <= 20_000, noteRows <= 32 else {
            throw GitFailure("差异超过 20,000 行，请使用外部工具查看完整差异", code: .resourceBudget)
        }
        return rows
    }

    static func changeStarts(_ rows: [GitDiffRow]) -> [Int] {
        var changing = false
        return rows.compactMap { row in
            if row.kind == .note { return nil }
            let start = row.kind.isChange && !changing
            changing = row.kind.isChange
            return start ? row.id : nil
        }
    }
}

public struct GitGraphRow: Sendable, Equatable {
    public struct Edge: Sendable, Equatable {
        public let from: Int
        public let to: Int
    }
    public let column: Int
    public let columns: Int
    public let edges: [Edge]
    public static func layout(_ commits: [GitCommit]) -> [GitGraphRow] {
        var lanes: [String] = []
        return commits.map { commit in
            if !lanes.contains(commit.object) { lanes.append(commit.object) }
            let before = lanes
            let column = lanes.firstIndex(of: commit.object) ?? 0
            lanes.remove(at: column)
            for (index, parent) in commit.parents.enumerated() where !lanes.contains(parent) {
                lanes.insert(parent, at: min(column + index, lanes.count))
            }
            var edges: [Edge] = []
            for (index, object) in before.enumerated() where object != commit.object {
                if let target = lanes.firstIndex(of: object) { edges.append(Edge(from: index, to: target)) }
            }
            for parent in commit.parents {
                if let target = lanes.firstIndex(of: parent) { edges.append(Edge(from: column, to: target)) }
            }
            return GitGraphRow(column: column, columns: max(before.count, lanes.count), edges: edges)
        }
    }
}
