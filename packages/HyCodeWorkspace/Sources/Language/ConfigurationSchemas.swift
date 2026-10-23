import Foundation

/// Only this bounded, bundled catalog associates schemas. Project code is not
/// imported; schema bytes are served by the native reader or pinned Node data.
public enum ConfigurationSchemas {
    static func configured(_ base: JSONValue, directory: URL) throws -> JSONValue {
        let data = try Data(contentsOf: directory.appendingPathComponent("schemas/catalog.json"))
        return try configured(base, data: data)
    }
    static func configured(_ base: JSONValue, data: Data) throws -> JSONValue {
        guard data.count <= 65_536 else { throw LanguageServiceFailure("Schema 台账超限") }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard value["schema"].int == 1, value["schemas"].array.count <= 32 else {
            throw LanguageServiceFailure("Schema 台账无效")
        }
        var json: [JSONValue] = []
        var yaml: [String: JSONValue] = [:]
        for item in value["schemas"].array {
            guard let uri = item["uri"].string, uri.hasPrefix("https://json.schemastore.org/"), uri.count <= 256,
                item["fileMatch"].array.count <= 16,
                item["fileMatch"].array.allSatisfy({ ($0.string?.utf8.count ?? 1025) <= 1024 })
            else { throw LanguageServiceFailure("Schema 关联无效") }
            if item["languages"].array.contains(.string("json")) {
                json.append(.object(["url": .string(uri), "fileMatch": item["fileMatch"]]))
            }
            if item["languages"].array.contains(.string("yaml")) { yaml[uri] = item["fileMatch"] }
        }
        guard case .object(var result) = base, case .object(var jsonSettings) = result["json"],
            case .object(var yamlSettings) = result["yaml"]
        else { throw LanguageServiceFailure("配置服务设置无效") }
        jsonSettings["schemas"] = .array(json)
        yamlSettings["schemas"] = .object(yaml)
        result["json"] = .object(jsonSettings)
        result["yaml"] = .object(yamlSettings)
        return .object(result)
    }
    static func requestURI(_ parameters: JSONValue) throws -> String {
        if let value = parameters.string { return value }
        if parameters.array.count == 1, let value = parameters.array.first?.string { return value }
        throw LanguageServiceFailure("Schema 请求参数无效")
    }
    static func relativePath(_ uri: String, root: URL) throws -> String {
        guard uri.utf8.count <= 8192, let url = URL(string: uri), url.isFileURL,
            url.host == nil || url.host == "" || url.host == "localhost", url.query == nil,
            url.path.hasPrefix(root.path + "/")
        else { throw LanguageServiceFailure("Schema 必须位于当前项目内，禁止网络读取") }
        let path = String(url.path.dropFirst(root.path.count + 1))
        guard ProjectSourceCatalog.allows(path) else { throw LanguageServiceFailure("Schema 路径不在分析范围内") }
        return path
    }
    public static func readLocal(_ uri: String, root: URL) async throws -> String {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let path = try relativePath(uri, root: root)
            let file = ProjectSourceFile(path: path, language: .json, size: 0, modified: .distantPast)
            let content = try ProjectSourceCatalog.read(file, root: root)
            try Task.checkCancellation()
            return content
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }
}
