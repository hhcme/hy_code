import Foundation
import HyCodeWorkspace

extension WebProbe {
    static func checkConfigurations(_ tools: WebToolchain) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hycode-config-probe-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let server = WebLanguageServer(root: root, tools: tools)
        let inbox = WebInbox()
        let listener = Task { for await event in server.events { await inbox.receive(event) } }
        func open(_ path: String, language: WebLanguage, text: String) async throws -> URL {
            let file = root.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
            try await server.open(uri: file.absoluteString, language: language, text: text, version: 1)
            return file
        }
        func diagnostics(_ file: URL, service: String, contains predicate: @escaping (JSONValue) -> Bool) async throws
            -> JSONValue
        {
            for _ in 0..<200 {
                if let value = await inbox.get(file.absoluteString, service: service), predicate(value["diagnostics"]) {
                    return value["diagnostics"]
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            if let last = await inbox.get(file.absoluteString, service: service) {
                log(String(decoding: try JSONEncoder().encode(last), as: UTF8.self))
            }
            throw LanguageServiceFailure("Configuration diagnostics timeout: " + file.lastPathComponent)
        }
        do {
            let json = try await open("package.json", language: .json, text: "{\"name\":\"demo\",\"version\":42,}")
            let jsonErrors = try await diagnostics(json, service: "json", contains: { !$0.array.isEmpty })
            try require(
                jsonErrors.array.contains { $0["message"].string?.contains("string") == true },
                "Missing offline package schema type validation")
            log("PASS: JSON syntax and bundled package schema diagnostics")
            let jsoncText = "{ // preserved comment\n\"large\": 900719925474099312345, \"array\":[1,2,],\n}\n"
            let jsonc = try await open(".vscode/settings.json", language: .jsonc, text: jsoncText)
            _ = try await diagnostics(
                jsonc, service: "json", contains: { !$0.array.contains { $0["severity"].int == 1 } })
            let formattedJSON = try await server.request(
                "textDocument/formatting", uri: jsonc.absoluteString, position: nil)
            let jsonResult = try LSPTextEdits.apply(try formattedJSON.decode([LSPTextEdit].self), to: jsoncText)
            try require(
                jsonResult.contains("// preserved comment") && jsonResult.contains("900719925474099312345"),
                "JSONC formatting changed comments or numeric precision")
            let symbols = try await server.request(
                "textDocument/documentSymbol", uri: jsonc.absoluteString, position: nil)
            try require(!symbols.array.isEmpty, "Missing JSON structure")
            log("PASS: JSONC comments/trailing commas, precision-preserving formatting and structure")
            let pubspec = try await open("pubspec.yaml", language: .yaml, text: "name: 42\nversion: 1.0.0\n")
            _ = try await diagnostics(
                pubspec, service: "yaml", contains: { $0.array.contains { $0["severity"].int == 1 } })
            let completion = try await server.request(
                "textDocument/completion", uri: pubspec.absoluteString, position: .init(line: 2, character: 0))
            try require(!completion["items"].array.isEmpty, "Missing YAML schema completion")
            let hover = try await server.request(
                "textDocument/hover", uri: pubspec.absoluteString, position: .init(line: 0, character: 2))
            try require(hover["contents"] != .null, "Missing YAML schema hover")
            log("PASS: YAML offline pubspec validation, completion and hover")
            let yamlText = "base: &base\n  values: [ 1,2 ]\ncopy: *base\nlarge: 900719925474099312345\n"
            let yaml = try await open("anchors.yml", language: .yaml, text: yamlText)
            _ = try await diagnostics(yaml, service: "yaml", contains: { $0.array.isEmpty })
            let definitions = try await server.request(
                "textDocument/definition", uri: yaml.absoluteString, position: .init(line: 2, character: 8))
            try require(!LSPLocation.locations(definitions).isEmpty, "Missing YAML anchor definition")
            let rename = try await server.request(
                "textDocument/rename", uri: yaml.absoluteString, position: .init(line: 2, character: 8),
                parameters: ["newName": .string("renamed")])
            let changes = try LSPWorkspaceEdits.parse(rename, root: root)
            try require(changes.first?.edits.count == 2, "YAML anchor rename did not cover declaration and alias")
            let formattedYAML = try await server.request(
                "textDocument/formatting", uri: yaml.absoluteString, position: nil)
            let yamlResult = try LSPTextEdits.apply(try formattedYAML.decode([LSPTextEdit].self), to: yamlText)
            try require(
                yamlResult.contains("&base") && yamlResult.contains("*base") && yamlResult.contains("[1, 2]")
                    && yamlResult.contains("900719925474099312345"),
                "YAML format lost anchors or failed")
            let yamlSymbols = try await server.request(
                "textDocument/documentSymbol", uri: yaml.absoluteString, position: nil)
            try require(!yamlSymbols.array.isEmpty, "Missing YAML structure")
            log("PASS: YAML formatting, structure, anchor definition and rename preview")
            let localSchema = root.appendingPathComponent("schema.schema")
            try Data(
                #"{"type":"object","properties":{"port":{"type":"integer","description":"Local service port"}},"required":["port"]}"#
                    .utf8
            ).write(to: localSchema)
            let local = try await open(
                "local.yaml", language: .yaml, text: "# yaml-language-server: $schema=./schema.schema\nport: wrong\n")
            _ = try await diagnostics(
                local, service: "yaml",
                contains: { $0.array.contains { $0["message"].string?.contains("integer") == true } })
            let localJSON = try await open(
                "local.json", language: .json, text: "{\"$schema\":\"./schema.schema\",\"port\":\"wrong\"}")
            _ = try await diagnostics(
                localJSON, service: "json",
                contains: { $0.array.contains { $0["message"].string?.contains("integer") == true } })
            let localHover = try await server.request(
                "textDocument/hover", uri: localJSON.absoluteString, position: .init(line: 0, character: 30))
            try require(localHover["contents"] != .null, "Missing JSON schema hover")
            await inbox.clear(local.absoluteString, service: "yaml")
            await inbox.clear(localJSON.absoluteString, service: "json")
            try Data(
                #"{"type":"object","properties":{"port":{"type":"string","description":"Updated port"}},"required":["port"]}"#
                    .utf8
            ).write(to: localSchema)
            _ = try await server.checkProject(changed: [localSchema.absoluteString])
            _ = try await diagnostics(local, service: "yaml", contains: { $0.array.isEmpty })
            _ = try await diagnostics(localJSON, service: "json", contains: { $0.array.isEmpty })
            log("PASS: JSON local schema hover and saved schema dependency revalidation for JSON/YAML")
            await inbox.clear(local.absoluteString, service: "yaml")
            await inbox.clear(localJSON.absoluteString, service: "json")
            try Data(#"{"type":"object","properties":{"port":{"type":"integer"}}}"#.utf8)
                .write(to: localSchema)
            _ = try await server.checkProject()
            for (file, service) in [(local, "yaml"), (localJSON, "json")] {
                _ = try await diagnostics(
                    file, service: service,
                    contains: {
                        $0.array.contains { $0["message"].string?.contains("integer") == true }
                    })
            }
            log("PASS: full rescan invalidates saved schema dependencies in JSON/YAML")
            let remote = try await open(
                "remote.yaml", language: .yaml,
                text: "# yaml-language-server: $schema=https://127.0.0.1:1/never.json\nport: wrong\n")
            _ = try await diagnostics(
                remote, service: "yaml",
                contains: {
                    $0.array.contains {
                        $0["message"].string?.contains("Network schema downloads are disabled") == true
                    }
                })
            log("PASS: native project-local schema load and explicit remote schema refusal")
            let duplicate = try await open("duplicate.yml", language: .yaml, text: "name: first\nname: second\n")
            _ = try await diagnostics(duplicate, service: "yaml", contains: { !$0.array.isEmpty })
            let unopened = root.appendingPathComponent("unopened.yml")
            try Data("name: one\nname: two\n".utf8).write(to: unopened)
            let catalog = try await Task.detached(priority: .utility) { try ProjectSourceCatalog.scan(root: root) }
                .value
            try await server.setProjectFiles(catalog.files)
            _ = try await diagnostics(unopened, service: "yaml", contains: { !$0.array.isEmpty })
            log("PASS: unopened YAML file included in project diagnostics")
            // Exercise the same disk refresh used by watcher events. This URI
            // remains a live editor, so release it before testing background I/O.
            await server.close(uri: pubspec.absoluteString)
            await inbox.clear(pubspec.absoluteString, service: "yaml")
            try Data("name: valid_package\nversion: 1.0.0\n".utf8).write(to: pubspec)
            try await server.refreshProjectFiles(["pubspec.yaml"])
            _ = try await server.checkProject(changed: [pubspec.absoluteString])
            _ = try await diagnostics(pubspec, service: "yaml", contains: { $0.array.isEmpty })
            log("PASS: external pubspec disk refresh replaces background YAML diagnostics")
            try require(try Data(contentsOf: yaml) == Data(yamlText.utf8), "Service wrote source file")
            await server.stop()
            listener.cancel()
            log("PASS: configuration real-service probe; no GUI, project code, scripts or schema network requests")
        } catch {
            await server.stop()
            listener.cancel()
            throw error
        }
    }
}
