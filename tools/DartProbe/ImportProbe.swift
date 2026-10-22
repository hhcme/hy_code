import Foundation
import HyCodeWorkspace

/// Only generated fixtures and the SDK analyzer; no Pub install or GUI host.
struct DartImportProbe {
    let file: URL
    let text: String
    private let commented: [(URL, String)]
    init(root: URL) throws {
        let library = root.appendingPathComponent("lib/library.dart")
        let config = root.appendingPathComponent(".dart_tool/package_config.json")
        for directory in [library.deletingLastPathComponent(), config.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("/// Fixture library.\nlibrary;\nconst value = 42;\n".utf8).write(to: library)
        try JSONSerialization.data(withJSONObject: [
            "configVersion": 2,
            "packages": [["name": "hycode_probe", "rootUri": "../", "packageUri": "lib/", "languageVersion": "3.0"]],
        ]).write(to: config)
        file = root.appendingPathComponent("imports.dart")
        text = """
            import 'dart:async';
            import 'package:hycode_probe/library.dart' as p;
            import 'lib/library.dart' as r;
            import 'missing.dart';
            void main() { print(p.value); print(r.value); StreamController<int>(); }

            """
        try Data(text.utf8).write(to: file)
        commented = [
            (root.appendingPathComponent("commented.dart"), "import /*\nimport 'example.dart';\n*/ 'dart:async';\n"),
            (root.appendingPathComponent("prefix.dart"), "/* note */ import'dart:async';\n"),
            (
                root.appendingPathComponent("long_comment.dart"),
                "/*\n" + String(repeating: "header\n", count: 16) + "author's ''' note\n*/\nimport\n'dart:async';\n"
            ),
        ]
        for (file, text) in commented { try Data(text.utf8).write(to: file) }
    }
    func run(server: DartLanguageServer, inbox: DiagnosticsInbox) async throws {
        try await server.open(uri: file.absoluteString, text: text, version: 0)
        let source = text as NSString
        let lines = TextLineIndex(text, unicodeLineSeparators: false)
        for (line, uri) in ["dart:async", "package:hycode_probe/library.dart", "lib/library.dart"].enumerated() {
            let expected = source.range(of: uri)
            let hit = DartDirectiveTarget.range(at: NSMaxRange(expected) - 1, in: source, lines: lines)
            try DartProbe.require(hit == expected, "Local URI target was truncated for \(uri)")
            let position = LSPPosition.at(hit!.location, in: lines)
            let hover = try await server.request("textDocument/hover", uri: file.absoluteString, position: position)
            let content = DartHoverContent(contents: hover["contents"])
            let value = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: position)
            let targets = try LSPLocation.locations(value)
            try DartProbe.require(!targets.isEmpty, "Missing import definition for \(uri)")
            try DartProbe.require(
                content.signature.hasPrefix("library ") && content.declaration.hasPrefix("Declared in "),
                "Import hover lost library or declaration for \(uri)")
            let punctuation = source.range(of: uri.contains(":") ? ":" : "/", range: expected).location
            let repeated = try await server.request(
                "textDocument/hover", uri: file.absoluteString, position: .at(punctuation, in: lines))
            try DartProbe.require(
                DartHoverContent(contents: repeated["contents"]) == content,
                "URI punctuation changed library hover on line \(line)")
            print("Import fixture: \(uri); signature=\(content.signature); declaration=\(content.declaration)")
        }
        let missing = try await server.request(
            "textDocument/definition", uri: file.absoluteString, position: .init(line: 3, character: 8))
        try DartProbe.require(try LSPLocation.locations(missing).isEmpty, "Unresolved import became a link")
        let errors = try await DartProbe.diagnostics(inbox, uri: file.absoluteString) {
            $0.contains { $0.severity == 1 && $0.range.start.line == 3 }
        }
        let missingRange = source.range(of: "missing.dart")
        try DartProbe.require(
            errors.contains {
                guard $0.severity == 1, let range = $0.range.range(in: lines, source: source) else { return false }
                return NSIntersectionRange(range, missingRange).length > 0
            }, "Missing import diagnostic underline range")
        await server.close(uri: file.absoluteString)
        print("PASS: SDK, package and relative import hover/definition; unresolved import has no target")
        for (file, text) in commented {
            let source = text as NSString
            let lines = TextLineIndex(text, unicodeLineSeparators: false)
            let uri = source.range(of: "dart:async")
            try await server.open(uri: file.absoluteString, text: text, version: 0)
            try DartProbe.require(
                DartDirectiveTarget.range(at: NSMaxRange(uri) - 1, in: source, lines: lines) == uri,
                "Comment interrupted whole URI hit")
            let position = LSPPosition.at(uri.location, in: lines)
            let hover = try await server.request("textDocument/hover", uri: file.absoluteString, position: position)
            let definition = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: position)
            try DartProbe.require(
                DartHoverContent(contents: hover["contents"]).signature == "library dart:async"
                    && !(try LSPLocation.locations(definition)).isEmpty, "Commented import lost SDK link")
            _ = try await DartProbe.diagnostics(inbox, uri: file.absoluteString) { !$0.contains { $0.severity == 1 } }
            await server.close(uri: file.absoluteString)
        }
        print("PASS: commented directives and adjacent keyword/string retain actual SDK library navigation")
    }
}
