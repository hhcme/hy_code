import Foundation
import Testing

@testable import HyCodeWorkspace

struct DartProjectTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hycode-dart-metadata-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ text: String, at path: String, root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    @Test func nestedPackageUsesNearestManifestAndDistinguishesPackageAndLanguageVersions() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("name: workspace\n", at: "pubspec.yaml", root: root)
        try write(
            "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n", at: "packages/app/pubspec.yaml", root: root)
        try write(
            """
            {"configVersion":2,"packages":[{"name":"a_pkg","rootUri":"../../../a_pkg/","languageVersion":"3.5"}]}
            """, at: "packages/app/.dart_tool/package_config.json", root: root)
        try write(
            """
            packages:
              a_pkg:
                dependency: "direct dev"
                description:
                  name: ignored
                  version: "9.9.9"
                source: hosted
                version: "1.2.3+4"
            sdks:
              dart: ">=3.5.0"
            """, at: "packages/app/pubspec.lock", root: root)
        let info = try #require(try DartProjectInfo.inspect(workspace: root, path: "packages/app/lib/main.dart"))
        #expect(info.root == root.appendingPathComponent("packages/app"))
        #expect(info.isFlutter && info.resolved)
        let package = try #require(info.packages.first)
        #expect(package.version == "1.2.3+4" && package.languageVersion == "3.5")
        #expect(package.dependency == "direct dev" && package.source == "hosted")
        #expect(package.root.path == root.appendingPathComponent("a_pkg").path)
        #expect(try DartProjectInfo.inspect(workspace: root, path: "lib/main.dart")?.isFlutter == false)
        #expect(try DartProjectInfo.inspect(workspace: root, path: "../other/main.dart") == nil)
        #expect(try DartProjectInfo.inspect(workspace: root, path: "/outside.dart") == nil)
    }
    @Test func invalidPackageConfigStaysUnresolvedAndUnsupportedLockScalarsStayUnknown() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("name: app\n", at: "pubspec.yaml", root: root)
        try write("not json", at: ".dart_tool/package_config.json", root: root)
        #expect(try DartProjectInfo.inspect(workspace: root)?.resolved == false)
        let locked = DartPackageLock.parse("packages:\n  pkg:\n    version: *some_alias\n    dependency: mystery\n")
        #expect(locked["pkg"]?.version == nil && locked["pkg"]?.dependency == nil)
    }
    @Test func sdkDiscoveryReadsMetadataWithoutExecutingSDKOrProjectFiles() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["bin/flutter", "bin/cache/dart-sdk/bin/dart"] {
            try write("This is metadata, never execute this fixture", at: path, root: root)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent(path).path)
        }
        try write("", at: "bin/cache/dart-sdk/bin/snapshots/analysis_server.dart.snapshot", root: root)
        try write("3.11.5\n", at: "bin/cache/dart-sdk/version", root: root)
        let sdk = try DartToolchain.discover(configured: root.path, environment: [:])
        #expect(sdk.flutterSDK == root.resolvingSymlinksInPath())
        #expect(sdk.dartVersion == "3.11.5")
        #expect(
            try DartToolchain.discover(environment: ["PATH": root.appendingPathComponent("bin").path]).dart == sdk.dart)
        #expect(throws: LanguageServiceFailure.self) {
            try DartToolchain.discover(configured: root.appendingPathComponent("missing").path)
        }
    }
    @Test func outputDecoderPreservesSplitChineseAndEmojiAndBoundsIncompleteBytes() {
        let text = "分析中😀\n依赖已更新"
        var decoder = UTF8OutputDecoder()
        var result = ""
        for byte in text.utf8 { result += decoder.append(Data([byte])) }
        result += decoder.finish()
        #expect(result == text)
        #expect(decoder.append(Data([0xf0, 0x9f])) == "")
        #expect(decoder.finish() == "�")
    }
}
