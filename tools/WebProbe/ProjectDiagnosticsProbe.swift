import Foundation
import HyCodeWorkspace

extension WebProbe {
    static func checkWorkspaceProject(_ tools: WebToolchain) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hycode-project-probe-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let text = "export let value = 1;\n"
        let contents = [
            "tsconfig.json":
                #"{"compilerOptions":{"strict":true,"module":"ESNext","moduleResolution":"bundler","target":"ES2022","resolveJsonModule":true,"allowSyntheticDefaultImports":true}}"#,
            "model.ts": text,
            "consumer.ts": "import { value } from './model';\nexport const amount: number = value;\n",
            "unopened.ts": "export const broken: number = 'wrong';\n",
            "unrelated.ts": "export const stable: number = 1;\n",
            "settings.json": #"{"n":1}"#,
            "json-consumer.ts": "import settings from './settings.json';\nexport const n: number = settings.n;\n",
            "blocked.vue": "<template><div/></template>",
            "style.scss": ".demo { unknown-property: red; }",
        ]
        for (path, text) in contents { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        // Escaping these bounded comments exceeds one 8 MiB LSP body if the
        // initial eight-file registration is not split by wire budget.
        let escaped = "/*" + String(repeating: "\u{1}", count: 250_000) + "*/\nexport {};\n"
        for index in 0..<8 { try Data(escaped.utf8).write(to: root.appendingPathComponent("bulk\(index).ts")) }
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary.css"))
        let server = WebLanguageServer(root: root, tools: tools)
        let inbox = WebInbox()
        let listener = Task { for await event in server.events { await inbox.receive(event) } }
        do {
            let settings = root.appendingPathComponent("settings.json")
            let jsonConsumer = root.appendingPathComponent("json-consumer.ts")
            try await server.open(uri: settings.absoluteString, language: .json, text: #"{"n":"initial"}"#, version: 0)
            let catalog = try ProjectSourceCatalog.scan(root: root)
            log("Project fixture catalog: " + catalog.files.map(\.path).joined(separator: ", "))
            try await server.setProjectFiles(catalog.files)
            let first = try await server.checkProject()
            try require(first.checked.count == 13 && first.fullSweep, "Initial project scope omitted TS files")
            let scope = await server.projectScope()
            try require(
                scope.failed == 1 && scope.blockedVue == 1, "Unsupported file and untrusted Vue must mark partial scope"
            )
            try await waitFor(inbox, jsonConsumer) { $0.array.contains { $0["severity"].int == 1 } }
            await inbox.clear(jsonConsumer.absoluteString)
            try await server.change(
                uri: settings.absoluteString,
                range: LSPRange(start: .init(line: 0, character: 5), end: .init(line: 0, character: 14)),
                text: "1", version: 1)
            _ = try await server.checkProject(changed: [settings.absoluteString])
            try await waitFor(inbox, jsonConsumer) { !$0.array.contains { $0["severity"].int == 1 } }
            await server.close(uri: settings.absoluteString)
            let unopened = root.appendingPathComponent("unopened.ts")
            try await waitFor(inbox, unopened) { $0.array.contains { $0["severity"].int == 1 } }
            try await waitFor(inbox, root.appendingPathComponent("style.scss")) { !$0.array.isEmpty }
            let model = root.appendingPathComponent("model.ts")
            let consumer = root.appendingPathComponent("consumer.ts")
            try await server.open(uri: model.absoluteString, language: .typescript, text: text, version: 0)
            let range = (text as NSString).range(of: "1")
            let lines = TextLineIndex(text, unicodeLineSeparators: false)
            await inbox.clear(consumer.absoluteString)
            try await server.change(
                uri: model.absoluteString,
                range: LSPRange(start: .at(range.location, in: lines), end: .at(NSMaxRange(range), in: lines)),
                text: "'text'", version: 1)
            let next = try await server.checkProject(changed: [model.absoluteString])
            try require(
                !next.fullSweep && Set(next.checked) == [model.absoluteString, consumer.absoluteString],
                "Incremental project scope must include reverse import and exclude unrelated files")
            try await waitFor(inbox, consumer) { $0.array.contains { $0["severity"].int == 1 } }
            try require(try Data(contentsOf: model) == Data(text.utf8), "Unsaved project check wrote source")
            await inbox.clear(consumer.absoluteString)
            await server.close(uri: model.absoluteString)
            _ = try await server.checkProject(changed: [model.absoluteString])
            try await waitFor(inbox, consumer) { !$0.array.contains { $0["severity"].int == 1 } }
            let settingsText = #"{"n":"wrong"}"#
            try Data(settingsText.utf8).write(to: settings)
            await inbox.clear(jsonConsumer.absoluteString)
            try await server.refreshProjectFiles(["settings.json"])
            _ = try await server.checkProject(changed: [settings.absoluteString])
            try await waitFor(inbox, jsonConsumer) { $0.array.contains { $0["severity"].int == 1 } }
            try await server.open(uri: settings.absoluteString, language: .json, text: settingsText, version: 0)
            await inbox.clear(jsonConsumer.absoluteString)
            try await server.change(
                uri: settings.absoluteString,
                range: LSPRange(start: .init(line: 0, character: 5), end: .init(line: 0, character: 12)),
                text: "2", version: 1)
            _ = try await server.checkProject(changed: [settings.absoluteString])
            try await waitFor(inbox, jsonConsumer) { !$0.array.contains { $0["severity"].int == 1 } }
            try require(
                try String(contentsOf: settings, encoding: .utf8) == settingsText, "JSON dependency overlay wrote disk")
            await server.close(uri: settings.absoluteString)
            // A disk update must replace the raw tsserver background snapshot.
            try Data("export let value = 'external';\n".utf8).write(to: model)
            await inbox.clear(consumer.absoluteString)
            try await server.refreshProjectFiles(["model.ts"])
            _ = try await server.checkProject(changed: [model.absoluteString])
            try await waitFor(inbox, consumer) { $0.array.contains { $0["severity"].int == 1 } }
            try fm.removeItem(at: model)
            await inbox.clear(consumer.absoluteString)
            try await server.refreshProjectFiles(["model.ts"])
            let removed = try await server.checkProject(changed: [model.absoluteString])
            try require(removed.fullSweep, "Deleted dependency must recheck surviving importers")
            try await waitFor(inbox, consumer) { $0.array.contains { $0["code"].int == 2307 } }
            await inbox.clear(unopened.absoluteString)
            try fm.removeItem(at: unopened)
            try await server.setProjectFiles(ProjectSourceCatalog.scan(root: root).files)
            try await waitFor(inbox, unopened) { $0.array.isEmpty }
            try await server.setProjectFiles([])
            let empty = await server.projectScope()
            try require(empty.total == 0, "Empty project retained background registrations")
            try await waitFor(inbox, consumer) { $0.array.isEmpty }
            await server.stop()
            listener.cancel()
            log(
                "PASS: project-wide unopened TS/SCSS diagnostics, unsaved reverse-import check, unrelated exclusion, close-to-disk handoff, JSON cross-service overlays, disk refresh, deleted dependency and empty-scope cleanup"
            )
        } catch {
            await server.stop()
            listener.cancel()
            throw error
        }
    }
    static func waitFor(_ inbox: WebInbox, _ file: URL, predicate: @Sendable (JSONValue) -> Bool) async throws {
        for _ in 0..<600 {
            if let value = await inbox.get(file.absoluteString), predicate(value["diagnostics"]) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw LanguageServiceFailure("Project diagnostics timeout: " + file.lastPathComponent)
    }
}
