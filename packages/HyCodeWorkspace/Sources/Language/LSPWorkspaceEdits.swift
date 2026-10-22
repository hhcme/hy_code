import Foundation

public struct LSPWorkspaceFileEdit: Sendable {
    public let path: String
    public let version: Int?
    public let edits: [LSPTextEdit]
}

/// Accept text edits only. Resource operations and targets outside the granted
/// workspace are rejected before the native owner opens any buffers.
public enum LSPWorkspaceEdits {
    public static func preview(_ edits: [LSPTextEdit], text: String) throws -> String {
        let source = text as NSString
        let lines = TextLineIndex(text, unicodeLineSeparators: false)
        var result = ""
        for edit in edits {
            guard let range = edit.range.range(in: lines, source: source) else {
                throw LanguageServiceFailure("预览位置无效")
            }
            result +=
                "@@ \(edit.range.start.line + 1):\(edit.range.start.character + 1) @@\n- "
                + source.substring(with: range) + "\n+ " + edit.newText + "\n\n"
            guard result.utf8.count <= 262_144 else { throw LanguageServiceFailure("修改预览超过 256 KiB，请缩小重构范围") }
        }
        return result
    }
    public static func parse(_ value: JSONValue, root: URL) throws -> [LSPWorkspaceFileEdit] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var files: [LSPWorkspaceFileEdit] = []
        var seen = Set<String>()
        var bytes = 0
        var editCount = 0
        func append(uri: String, version: Int?, values: JSONValue) throws {
            guard let url = URL(string: uri), url.isFileURL, url.host == nil || url.host == "localhost" else {
                throw LanguageServiceFailure("编辑目标不是本地文件")
            }
            let target = try WorkspaceCanonicalPath.resolve(url)
            guard target.path.hasPrefix(root.path + "/"), seen.insert(target.path).inserted else {
                throw LanguageServiceFailure("编辑目标越过工作区或重复，请重新请求")
            }
            let edits = try values.decode([LSPTextEdit].self)
            editCount += edits.count
            for edit in edits {
                bytes += edit.newText.utf8.count
                guard !edit.newText.contains("\0") else { throw LanguageServiceFailure("编辑结果包含空字符") }
            }
            guard files.count < 32, editCount <= 5_000, bytes <= 8 * 1024 * 1024 else {
                throw LanguageServiceFailure("本次编辑超过 32 文件 / 5000 编辑 / 8 MiB 预算")
            }
            files.append(
                LSPWorkspaceFileEdit(
                    path: String(target.path.dropFirst(root.path.count + 1)), version: version, edits: edits))
        }
        guard !(value["changes"] != .null && value["documentChanges"] != .null) else {
            throw LanguageServiceFailure("编辑响应同时含两种目标表")
        }
        if case .object(let changes) = value["changes"] {
            for uri in changes.keys.sorted() { try append(uri: uri, version: nil, values: changes[uri]!) }
        } else if case .array(let changes) = value["documentChanges"] {
            for change in changes {
                guard change["kind"] == .null, let uri = change["textDocument"]["uri"].string else {
                    throw LanguageServiceFailure("当前预览只支持文本修改，不创建、移动或删除文件")
                }
                let versionValue = change["textDocument"]["version"]
                guard versionValue == .null || (versionValue.int != nil && versionValue.int! >= 0) else {
                    throw LanguageServiceFailure("编辑版本无效")
                }
                try append(uri: uri, version: versionValue.int, values: change["edits"])
            }
        } else {
            throw LanguageServiceFailure("语言服务未返回可预览的文本编辑")
        }
        guard !files.isEmpty else { throw LanguageServiceFailure("没有需要修改的文件") }
        return files
    }
}
