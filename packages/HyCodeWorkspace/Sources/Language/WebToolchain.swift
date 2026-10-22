import Foundation

public struct WebToolchain: Sendable {
    public let node: URL
    public let services: URL
    public init(node: URL, services: URL) {
        self.node = node
        self.services = services
    }
    public static func discover(configured: String, services: URL) throws -> Self {
        let manager = FileManager.default
        let explicit = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [URL] = []
        if !explicit.isEmpty {
            candidates = [URL(fileURLWithPath: explicit)]
        } else {
            candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("node") }
            candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node"].map { URL(fileURLWithPath: $0) }
            let nvm = manager.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
            if let versions = try? manager.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil) {
                candidates += versions.sorted {
                    $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
                }
                .map { $0.appendingPathComponent("bin/node") }
            }
        }
        guard let node = candidates.first(where: { manager.isExecutableFile(atPath: $0.path) }) else {
            throw LanguageServiceFailure("未找到 Node.js，请在设置指定 Node 可执行文件（22.22.2 或更新）")
        }
        for path in [
            "typescript/lib/tsserver.js", "typescript-language-server/lib/cli.mjs",
            "@vue/language-server/bin/vue-language-server.js",
            "vscode-langservers-extracted/bin/vscode-html-language-server",
        ] {
            guard manager.fileExists(atPath: services.appendingPathComponent("node_modules/" + path).path) else {
                throw LanguageServiceFailure("Web 语言工具缺失，请重新构建完整开发包")
            }
        }
        return Self(node: node.resolvingSymlinksInPath(), services: services)
    }
    public static func supportsNode(_ version: String) -> Bool {
        let values = version.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "v" }).split(
            separator: "."
        ).compactMap { Int($0) }
        guard values.count == 3 else { return false }
        return values[0] > 22 || (values[0] == 22 && (values[1] > 22 || (values[1] == 22 && values[2] >= 2)))
    }
    public func script(_ service: WebLanguage.Service) -> URL {
        let path: String
        switch service {
        case .typescript: path = "typescript-language-server/lib/cli.mjs"
        case .vue: path = "@vue/language-server/bin/vue-language-server.js"
        case .html: path = "vscode-langservers-extracted/bin/vscode-html-language-server"
        case .css: path = "vscode-langservers-extracted/bin/vscode-css-language-server"
        case .json: path = "vscode-langservers-extracted/bin/vscode-json-language-server"
        }
        return services.appendingPathComponent("node_modules/" + path)
    }
    public func packageManager(_ manager: WebProject.Manager) throws -> URL {
        let directories =
            [node.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard
            let path = directories.map({ URL(fileURLWithPath: $0).appendingPathComponent(manager.rawValue) })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
        else {
            throw LanguageServiceFailure("未找到 \(manager.rawValue)，请先安装到所选 Node 环境；HyCode 不自动运行 Corepack 下载")
        }
        return path.resolvingSymlinksInPath()
    }
    public var environment: [String: String] {
        [
            "PATH": node.deletingLastPathComponent().path + ":"
                + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"),
            "YARN_ENABLE_SCRIPTS": "false", "npm_config_update_notifier": "false", "npm_config_audit": "false",
            "npm_config_fund": "false",
        ]
    }
}
