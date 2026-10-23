import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

struct ConfigurationLanguageTests {
    @Test func yamlAndCommentedConfigurationsUseTheirOwnServices() {
        #expect(WebLanguage.detect("pubspec.yaml") == .yaml)
        #expect(WebLanguage.detect(".github/workflows/test.YML") == .yaml)
        #expect(WebLanguage.yaml.service == .yaml && !WebLanguage.yaml.synchronizes(with: .typescript))
        for path in ["tsconfig.app.json", "jsconfig.test.json", ".vscode/settings.json", "x.jsonc"] {
            #expect(WebLanguage.detect(path) == .jsonc)
        }
        #expect(WebLanguage.detect("data.json") == .json)
        #expect(WebLanguage.detect("settings.json") == .json)
        #expect(WebLanguage.jsonc.isJSON && !WebLanguage.yaml.isJSON)
        #expect(
            WebLanguage.json.isConfiguration && WebLanguage.yaml.isConfiguration
                && !WebLanguage.typescript.isConfiguration)
        let tools = WebToolchain(node: URL(fileURLWithPath: "/node"), services: URL(fileURLWithPath: "/services"))
        #expect(tools.arguments(.yaml).suffix(2) == ["yaml", "--stdio"])
        #expect(tools.script(.json).path.hasSuffix("native/config-language-server.mjs"))
    }
    @Test func boundedCatalogBuildsOnlyDeclaredJsonAndYamlAssociations() throws {
        let data = Data(
            #"{"schema":1,"schemas":[{"uri":"https://json.schemastore.org/demo","fileMatch":["demo.yaml"],"languages":["yaml"]},{"uri":"https://json.schemastore.org/other","fileMatch":["other.json"],"languages":["json"]}]}"#
                .utf8)
        let settings = try ConfigurationSchemas.configured(
            JSONValue(["json": ["format": ["enable": true]], "yaml": ["validate": true]]), data: data)
        #expect(settings["json"]["schemas"].array.count == 1)
        #expect(settings["yaml"]["schemas"]["https://json.schemastore.org/demo"].array == [.string("demo.yaml")])
        #expect(settings["yaml"]["validate"] == .bool(true))
        #expect(throws: LanguageServiceFailure.self) {
            try ConfigurationSchemas.configured(settings, data: Data(repeating: 32, count: 65537))
        }
        #expect(throws: LanguageServiceFailure.self) {
            try ConfigurationSchemas.configured(settings, data: Data(#"{"schema":2,"schemas":[]}"#.utf8))
        }
    }
    @Test func configDiscoveryIncludesKnownFoldersButNeverDependenciesOrPrivateDirectories() throws {
        #expect(ProjectSourceCatalog.allows(".github/workflows/build.yaml"))
        #expect(ProjectSourceCatalog.allows(".vscode/settings.json"))
        for path in [
            ".git/config", ".secret/schema.json", ".github/../outside.yaml", "node_modules/schema.json",
            "build/file.yaml",
        ] {
            #expect(!ProjectSourceCatalog.allows(path))
        }
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".github/workflows"), withIntermediateDirectories: true)
        try Data("name: CI\n".utf8).write(to: root.appendingPathComponent(".github/workflows/ci.yaml"))
        let files = try ProjectSourceCatalog.scan(root: root)
        #expect(files.files.contains { $0.path == ".github/workflows/ci.yaml" && $0.language == .yaml })
    }
    @Test func localSchemasDecodeUnicodeBomAndRemainInsideTheAuthorizedRoot() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("模式%.json")
        try Data([0xef, 0xbb, 0xbf] + Array("{\"title\":\"配置\"}".utf8)).write(to: file)
        #expect(try await ConfigurationSchemas.readLocal(file.absoluteString, root: root) == "{\"title\":\"配置\"}")
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("link.json").path, withDestinationPath: file.path)
        #expect(mkfifo(root.appendingPathComponent("fifo.json").path, 0o600) == 0)
        for uri in [
            "https://example.com/schema", "file:///outside/schema.json",
            root.appendingPathComponent("../outside.json").absoluteString,
            root.appendingPathComponent("link.json").absoluteString,
            root.appendingPathComponent("fifo.json").absoluteString,
        ] {
            do {
                _ = try await ConfigurationSchemas.readLocal(uri, root: root)
                Issue.record("Disallowed schema accepted")
            } catch {}
        }
    }
    @Test func schemaRequestsAcceptBothPinnedRpcParameterShapes() throws {
        #expect(try ConfigurationSchemas.requestURI(.string("file:///a.json")) == "file:///a.json")
        #expect(try ConfigurationSchemas.requestURI(.array([.string("file:///a.json")])) == "file:///a.json")
        #expect(throws: LanguageServiceFailure.self) { try ConfigurationSchemas.requestURI(.array([])) }
        #expect(throws: LanguageServiceFailure.self) {
            try ConfigurationSchemas.requestURI(.array([.string("a"), .string("b")]))
        }
    }
    @Test func schemaSizeAndCancellationAreBounded() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("huge.json")
        try Data(repeating: 32, count: 1_048_577).write(to: file)
        do {
            _ = try await ConfigurationSchemas.readLocal(file.absoluteString, root: root)
            Issue.record("Oversize schema accepted")
        } catch {}
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ConfigurationSchemas.readLocal(file.absoluteString, root: root)
        }
        do {
            _ = try await canceled.value
            Issue.record("Canceled schema read accepted")
        } catch is CancellationError {} catch { Issue.record("Unexpected cancellation error") }
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
