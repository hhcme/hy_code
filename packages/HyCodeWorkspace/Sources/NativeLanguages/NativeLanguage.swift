import Foundation

public enum NativeCodeLanguage: String, CaseIterable, Codable, Sendable {
    case swift, java, sql
    public static func detect(_ path: String) -> Self? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift": .swift
        case "java": .java
        case "sql": .sql
        default: nil
        }
    }
    public var title: String {
        switch self {
        case .swift: "Swift"
        case .java: "Java"
        case .sql: "SQL"
        }
    }
}

public struct NativeLanguageSettings: Sendable {
    public var sourceKitPath: String
    public var javaHome: String
    public var jdtlsPath: String
    public init(sourceKitPath: String = "", javaHome: String = "", jdtlsPath: String = "") {
        self.sourceKitPath = sourceKitPath
        self.javaHome = javaHome
        self.jdtlsPath = jdtlsPath
    }
}

/// Discovery is metadata-only; in particular it never executes macOS's Java
/// installer stub. Call off MainActor. Launch/import is separately trust-gated.
public struct NativeLanguageToolchain: Sendable {
    public let language: NativeCodeLanguage
    public let executable: URL
    public let serverDirectory: URL?
    public let javaHome: URL?
    public let launcher: URL?
    public let configuration: URL?
    public static func discover(_ language: NativeCodeLanguage, settings: NativeLanguageSettings) throws -> Self {
        let files = FileManager.default
        func url(_ value: String) -> URL { URL(fileURLWithPath: (value as NSString).expandingTildeInPath) }
        if language == .swift {
            var candidates: [URL] = []
            if !settings.sourceKitPath.isEmpty {
                candidates = [url(settings.sourceKitPath)]
            } else {
                if let developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
                    candidates.append(
                        url(developer).appendingPathComponent(
                            "Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"))
                }
                candidates += [
                    url(
                        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"
                    ),
                    url("/Library/Developer/CommandLineTools/usr/bin/sourcekit-lsp"),
                ]
            }
            guard let executable = candidates.first(where: { files.isExecutableFile(atPath: $0.path) }) else {
                throw LanguageServiceFailure("未找到 SourceKit-LSP，请在设置选择已安装工具链的 sourcekit-lsp")
            }
            return Self(
                language: language, executable: executable, serverDirectory: nil, javaHome: nil, launcher: nil,
                configuration: nil)
        }
        guard language == .java else { throw LanguageServiceFailure("SQL 使用内置离线工具") }
        let homeCandidates =
            settings.javaHome.isEmpty
            ? [
                ProcessInfo.processInfo.environment["JAVA_HOME"],
                "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
                "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home",
            ].compactMap { $0 }
            : [settings.javaHome]
        guard
            let home = homeCandidates.map(url).first(where: { candidate in
                guard files.isExecutableFile(atPath: candidate.appendingPathComponent("bin/java").path),
                    let size = try? candidate.appendingPathComponent("release").resourceValues(forKeys: [.fileSizeKey])
                        .fileSize, size <= 65_536,
                    let data = try? Data(contentsOf: candidate.appendingPathComponent("release")), data.count <= 65_536,
                    let text = String(data: data, encoding: .utf8),
                    let line = text.split(separator: "\n").first(where: { $0.hasPrefix("JAVA_VERSION=") }),
                    let version = line.split(separator: "=").last?.trimmingCharacters(
                        in: CharacterSet(charactersIn: "\"")),
                    let major = Int(version.split(separator: ".").first ?? "")
                else { return false }
                return major >= 21
            })
        else { throw LanguageServiceFailure("Java 语言服务需要已安装的 JDK 21+；设置中填写 JAVA_HOME，不使用系统安装提示") }
        let server = url(settings.jdtlsPath.isEmpty ? "/opt/homebrew/opt/jdtls/libexec" : settings.jdtlsPath)
        let jars =
            (try? files.contentsOfDirectory(
                at: server.appendingPathComponent("plugins"), includingPropertiesForKeys: nil)) ?? []
        let launchers = jars.filter {
            $0.lastPathComponent.hasPrefix("org.eclipse.equinox.launcher_") && $0.pathExtension == "jar"
        }
        let configs = ["config_mac_arm", "config_mac"].map { server.appendingPathComponent($0) }
        guard launchers.count == 1, files.isReadableFile(atPath: launchers[0].path),
            let config = configs.first(where: { files.fileExists(atPath: $0.appendingPathComponent("config.ini").path) }
            )
        else { throw LanguageServiceFailure("未找到完整 Eclipse JDT LS；设置中选择包含 plugins 与 config_mac 的外部服务目录") }
        return Self(
            language: language, executable: home.appendingPathComponent("bin/java"), serverDirectory: server,
            javaHome: home, launcher: launchers[0], configuration: config)
    }
}
