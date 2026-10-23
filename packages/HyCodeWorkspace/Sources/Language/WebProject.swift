import Foundation

public enum WebLanguage: String, Sendable {
    case javascript, javascriptreact, typescript, typescriptreact, vue, html, css, scss, less, json, jsonc, yaml
    public enum Service: String, CaseIterable, Sendable { case typescript, vue, html, css, json, yaml }
    public var service: Service {
        switch self {
        case .javascript, .javascriptreact, .typescript, .typescriptreact: .typescript
        case .vue: .vue
        case .html: .html
        case .css, .scss, .less: .css
        case .json, .jsonc: .json
        case .yaml: .yaml
        }
    }
    public var isJSON: Bool { self == .json || self == .jsonc }
    public var isConfiguration: Bool { isJSON || self == .yaml }
    public func synchronizes(with service: Service) -> Bool {
        self.service == service || (self == .vue && service == .typescript)
    }
    public static func detect(_ path: String) -> Self? {
        let url = URL(fileURLWithPath: path.lowercased())
        switch url.pathExtension {
        case "js", "mjs", "cjs": return .javascript
        case "jsx": return .javascriptreact
        case "ts", "mts", "cts": return .typescript
        case "tsx": return .typescriptreact
        case "vue": return .vue
        case "html", "htm": return .html
        case "css": return .css
        case "scss": return .scss
        case "less": return .less
        case "yaml", "yml": return .yaml
        case "jsonc": return .jsonc
        case "json":
            return url.lastPathComponent.hasPrefix("tsconfig.") || url.lastPathComponent.hasPrefix("jsconfig.")
                || (url.pathComponents.contains(".vscode")
                    && ["settings.json", "tasks.json", "launch.json", "extensions.json"].contains(url.lastPathComponent))
                ? .jsonc : .json
        default: return nil
        }
    }
}

public struct WebProject: Sendable {
    public enum Manager: String, CaseIterable, Sendable { case npm, pnpm, yarn }
    public struct Dependency: Sendable, Identifiable {
        public let name: String
        public let version: String
        public let kind: String
        public var id: String { kind + ":" + name }
    }
    public let root: URL
    public let name: String
    public let manager: Manager
    public let scripts: [String: String]
    public let dependencies: [Dependency]
    public let workspaces: [String]
    public static func inspect(workspace: URL, path: String = "") throws -> Self? {
        let workspace = workspace.resolvingSymlinksInPath().standardizedFileURL
        let target = try WorkspaceCanonicalPath.resolve(workspace.appendingPathComponent(path))
        guard target == workspace || target.path.hasPrefix(workspace.path + "/") else {
            throw LanguageServiceFailure("Web 项目路径越过工作区")
        }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        var directory = isDirectory.boolValue ? target : target.deletingLastPathComponent()
        if path.isEmpty { directory = workspace }
        for _ in 0..<64 {
            let manifest = directory.appendingPathComponent("package.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                let canonical = manifest.resolvingSymlinksInPath()
                guard canonical.path.hasPrefix(workspace.path + "/") else { throw LanguageServiceFailure("清单指向工作区外") }
                let attributes = try FileManager.default.attributesOfItem(atPath: canonical.path)
                guard let size = attributes[.size] as? Int, size <= 1_048_576 else {
                    throw LanguageServiceFailure("package.json 过大")
                }
                return try parse(Data(contentsOf: canonical), root: directory)
            }
            if directory == workspace { break }
            let parent = directory.deletingLastPathComponent()
            guard parent != directory, parent == workspace || parent.path.hasPrefix(workspace.path + "/") else { break }
            directory = parent
        }
        return nil
    }
    public static func parse(_ data: Data, root: URL) throws -> Self {
        guard data.count <= 1_048_576, let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object = json
        else { throw LanguageServiceFailure("package.json 不是有效 JSON 对象") }
        var scripts: [String: String] = [:]
        if case .object(let values) = json["scripts"] {
            for name in values.keys.sorted().prefix(200) {
                guard let value = values[name]?.string, !name.isEmpty, !name.hasPrefix("-"), name.count <= 256,
                    value.count <= 16_384, !name.contains("\0"), !value.contains("\0")
                else { continue }
                scripts[name] = value
            }
        }
        var dependencies: [Dependency] = []
        for kind in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            if case .object(let values) = json[kind] {
                for name in values.keys.sorted().prefix(1_000) {
                    if let version = values[name]?.string, name.count <= 256, version.count <= 1_024 {
                        dependencies.append(Dependency(name: name, version: version, kind: kind))
                    }
                }
            }
        }
        let declared = (json["packageManager"].string ?? "").split(separator: "@").first.map(String.init)
        let manager =
            declared.flatMap(Manager.init(rawValue:))
            ?? (FileManager.default.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path)
                ? .pnpm
                : FileManager.default.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) ? .yarn : .npm)
        let workspaces = (json["workspaces"]["packages"] == .null ? json["workspaces"] : json["workspaces"]["packages"])
            .array.prefix(100).compactMap(\.string).filter { $0.count <= 1_024 && !$0.contains("\0") }
        return Self(
            root: root, name: String((json["name"].string ?? root.lastPathComponent).prefix(256)),
            manager: manager, scripts: scripts, dependencies: dependencies, workspaces: workspaces)
    }
    public func arguments(action: String, package: String = "", dev: Bool = false, yarnMajor: Int? = nil) throws
        -> [String]
    {
        if manager == .yarn, yarnMajor != 1 && (yarnMajor ?? 0) < 4 {
            throw LanguageServiceFailure("当前支持 Yarn 1 与 Yarn 4+，请先配置对应版本")
        }
        let modernYarn = manager == .yarn && (yarnMajor ?? 0) >= 4
        let noHooks = modernYarn ? ["--mode=skip-build"] : ["--ignore-scripts"]
        switch action {
        case "script":
            guard scripts[package] != nil else { throw LanguageServiceFailure("脚本不在当前清单中") }
            return ["run", package]
        case "install": return ["install"] + noHooks + (manager == .npm ? ["--no-audit", "--no-fund"] : [])
        case "outdated":
            guard !modernYarn else { throw LanguageServiceFailure("Yarn 4 未内置 outdated；当前不自动安装额外插件") }
            return ["outdated"]
        case "list": return modernYarn ? ["info"] : ["list", "--depth=0"]
        case "add", "remove":
            guard
                package.range(
                    of: #"^(?:@[a-zA-Z0-9._-]+/)?[a-zA-Z0-9][a-zA-Z0-9._-]*(?:@[^\s\x00]+)?$"#,
                    options: .regularExpression) != nil, package.count <= 512
            else { throw LanguageServiceFailure("请输入有效的包名或包名@版本") }
            let verb =
                action == "remove" ? (manager == .npm ? "uninstall" : "remove") : (manager == .npm ? "install" : "add")
            return [verb, package] + (action == "add" && dev ? [manager == .npm ? "--save-dev" : "--dev"] : [])
                + noHooks + (manager == .npm ? ["--no-audit", "--no-fund"] : [])
        default: throw LanguageServiceFailure("不支持的 Web 工具操作")
        }
    }
}
