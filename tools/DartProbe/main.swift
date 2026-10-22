import Foundation
import HyCodeWorkspace

actor DiagnosticsInbox {
    var values: [String: [LSPDiagnostic]] = [:]
    func receive(_ value: JSONValue) throws {
        guard value["method"].string == "textDocument/publishDiagnostics",
            let uri = value["params"]["uri"].string
        else { return }
        values[uri] = try value["params"]["diagnostics"].decode([LSPDiagnostic].self)
    }
    func get(_ uri: String) -> [LSPDiagnostic]? { values[uri] }
    func clear(_ uri: String) { values[uri] = nil }

}

@main struct DartProbe {
    static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LanguageServiceFailure(message) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw LanguageServiceFailure("Usage: HyCodeDartProbe <Dart-or-Flutter-SDK-root>")
        }
        let sdk = try DartToolchain.discover(configured: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hycode-dart-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("main.dart")
        let text =
            "/// Example value.\nint answer = 42;\nvoid main(){\n  print(answer);\n  String bad = 1;\n}\nfinal buffer = StringBuffer();\n"
        try Data(text.utf8).write(to: file)
        let model = root.appendingPathComponent("model.dart")
        let consumer = root.appendingPathComponent("consumer.dart")
        let unopened = root.appendingPathComponent("unopened.dart")
        try Data("int value = 1;\n".utf8).write(to: model)
        try Data("import 'model.dart';\nint amount = value;\n".utf8).write(to: consumer)
        try Data("int wrong = 'text';\n".utf8).write(to: unopened)
        let imports = try DartImportProbe(root: root)
        let server = DartLanguageServer()
        let inbox = DiagnosticsInbox()
        let listener = Task {
            for await event in server.events {
                if event["method"].string == "hycode/stderr" {
                    print("Analyzer stderr: \(event["params"]["message"].string ?? "")")
                }
                try? await inbox.receive(event)
            }
        }
        do {
            print("Initializing Dart analyzer")
            try await server.initialize(root: root, toolchain: sdk, cache: root.appendingPathComponent("cache"))
            _ = try await diagnostics(inbox, uri: unopened.absoluteString) { $0.contains { $0.severity == 1 } }
            let errors = try await diagnostics(inbox, uri: file.absoluteString) { $0.contains { $0.severity == 1 } }
            print("PASS: root analysis publishes unopened Dart diagnostics before didOpen")
            try await imports.run(server: server, inbox: inbox)
            try await server.open(uri: file.absoluteString, text: text, version: 0)
            try require(
                errors.contains { $0.severity == 1 && $0.range.start.line == 4 }, "Missing type diagnostic")
            let hover = try await server.request(
                "textDocument/hover", uri: file.absoluteString, position: LSPPosition(line: 3, character: 10))
            try require(hover["contents"] != .null, "Missing hover")
            let parsedHover = DartHoverContent(contents: hover["contents"])
            try require(
                !parsedHover.signature.isEmpty && !parsedHover.signature.contains("```"),
                "Signature was not extracted from SDK hover")
            let began = ContinuousClock.now
            let constructor = try await server.request(
                "textDocument/hover", uri: file.absoluteString, position: LSPPosition(line: 6, character: 18))
            let first = began.duration(to: .now)
            let repeated = ContinuousClock.now
            let again = try await server.request(
                "textDocument/hover", uri: file.absoluteString, position: LSPPosition(line: 6, character: 20))
            let repeatDuration = repeated.duration(to: .now)
            let constructorCard = DartHoverContent(contents: constructor["contents"])
            try require(
                constructorCard.signature.contains("StringBuffer")
                    && constructorCard.declaration.contains("StringBuffer") && !constructorCard.documentation.isEmpty,
                "SDK constructor hover lost signature, declaration or docs")
            try require(
                DartHoverContent(contents: again["contents"]) == constructorCard,
                "Moving inside SDK symbol changed card content")
            let source = text as NSString
            let lines = TextLineIndex(text, unicodeLineSeparators: false)
            let symbolOffset = LSPPosition(line: 6, character: 18).offset(in: lines, source: source)!
            let hoverRange = try constructor["range"].decode(LSPRange.self).range(in: lines, source: source)
            try require(
                hoverRange == DartHoverTarget.range(at: symbolOffset, in: source),
                "SDK hover and local symbol range disagree")
            func milliseconds(_ value: Duration) -> Double {
                Double(value.components.seconds) * 1_000 + Double(value.components.attoseconds) / 1e15
            }
            print(
                "Hover SDK fixture timings (not UI): first=\(milliseconds(first))ms repeat=\(milliseconds(repeatDuration))ms; signature=\(constructorCard.signature.count) declaration=\(constructorCard.declaration.count) docs=\(constructorCard.documentation.count) chars"
            )
            let definition = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: LSPPosition(line: 3, character: 10))
            let definitions = try LSPLocation.locations(definition)
            try require(definitions.first?.range.start.line == 1, "Incorrect definition")
            let sdkDefinition = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: LSPPosition(line: 3, character: 4))
            let sdkTargets = try LSPLocation.locations(sdkDefinition)
            try require(
                sdkTargets.contains { URL(string: $0.uri)?.path.hasPrefix(sdk.dartSDK.path + "/") == true },
                "Missing SDK source definition")
            let references = try await server.request(
                "textDocument/references", uri: file.absoluteString, position: LSPPosition(line: 1, character: 5))
            try require(try LSPLocation.locations(references).count >= 2, "Missing references")
            let completion = try await server.request(
                "textDocument/completion", uri: file.absoluteString, position: LSPPosition(line: 3, character: 4))
            try require(!completion["items"].array.isEmpty || !completion.array.isEmpty, "Missing completion")
            let symbols = try await server.request("textDocument/documentSymbol", uri: file.absoluteString)
            try require(
                symbols.array.contains { $0["name"].string == "main" && $0["selectionRange"] != .null },
                "Missing hierarchical document symbols")
            await inbox.clear(file.absoluteString)
            try await server.change(
                uri: file.absoluteString,
                range: LSPRange(start: LSPPosition(line: 4, character: 15), end: LSPPosition(line: 4, character: 16)),
                text: "'ok'", version: 1)
            let fixed = try await diagnostics(inbox, uri: file.absoluteString) { !$0.contains { $0.severity == 1 } }
            try require(!fixed.contains { $0.severity == 1 }, "Unsaved incremental fix not analyzed")
            let edits = try await server.request("textDocument/formatting", uri: file.absoluteString)
            try require(edits != .null, "Formatting request failed")
            try require(try Data(contentsOf: file) == Data(text.utf8), "Analysis modified disk text")
            try await server.open(uri: model.absoluteString, text: "int value = 1;\n", version: 0)
            await inbox.clear(consumer.absoluteString)
            try await server.change(
                uri: model.absoluteString,
                range: LSPRange(start: .init(line: 0, character: 0), end: .init(line: 1, character: 0)),
                text: "String value = 'changed';\n", version: 1)
            _ = try await diagnostics(inbox, uri: consumer.absoluteString) { $0.contains { $0.severity == 1 } }
            try require(
                try String(contentsOf: model, encoding: .utf8) == "int value = 1;\n",
                "Reverse dependency analysis wrote disk")
            await inbox.clear(consumer.absoluteString)
            await server.close(uri: model.absoluteString)
            _ = try await diagnostics(inbox, uri: consumer.absoluteString) { !$0.contains { $0.severity == 1 } }
            print("PASS: unsaved Dart dependency change checks unopened importer, close restores disk analysis")
            await server.close(uri: file.absoluteString)
            await server.stop()
            listener.cancel()
            print(
                "PASS: Dart \(sdk.dartVersion), diagnostics / unsaved change / hover / definition / references / completion / document symbols / formatting / unchanged disk. No GUI, pub, network packages or user project."
            )
        } catch {
            await server.stop()
            listener.cancel()
            throw error
        }
    }
    static func diagnostics(_ inbox: DiagnosticsInbox, uri: String, predicate: @Sendable ([LSPDiagnostic]) -> Bool)
        async throws -> [LSPDiagnostic]
    {
        for _ in 0..<300 {
            if let result = await inbox.get(uri), predicate(result) { return result }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw LanguageServiceFailure("Diagnostics timed out at " + (URL(string: uri)?.lastPathComponent ?? uri))
    }
}
