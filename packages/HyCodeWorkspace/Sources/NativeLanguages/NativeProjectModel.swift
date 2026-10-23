import Foundation

/// Metadata/configuration adaptation only. Loading a SwiftPM/BSP/Maven/Gradle
/// build model remains an explicit trust-gated action in the service owner.
public enum NativeProjectModel: String, Sendable {
    case swiftPM, xcodeBuildServer, buildServer, xcodeNeedsBuildServer, maven, gradle, eclipse, standalone, offlineSQL
    public var title: String {
        switch self {
        case .swiftPM: "SwiftPM"
        case .xcodeBuildServer: "Xcode / BSP 构建信息"
        case .buildServer: "BSP 构建信息"
        case .xcodeNeedsBuildServer: "Xcode：需要 buildServer.json；当前仅单文件语义"
        case .maven: "Maven"
        case .gradle: "Gradle"
        case .eclipse: "Eclipse"
        case .standalone: "单文件 / 无构建清单"
        case .offlineSQL: "离线 SQL / 项目 DDL"
        }
    }
    public static func inspect(language: NativeCodeLanguage, root: URL) throws -> Self {
        let files = FileManager.default
        func exists(_ path: String) -> Bool { files.fileExists(atPath: root.appendingPathComponent(path).path) }
        if language == .sql { return .offlineSQL }
        if language == .java {
            if exists("pom.xml") { return .maven }
            if exists("build.gradle") || exists("build.gradle.kts") { return .gradle }
            if exists(".project") { return .eclipse }
            return .standalone
        }
        let walker = files.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        var xcode = false
        var count = 0
        while let url = walker?.nextObject() as? URL {
            count += 1
            if count > 1000 { break }
            if ["xcodeproj", "xcworkspace"].contains(url.pathExtension.lowercased()) {
                xcode = true
                break
            }
        }
        if exists("buildServer.json") {
            let data = try PreviewFileIO.read(root: root, path: "buildServer.json", limit: 65_536)
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            let argv = value["argv"].array.compactMap(\.string)
            guard !argv.isEmpty, argv.count == value["argv"].array.count, argv.count <= 64,
                argv.allSatisfy({ !$0.contains("\0") && $0.utf8.count <= 8192 }),
                argv.reduce(0, { $0 + $1.utf8.count }) <= 16_384,
                value["languages"].array.contains(.string("swift"))
            else { throw LanguageServiceFailure("buildServer.json 缺少受支持的 argv / Swift languages 或超出大小限制") }
            return xcode ? .xcodeBuildServer : .buildServer
        }
        if exists("Package.swift") { return .swiftPM }
        return xcode ? .xcodeNeedsBuildServer : .standalone
    }
}
