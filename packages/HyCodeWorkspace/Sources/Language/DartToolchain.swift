import Foundation

public struct DartToolchain: Sendable {
    public let dartSDK: URL
    public let flutterSDK: URL?
    public let dartVersion: String
    public var dart: URL { dartSDK.appendingPathComponent("bin/dart") }
    public var analysisServer: URL { dartSDK.appendingPathComponent("bin/snapshots/analysis_server.dart.snapshot") }
    public var flutter: URL? { flutterSDK?.appendingPathComponent("bin/flutter") }

    /// Read metadata only. Never run wrappers, download tools, inspect unrelated
    /// projects or execute a workspace-local SDK automatically.
    public static func discover(
        configured: String = "", environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        if !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let result = inspect(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)) else {
                throw LanguageServiceFailure("SDK 路径无效，需要 Flutter SDK 或 Dart SDK 根目录")
            }
            return result
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            for name in ["flutter", "dart"] {
                let executable = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
                    .resolvingSymlinksInPath()
                if let result = inspect(executable.deletingLastPathComponent().deletingLastPathComponent()) {
                    return result
                }
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for root in [
            home.appendingPathComponent("flutter"), home.appendingPathComponent("fvm/default"),
            URL(fileURLWithPath: "/opt/homebrew/share/flutter"),
        ] {
            if let result = inspect(root) { return result }
        }
        throw LanguageServiceFailure("未发现 Dart/Flutter SDK，请在设置中填写 SDK 根目录")
    }
    public static func inspect(_ candidate: URL) -> Self? {
        let root = candidate.standardizedFileURL.resolvingSymlinksInPath()
        let embedded = root.appendingPathComponent("bin/cache/dart-sdk")
        let flutter = FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/flutter").path)
        let sdk = flutter ? embedded : root
        guard FileManager.default.isExecutableFile(atPath: sdk.appendingPathComponent("bin/dart").path),
            FileManager.default.fileExists(
                atPath: sdk.appendingPathComponent("bin/snapshots/analysis_server.dart.snapshot").path),
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: sdk.appendingPathComponent("version").path),
            let size = attributes[.size] as? Int, size <= 1_000,
            let version = try? String(contentsOf: sdk.appendingPathComponent("version"), encoding: .utf8),
            version.count < 100
        else { return nil }
        return Self(
            dartSDK: sdk, flutterSDK: flutter ? root : nil,
            dartVersion: version.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public struct DartResolvedPackage: Sendable, Identifiable {
    public let name: String
    public let root: URL
    public let languageVersion: String
    public let version: String?
    public let dependency: String?
    public let source: String?
    public var id: String { name }
}
public struct DartProjectInfo: Sendable {
    public let root: URL
    public let isFlutter: Bool
    public let packages: [DartResolvedPackage]
    public let resolved: Bool
    public static func inspect(workspace: URL, path: String = "") throws -> Self? {
        let workspace = workspace.standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        var root = path.isEmpty ? workspace : workspace.appendingPathComponent(path).deletingLastPathComponent()
        while root.path == workspace.path || root.path.hasPrefix(workspace.path + "/") {
            let manifest = root.appendingPathComponent("pubspec.yaml")
            if let attributes = try? FileManager.default.attributesOfItem(atPath: manifest.path),
                let size = attributes[.size] as? Int, size <= 1_048_576,
                let yaml = try? String(contentsOf: manifest, encoding: .utf8)
            {
                let config = root.appendingPathComponent(".dart_tool/package_config.json")
                let lock = root.appendingPathComponent("pubspec.lock")
                var locked: [String: DartPackageLock.Entry] = [:]
                if let attributes = try? FileManager.default.attributesOfItem(atPath: lock.path),
                    let size = attributes[.size] as? Int, size <= 1_048_576,
                    let text = try? String(contentsOf: lock, encoding: .utf8)
                {
                    locked = DartPackageLock.parse(text)
                }
                var packages: [DartResolvedPackage] = []
                let data = try? Data(contentsOf: config, options: .mappedIfSafe)
                let json = data.flatMap {
                    $0.count <= 4 * 1024 * 1024 ? try? JSONDecoder().decode(JSONValue.self, from: $0) : nil
                }
                for item in (json?["packages"].array ?? []).prefix(5_000) {
                    guard let name = item["name"].string, let uri = item["rootUri"].string,
                        let location = URL(string: uri, relativeTo: config)?.absoluteURL, location.isFileURL
                    else { continue }
                    packages.append(
                        DartResolvedPackage(
                            name: name, root: location.standardizedFileURL,
                            languageVersion: item["languageVersion"].string ?? "", version: locked[name]?.version,
                            dependency: locked[name]?.dependency, source: locked[name]?.source))
                }
                return Self(
                    root: root,
                    isFlutter: yaml.range(of: #"(?m)^\s+sdk:\s*flutter\s*(?:#.*)?$"#, options: .regularExpression)
                        != nil,
                    packages: packages.sorted { $0.name < $1.name }, resolved: json?["configVersion"].int == 2)
            }
            guard root.path != workspace.path else { break }
            root.deleteLastPathComponent()
        }
        return nil
    }
}
