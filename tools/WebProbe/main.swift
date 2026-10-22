import Foundation
import HyCodeWorkspace

actor WebInbox {
    var values: [String: JSONValue] = [:]
    var services: [String: JSONValue] = [:]
    func receive(_ event: JSONValue) {
        if event["method"].string == "textDocument/publishDiagnostics", let uri = event["params"]["uri"].string {
            values[uri] = event["params"]
            services[uri + "|" + (event["hycodeService"].string ?? "")] = event["params"]
        }
    }
    func get(_ uri: String) -> JSONValue? { values[uri] }
    func get(_ uri: String, service: String) -> JSONValue? { services[uri + "|" + service] }
    func clear(_ uri: String) { values[uri] = nil }
}

@main struct WebProbe {
    static func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw LanguageServiceFailure(message) }
    }
    static func main() async {
        do { try await run() } catch {
            log("FAIL: " + error.localizedDescription)
            exit(1)
        }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw LanguageServiceFailure("Usage: HyCodeWebProbe /path/to/node /path/to/web-language-services")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "hycode-web-probe-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let tools = try WebToolchain.discover(
            configured: CommandLine.arguments[1], services: URL(fileURLWithPath: CommandLine.arguments[2]))
        try await checkWorkspaceProject(tools)
        try await checkUntrustedJavaScript(tools)
        let settings =
            #"{"compilerOptions":{"strict":true,"allowJs":true,"checkJs":true,"jsx":"preserve","target":"ES2022","module":"ESNext","moduleResolution":"bundler"},"include":["**/*"]}"#
        try Data(settings.utf8).write(to: root.appendingPathComponent("tsconfig.json"))
        try Data(#"{"name":"hycode-probe","version":"1.0.0"}"#.utf8).write(
            to: root.appendingPathComponent("package.json"))
        let source = "export const count: number = 'oops';\nexport const other = count;\n"
        let file = root.appendingPathComponent("main.ts")
        try Data(source.utf8).write(to: file)
        let server = WebLanguageServer(root: root, tools: tools, trace: true, allowProjectPlugins: true)
        let inbox = WebInbox()
        let listener = Task {
            for await event in server.events {
                if event["method"].string == "hycode/serviceEvent" {
                    log(
                        "Event " + (event["params"]["service"].string ?? "") + ": "
                            + (event["params"]["method"].string ?? ""))
                }
                if event["method"].string == "hycode/stderr" {
                    log("Service stderr: " + (event["params"]["message"].string ?? ""))
                }
                await inbox.receive(event)
            }
        }
        do {
            log("Opening TypeScript fixture")
            try await server.open(uri: file.absoluteString, language: .typescript, text: source, version: 0)
            try require(
                try await errors(inbox, file).array.contains { $0["severity"].int == 1 }, "Missing TS type error")
            let position = LSPPosition(line: 1, character: 23)
            let hover = try await server.request("textDocument/hover", uri: file.absoluteString, position: position)
            try require(hover["contents"] != .null, "Missing TS hover")
            let definitions = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: position)
            try require(try LSPLocation.locations(definitions).first?.range.start.line == 0, "Wrong TS definition")
            let refs = try await server.request("textDocument/references", uri: file.absoluteString, position: position)
            try require(try LSPLocation.locations(refs).count >= 2, "Missing TS references")
            let completion = try await server.request(
                "textDocument/completion", uri: file.absoluteString,
                position: LSPPosition(line: 1, character: 22))
            try require(!completion.array.isEmpty || !completion["items"].array.isEmpty, "Missing TS completion")
            await inbox.clear(file.absoluteString)
            try await server.change(
                uri: file.absoluteString,
                range: LSPRange(start: LSPPosition(line: 0, character: 29), end: LSPPosition(line: 0, character: 35)),
                text: "42", version: 1)
            let fixed = try await errors(inbox, file)
            try require(!fixed.array.contains { $0["severity"].int == 1 }, "Unsaved TS change was not analyzed")
            let symbols = try await server.request(
                "textDocument/documentSymbol", uri: file.absoluteString, position: nil)
            try require(!symbols.array.isEmpty, "Missing TS symbols")
            let rename = try await server.request(
                "textDocument/rename", uri: file.absoluteString, position: position,
                parameters: ["newName": .string("total")])
            try require(rename["changes"] != .null || rename["documentChanges"] != .null, "Missing TS rename edits")
            log(
                "PASS: TypeScript diagnostics, unsaved fix, hover, definitions, references, completion, symbols, rename protocol"
            )
            try Data("export function greet(name: string) { return name; }\n".utf8).write(
                to: root.appendingPathComponent("helper.ts"))
            let importFile = root.appendingPathComponent("import-completion.ts")
            try Data("gre".utf8).write(to: importFile)
            try await server.open(uri: importFile.absoluteString, language: .typescript, text: "gre", version: 0)
            _ = try await errors(inbox, importFile)
            let imports = try await server.request(
                "textDocument/completion", uri: importFile.absoluteString, position: .init(line: 0, character: 3))
            guard let item = imports["items"].array.first(where: { $0["label"].string == "greet" }),
                case .object(let fields) = item
            else { throw LanguageServiceFailure("Missing auto-import completion") }
            let resolved = try await server.request(
                "completionItem/resolve", uri: importFile.absoluteString, position: nil, parameters: fields)
            let primary =
                (try? resolved["textEdit"].decode(LSPTextEdit.self))
                ?? LSPTextEdit(
                    range: LSPRange(start: .init(line: 0, character: 0), end: .init(line: 0, character: 3)),
                    newText: resolved["insertText"].string ?? "greet")
            let additional = try resolved["additionalTextEdits"].decode([LSPTextEdit].self)
            try require(!additional.isEmpty, "Completion resolve omitted auto-import")
            let completed = try LSPTextEdits.apply([primary] + additional, to: "gre")
            let caret = try LSPTextEdits.completionOffset(primary: primary, additional: additional, text: "gre")
            try require(
                completed.contains("import") && completed.hasSuffix("greet") && caret == completed.utf16.count,
                "Auto-import edits or caret invalid")
            try require(try Data(contentsOf: importFile) == Data("gre".utf8), "Completion changed source on disk")
            await server.close(uri: importFile.absoluteString)
            log("PASS: resolved auto-import completion, simultaneous import/replacement edits and caret")
            let useFile = root.appendingPathComponent("use-greet.ts")
            let useText = "import { greet } from './helper';\ngreet('hello');\n"
            try Data(useText.utf8).write(to: useFile)
            try await server.open(uri: useFile.absoluteString, language: .typescript, text: useText, version: 0)
            _ = try await errors(inbox, useFile)
            let declaration = root.appendingPathComponent("helper.ts")
            try await server.open(
                uri: declaration.absoluteString, language: .typescript,
                text: "export function greet(name: string) { return name; }\n", version: 0)
            let multiRename = try await server.request(
                "textDocument/rename", uri: declaration.absoluteString,
                position: .init(line: 0, character: 18), parameters: ["newName": .string("welcome")])
            let renameFiles = try LSPWorkspaceEdits.parse(multiRename, root: root)
            try require(renameFiles.count >= 2, "Rename did not include declaration and caller")
            for change in renameFiles {
                let before = try String(contentsOf: root.appendingPathComponent(change.path), encoding: .utf8)
                let after = try LSPTextEdits.apply(change.edits, to: before)
                try require(after.contains("welcome"), "Invalid multi-file rename range")
            }
            await server.close(uri: useFile.absoluteString)
            await server.close(uri: declaration.absoluteString)
            log("PASS: real multi-file rename parsed and applied to immutable declaration/caller snapshots")
            for (name, language, text) in [
                ("index.html", WebLanguage.html, "<html><body><div class=\"x\">hello</div></body></html>"),
                ("main.scss", .scss, ".demo { color: red; unknown-property: 12; }"),
                ("settings.json", .json, "{\"name\": }"),
                (
                    "Component.vue", .vue,
                    "<script setup lang=\"ts\">\nconst count: number = 'oops';\n</script>\n<template><div>{{ count.toFixed(2) }}</div></template>\n<style>\n.demo { colr: red; }\n</style>\n"
                ),
            ] {
                let url = root.appendingPathComponent(name)
                try Data(text.utf8).write(to: url)
                log("Opening " + language.rawValue + " fixture")
                try await server.open(uri: url.absoluteString, language: language, text: text, version: 0)
                log("Opened " + language.rawValue + "; waiting for diagnostics")
                if language != .html {
                    let result = try await errors(inbox, url)
                    try require(!result.array.isEmpty, "Missing \(language.rawValue) diagnostics")
                }
                log("Formatting " + language.rawValue)
                let formatted = try await server.request(
                    "textDocument/formatting", uri: url.absoluteString, position: nil)
                if language != .vue { try require(formatted != .null, "Missing \(language.rawValue) formatting") }
                if language == .vue {
                    let value = try await server.request(
                        "textDocument/hover", uri: url.absoluteString,
                        position: LSPPosition(line: 3, character: 27))
                    try require(value["contents"] != .null, "Missing Vue template hover / TS bridge")
                    var diagnostics: [JSONValue] = []
                    for _ in 0..<400 {
                        diagnostics = await inbox.get(url.absoluteString, service: "vue")?["diagnostics"].array ?? []
                        if diagnostics.contains(where: { $0["data"] != .null && $0["range"]["start"]["line"].int == 5 })
                        {
                            break
                        }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    let original = try JSONValue.array(diagnostics).decode([LSPDiagnostic].self)
                    let context = original.filter { $0.range.start.line == 5 }.map { item -> JSONValue in
                        guard case .object(var value) = item.raw else { return item.raw }
                        value["hycodeService"] = .string("vue")
                        return .object(value)
                    }
                    try require(!context.isEmpty, "Missing Vue CSS diagnostic provider data")
                    let actions = try await server.request(
                        "textDocument/codeAction", uri: url.absoluteString, position: nil,
                        parameters: [
                            "range": LSPRange(start: .init(line: 5, character: 8), end: .init(line: 5, character: 12))
                                .json,
                            "context": JSONValue(["diagnostics": context]),
                        ])
                    try require(!actions.array.isEmpty, "Missing Vue diagnostic-driven quick fix")
                    log("PASS: Vue embedded CSS diagnostic metadata round-trip and quick fix")
                }
                try require(try Data(contentsOf: url) == Data(text.utf8), "Service changed source on disk")
                await server.close(uri: url.absoluteString)
            }
            try require(try Data(contentsOf: file) == Data(source.utf8), "TS service wrote unsaved buffer to disk")
            log("Vue bridge counters: \(await server.bridgeRequests) / \(await server.bridgeResponses)")
            await server.stop()
            listener.cancel()
            log(
                "PASS: real Web services on generated temporary fixtures; no GUI, browser, project scripts or npm lifecycle execution"
            )
        } catch {
            log(
                "FAIL: \(error.localizedDescription); bridge counters \(await server.bridgeRequests) / \(await server.bridgeResponses)"
            )
            await server.stop()
            listener.cancel()
            throw error
        }
    }
    static func errors(_ inbox: WebInbox, _ file: URL) async throws -> JSONValue {
        for _ in 0..<400 {
            if let value = await inbox.get(file.absoluteString) { return value["diagnostics"] }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw LanguageServiceFailure("Diagnostics timeout: " + file.lastPathComponent)
    }
    static func checkUntrustedJavaScript(_ tools: WebToolchain) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hycode-web-untrusted-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("main.js")
        let text = "const count = 1;\ncount.toUpperCase();\n"
        try Data(text.utf8).write(to: file)
        let server = WebLanguageServer(root: root, tools: tools)
        let inbox = WebInbox()
        let listener = Task { for await event in server.events { await inbox.receive(event) } }
        do {
            try await server.open(uri: file.absoluteString, language: .javascript, text: text, version: 0)
            try require(
                try await errors(inbox, file).array.contains { $0["severity"].int == 1 },
                "Missing inferred JS type check")
            let plugin = root.appendingPathComponent("node_modules/hycode-canary")
            try fm.createDirectory(at: plugin, withIntermediateDirectories: true)
            try Data(#"{"name":"hycode-canary","main":"index.js"}"#.utf8).write(
                to: plugin.appendingPathComponent("package.json"))
            try Data(
                #"require('node:fs').writeFileSync(require('node:path').join(__dirname, '../../plugin-ran'), 'ran'); module.exports = () => ({create: info => info.languageService});"#
                    .utf8
            ).write(to: plugin.appendingPathComponent("index.js"))
            try Data(
                #"{"compilerOptions":{"allowJs":true,"checkJs":true,"plugins":[{"name":"hycode-canary"}]},"vueCompilerOptions":{"plugins":["./node_modules/hycode-canary/index.js"]}}"#
                    .utf8
            ).write(to: root.appendingPathComponent("tsconfig.json"))
            let ts = root.appendingPathComponent("main.ts")
            try Data("const count: number = 'wrong';".utf8).write(to: ts)
            try await server.open(
                uri: ts.absoluteString, language: .typescript, text: "const count: number = 'wrong';", version: 0)
            _ = try await errors(inbox, ts)
            await server.stop()
            listener.cancel()
            try require(
                !fm.fileExists(atPath: root.appendingPathComponent("plugin-ran").path),
                "Untrusted project plugin executed")
            log("PASS: inferred JS type checking without jsconfig; untrusted TS/Vue plugin canary not executed")
        } catch {
            await server.stop()
            listener.cancel()
            throw error
        }
    }
}
