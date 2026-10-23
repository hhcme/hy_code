import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

struct NativeLanguageTests {
    @Test func routingAndMissingToolsDoNotLaunchAnything() throws {
        #expect(NativeCodeLanguage.detect("Sources/Model.SWIFT") == .swift)
        #expect(NativeCodeLanguage.detect("Demo.java") == .java)
        #expect(NativeCodeLanguage.detect("schema.SQL") == .sql)
        #expect(NativeCodeLanguage.detect("main.dart") == nil)
        #expect(throws: LanguageServiceFailure.self) {
            try NativeLanguageToolchain.discover(
                .swift, settings: NativeLanguageSettings(sourceKitPath: "/missing/sourcekit-lsp"))
        }
        #expect(throws: LanguageServiceFailure.self) {
            try NativeLanguageToolchain.discover(.java, settings: NativeLanguageSettings(javaHome: "/missing/jdk"))
        }
    }
    @Test func catalogAndReadsExcludeLinksAndBuildOutput() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-native-catalog-" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "let name = \"中文😀\"\n"
        var bom = Data([0xff, 0xfe])
        bom.append(text.data(using: .utf16LittleEndian)!)
        try bom.write(to: root.appendingPathComponent("Sources/Model.swift"))
        try "create table users(id integer);".write(
            to: root.appendingPathComponent("schema.sql"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.sql"), withDestinationURL: root.appendingPathComponent("schema.sql")
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: root.appendingPathComponent(".build/Generated.java"))
        let catalog = try NativeSourceCatalog.scan(root: root)
        #expect(catalog.files.map(\.path) == ["Sources/Model.swift", "schema.sql"])
        #expect(try NativeSourceCatalog.read(path: "Sources/Model.swift", root: root) == text)
        #expect(throws: WorkspaceFailure.self) { try NativeSourceCatalog.read(path: "linked.sql", root: root) }
        #expect(throws: LanguageServiceFailure.self) {
            try NativeSourceCatalog.read(path: "../outside.sql", root: root)
        }
        let fifo = root.appendingPathComponent("pipe.sql")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: WorkspaceFailure.self) { try NativeSourceCatalog.read(path: "pipe.sql", root: root) }
    }
    @Test func untrustedServiceDoesNotCreateCacheOrStartTool() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HyCode-trust-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Metadata discovery may find the real toolchain, but the trust refusal
        // must occur before any cache creation/process launch.
        if let tools = try? NativeLanguageToolchain.discover(.swift, settings: NativeLanguageSettings()) {
            let server = NativeLanguageServer(language: .swift)
            let cache = root.appendingPathComponent("must-not-exist")
            await #expect(throws: LanguageServiceFailure.self) {
                try await server.initialize(root: root, tools: tools, cache: cache, trusted: false)
            }
            #expect(!FileManager.default.fileExists(atPath: cache.path))
            await server.stop()
        }
    }
    @Test func sqlDialectDiagnosticsCommentsAndFormatting() throws {
        let source =
            "-- 😀 中文\r\ncreate table \"用户\" (\"名字\" text, id integer);\r\nselect 'a  b', id /* keep */ from \"用户\";\r\n"
        let result = try SQLAnalyzer.analyze(source, dialect: .postgresql, formatting: true)
        #expect(result.diagnostics.isEmpty && result.tables.count == 1)
        #expect(result.tables[0].name == "用户")
        #expect(result.tables[0].columns[0].range.start.line == 1)
        #expect(result.formatted?.contains("'a  b'") == true)
        #expect(result.formatted?.contains("/* keep */") == true)
        #expect(result.formatted?.contains("-- 😀 中文\r\n") == true)
        #expect(try SQLAnalyzer.analyze("select `name` from users;", dialect: .mysql).diagnostics.isEmpty)
        #expect(try !SQLAnalyzer.analyze("select `name` from users;", dialect: .postgresql).diagnostics.isEmpty)
        #expect(throws: LanguageServiceFailure.self) {
            try SQLAnalyzer.analyze(String(repeating: " ", count: 256 * 1024 + 1), dialect: .generic)
        }
        let bad = try SQLAnalyzer.analyze("select * from ;", dialect: .generic)
        #expect(bad.diagnostics.first?.severity == 1)
    }
    @Test func sqlDDLCompletionNavigationAndUnsavedIncrement() async throws {
        let service = SQLLanguageService(dialect: .sqlite)
        let schema = "create table users (id integer, name text);"
        let uri = "file:///owned/schema.sql"
        let queryURI = "file:///owned/query.sql"
        let query = "select users.name from users;"
        try await service.open(uri: uri, text: schema, version: 0)
        try await service.open(uri: queryURI, text: query, version: 0)
        let complete = try await service.request(
            "textDocument/completion", uri: queryURI, position: nil, parameters: [:])
        #expect(complete["items"].array.contains { $0["label"].string == "users" })
        #expect(complete["items"].array.contains { $0["label"].string == "name" })
        let definition = try await service.request(
            "textDocument/definition", uri: queryURI, position: LSPPosition(line: 0, character: 14), parameters: [:])
        #expect(definition.array.first?["uri"].string == uri)
        let hover = try await service.request(
            "textDocument/hover", uri: queryURI, position: LSPPosition(line: 0, character: 14), parameters: [:])
        #expect(hover["contents"]["value"].string?.contains("users.name") == true)
        let renameRange = (schema as NSString).range(of: "name")
        try await service.change(
            uri: uri,
            range: LSPRange(
                start: LSPPosition(line: 0, character: renameRange.location),
                end: LSPPosition(line: 0, character: NSMaxRange(renameRange))), text: "title", version: 1)
        let changed = try await service.request(
            "textDocument/completion", uri: queryURI, position: nil, parameters: [:])
        #expect(changed["items"].array.contains { $0["label"].string == "title" })
        #expect(!changed["items"].array.contains { $0["label"].string == "name" })
        await #expect(throws: LanguageServiceFailure.self) {
            try await service.change(
                uri: uri, range: LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 0)),
                text: "", version: 1)
        }
        await service.close(uri: uri)
        let closed = try await service.request("textDocument/completion", uri: queryURI, position: nil, parameters: [:])
        #expect(!closed["items"].array.contains { $0["label"].string == "users" })
        await service.stop()
        await #expect(throws: LanguageServiceFailure.self) {
            try await service.request("textDocument/hover", uri: queryURI, position: nil, parameters: [:])
        }
        for dialect in [SQLDialect.mysql, .bigquery] {
            let quoted = SQLLanguageService(dialect: dialect)
            try await quoted.open(uri: uri, text: "create table data (`display name` text);", version: 0)
            let completion = try await quoted.request(
                "textDocument/completion", uri: uri, position: nil, parameters: [:])
            let column = completion["items"].array.first { $0["label"].string == "display name" }
            #expect(column?["insertText"].string == "`display name`")
            await quoted.stop()
        }
    }
    @Test func sqlNavigationRequiresBoundTablesAndRejectsAmbiguity() async throws {
        let service = SQLLanguageService(dialect: .postgresql)
        let schemaURI = "file:///owned/schema.sql"
        let queryURI = "file:///owned/query.sql"
        try await service.open(
            uri: schemaURI,
            text:
                "create table users(id int, name text); create table orders(id int); create table Mixed(Col int); create table public.\"Quoted\"(id int);",
            version: 0)
        let samples: [(String, String, Bool)] = [
            ("select id from missing_table;", "id", false),
            ("select id from users u join orders o on u.id=o.id;", "id", false),
            ("select u.id from users u;", "id", true),
            ("select o.id from users u;", "id", false),
            ("with users as (select 1 as id) select id from users;", "id from", false),
            ("select id from (select 1 as id) users;", "id", false),
            ("select u.id from users u where exists (select u.id from (select 1 as id) u);", "u.id from (", false),
            ("select \"Col\" from \"Mixed\";", "Col", false),
            ("select \"col\" from \"mixed\";", "col", true),
            ("select \"U\".id from users U;", "id", false),
            ("select \"u\".id from users U;", "id", true),
            ("select id from public.\"Quoted\";", "id", false),
            ("select id as renamed from users having renamed > 0;", "renamed >", false),
        ]
        for (text, needle, expected) in samples {
            try await service.open(uri: queryURI, text: text, version: 0)
            let offset = (text as NSString).range(of: needle).location + (needle.hasPrefix("u.id") ? 2 : 0)
            let value = try await service.request(
                "textDocument/definition", uri: queryURI, position: LSPPosition(line: 0, character: offset),
                parameters: [:])
            #expect(!value.array.isEmpty == expected, "\(text)")
        }
        let completion = try await service.request(
            "textDocument/completion", uri: queryURI, position: nil, parameters: [:])
        #expect(!completion["items"].array.contains { $0["insertText"].string == "\"public.Quoted\"" })
        await service.stop()
    }
    @Test func diagnosticInboxIsBoundedAndRejectsSameRevisionStaleWork() {
        var inbox = LanguageDiagnosticInbox()
        let uri = "file:///owned/a.swift"
        let offered = inbox.offer(uri: uri, version: 1, values: Array(repeating: .null, count: 2000))
        #expect(offered)
        let old = inbox.take()!
        #expect(old.values.count == 1000 && inbox.isCurrent(old))
        let replacement = inbox.offer(uri: uri, version: 1, values: [])
        #expect(replacement)
        #expect(!inbox.isCurrent(old))
        #expect(inbox.count == 1)
        for i in 0..<31 {
            let accepted = inbox.offer(uri: "file:///owned/\(i).swift", version: 0, values: [])
            #expect(accepted)
        }
        let overflow = inbox.offer(uri: "file:///owned/overflow.swift", version: 0, values: [])
        #expect(!overflow)
        inbox.remove(uri)
        #expect(!inbox.isCurrent(old) && inbox.count == 31)
        inbox.reset()
        #expect(inbox.count == 0)
    }
    @Test func cachePathsURIMappingAndProjectModels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-native-paths-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        #expect(try !NativeWorkspacePaths.cacheIsOutsideProject(root: project, cache: project))
        #expect(
            try !NativeWorkspacePaths.cacheIsOutsideProject(
                root: project, cache: alias.appendingPathComponent("missing/cache")))
        #expect(try !NativeWorkspacePaths.cacheIsOutsideProject(root: URL(fileURLWithPath: "/"), cache: root))
        #expect(
            try NativeWorkspacePaths.cacheIsOutsideProject(root: project, cache: root.appendingPathComponent("cache")))
        let mapping = try NativeLanguageURIs(root: alias)
        let display = alias.appendingPathComponent("名字.swift").absoluteString
        let server = mapping.toServer(display)
        #expect(mapping.toClient(server) == display)
        let edit = JSONValue(["changes": [server: [["newText": server, "uri": server]]]])
        let mapped = mapping.project(edit, outgoing: false)
        #expect(mapped["changes"][display].array[0]["newText"].string == server)
        #expect(mapped["changes"][display].array[0]["uri"].string == display)
        #expect(mapping.project(mapped, outgoing: true) == edit)
        try Data().write(to: project.appendingPathComponent("Package.swift"))
        #expect(try NativeProjectModel.inspect(language: .swift, root: project) == .swiftPM)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Owned.xcodeproj"), withIntermediateDirectories: true)
        let bsp = JSONValue(["argv": ["/owned/build-server"], "languages": ["swift"]])
        try JSONEncoder().encode(bsp).write(to: project.appendingPathComponent("buildServer.json"))
        #expect(try NativeProjectModel.inspect(language: .swift, root: project) == .xcodeBuildServer)
        try Data("{}".utf8).write(to: project.appendingPathComponent("buildServer.json"))
        #expect(throws: LanguageServiceFailure.self) { try NativeProjectModel.inspect(language: .swift, root: project) }
    }
    @Test func nativeGrammarProjectionAndCancelledSQL() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-native-syntax-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, text, language) in [
            ("Model.swift", "public struct Counter { let value: Int = 1 }", "Swift"),
            ("Demo.java", "public class Demo { int value = 1; }", "Java"),
            ("schema.sql", "CREATE TABLE users(id INTEGER);", "SQL"),
        ] {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
            let document = NativeTextDocument(root: root, path: path)
            _ = try await document.open()
            let syntax = try await document.syntax(revision: 0, range: NSRange(location: 0, length: text.utf16.count))
            #expect(syntax.language == language && !syntax.spans.isEmpty)
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SQLAnalyzer.analyze("select 1;", dialect: .generic)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
