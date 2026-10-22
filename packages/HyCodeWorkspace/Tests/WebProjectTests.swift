import Foundation
import Testing

@testable import HyCodeWorkspace

struct WebProjectTests {
    @Test func languageFamiliesAndConfigurationCommentsAreDistinct() {
        #expect(WebLanguage.detect("src/main.mts") == .typescript)
        #expect(WebLanguage.detect("src/App.tsx") == .typescriptreact)
        #expect(WebLanguage.detect("src/App.JSX") == .javascriptreact)
        #expect(WebLanguage.detect("App.vue")?.service == .vue)
        #expect(WebLanguage.detect("style.less")?.service == .css)
        #expect(WebLanguage.detect("tsconfig.json") == .jsonc)
        #expect(WebLanguage.detect("package.json") == .json)
        #expect(WebLanguage.detect("main.dart") == nil)
        #expect(WebLanguage.vue.synchronizes(with: .typescript))
        #expect(WebLanguage.vue.synchronizes(with: .vue))
        #expect(WebLanguage.typescriptreact.synchronizes(with: .typescript))
        #expect(!WebLanguage.json.synchronizes(with: .typescript))
        #expect(!WebLanguage.typescript.synchronizes(with: .vue))
    }
    @Test func manifestKeepsScriptLiteralAndTypedDependencyKinds() throws {
        let data = Data(
            #"{"name":"demo","packageManager":"pnpm@10.0.0","scripts":{"test":"echo $(unsafe)","-bad":"ignored"},"dependencies":{"vue":"^3"},"devDependencies":{"typescript":"^6"},"workspaces":["packages/*"]}"#
                .utf8)
        let project = try WebProject.parse(data, root: URL(fileURLWithPath: "/tmp/work"))
        #expect(project.manager == .pnpm && project.dependencies.count == 2)
        #expect(project.scripts["test"] == "echo $(unsafe)" && project.scripts["-bad"] == nil)
        #expect(try project.arguments(action: "script", package: "test") == ["run", "test"])
        #expect(project.workspaces == ["packages/*"])
        #expect(throws: LanguageServiceFailure.self) { try project.arguments(action: "script", package: "another") }
    }
    @Test func packageCommandsDisableHooksAndNeverBuildShellStrings() throws {
        let project = try WebProject.parse(
            Data(#"{"packageManager":"npm@11"}"#.utf8), root: URL(fileURLWithPath: "/tmp/work"))
        #expect(try project.arguments(action: "install").contains("--ignore-scripts"))
        let add = try project.arguments(action: "add", package: "@vue/runtime-core@^3", dev: true)
        #expect(
            add == ["install", "@vue/runtime-core@^3", "--save-dev", "--ignore-scripts", "--no-audit", "--no-fund"])
        for name in ["--unsafe", "../local", "package;touch file", "pkg\nother", ""] {
            #expect(throws: LanguageServiceFailure.self) { try project.arguments(action: "add", package: name) }
        }
        #expect(throws: LanguageServiceFailure.self) { try project.arguments(action: "unknown") }
    }
    @Test func nearestPackageAndDirectorySelectionStayInsideWorkspace() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("packages/ui/src"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data(#"{"name":"root"}"#.utf8).write(to: root.appendingPathComponent("package.json"))
        try Data(#"{"name":"ui"}"#.utf8).write(to: root.appendingPathComponent("packages/ui/package.json"))
        try Data("export const item = 1".utf8).write(to: root.appendingPathComponent("packages/ui/src/main.ts"))
        #expect(try WebProject.inspect(workspace: root, path: "packages/ui/src/main.ts")?.name == "ui")
        #expect(try WebProject.inspect(workspace: root, path: "packages/ui")?.name == "ui")
        #expect(throws: LanguageServiceFailure.self) { try WebProject.inspect(workspace: root, path: "../escape.ts") }
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
        #expect(throws: LanguageServiceFailure.self) {
            try WebProject.inspect(workspace: root, path: "outside/secret.ts")
        }
    }
    @Test func yarnClassicAndModernCommandsHaveSeparateCompatibilityAndHookPolicy() throws {
        let project = try WebProject.parse(
            Data(#"{"packageManager":"yarn@4.0.0"}"#.utf8), root: URL(fileURLWithPath: "/tmp/work"))
        #expect(try project.arguments(action: "install", yarnMajor: 1) == ["install", "--ignore-scripts"])
        #expect(try project.arguments(action: "install", yarnMajor: 4) == ["install", "--mode=skip-build"])
        #expect(
            try project.arguments(action: "add", package: "vue", yarnMajor: 4) == ["add", "vue", "--mode=skip-build"])
        #expect(try project.arguments(action: "list", yarnMajor: 1) == ["list", "--depth=0"])
        #expect(try project.arguments(action: "list", yarnMajor: 4) == ["info"])
        #expect(throws: LanguageServiceFailure.self) { try project.arguments(action: "outdated", yarnMajor: 4) }
        #expect(throws: LanguageServiceFailure.self) { try project.arguments(action: "install", yarnMajor: 2) }
    }
    @Test func malformedAndOversizedManifestsAndUnsupportedNodesFailExplicitly() {
        for value in ["[]", "not json", "null", String(repeating: " ", count: 1_048_577)] {
            #expect(throws: LanguageServiceFailure.self) {
                try WebProject.parse(Data(value.utf8), root: URL(fileURLWithPath: "/tmp/work"))
            }
        }
        #expect(WebToolchain.supportsNode("v22.22.2\n"))
        #expect(WebToolchain.supportsNode("v24.0.0"))
        #expect(!WebToolchain.supportsNode("v22.22.1"))
        #expect(!WebToolchain.supportsNode("v20.20.0"))
        #expect(!WebToolchain.supportsNode("garbage"))
    }
}
