import Darwin
import Foundation
import HyCodeWorkspace

actor ProbeEvents {
    private var diagnostics: [String: JSONValue] = [:]
    func accept(_ event: JSONValue) {
        if event["method"].string == "hycode/stderr" { print("SERVER: " + (event["params"]["message"].string ?? "")) }
        if event["method"].string == "textDocument/publishDiagnostics", let uri = event["params"]["uri"].string {
            if diagnostics[uri] == nil { print("Diagnostic URI: " + uri) }
            diagnostics[uri] = event["params"]
        }
    }
    func errors(_ uri: String) -> Bool {
        diagnostics[uri]?["diagnostics"].array.contains { $0["severity"].int == 1 } ?? false
    }
    func described(_ uri: String) -> String { String(describing: diagnostics[uri] ?? .null).prefix(1000).description }
}

@main struct NativeLanguageProbe {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LanguageServiceFailure(message) }
    }
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data(("FAIL: " + String(describing: error) + "\n").utf8))
            exit(1)
        }
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let raw = args.first,
            let language = NativeCodeLanguage(rawValue: String(raw.split(separator: "-").first ?? "")), language != .sql
        else {
            throw LanguageServiceFailure(
                "Usage: HyCodeNativeLanguageProbe swift|swift-bsp [sourcekit-lsp] | java|java-maven <JAVA_HOME> <JDT_LS_ROOT>"
            )
        }
        let rawRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-native-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: rawRoot, withIntermediateDirectories: true)
        let root: URL
        if let physical = realpath(rawRoot.path, nil) {
            root = URL(fileURLWithPath: String(cString: physical))
            free(physical)
        } else {
            root = rawRoot
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-native-probe-cache-" + UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: cache)
        }
        let text: String
        let file: URL
        let settings: NativeLanguageSettings
        if language == .swift {
            let sources = root.appendingPathComponent("Sources/ProbeLibrary")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try
                "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"ProbeLibrary\", targets: [.target(name: \"ProbeLibrary\")])\n"
                .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            file = sources.appendingPathComponent("Model.swift")
            text =
                "public struct Counter { public var value: Int = 0 }\npublic func read(_ counter: Counter) -> Int { return counter.value }\npublic let invalid: Int = \"bad\"\n"
            settings = NativeLanguageSettings(sourceKitPath: args.count > 1 ? args[1] : "")
        } else {
            guard args.count == 3 else {
                throw LanguageServiceFailure("Java probe needs installed JAVA_HOME and JDT LS root")
            }
            if raw == "java-maven" {
                let sources = root.appendingPathComponent("src/main/java")
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                file = sources.appendingPathComponent("Demo.java")
                try
                    "<project xmlns=\"http://maven.apache.org/POM/4.0.0\"><modelVersion>4.0.0</modelVersion><groupId>owned.hycode</groupId><artifactId>fixture</artifactId><version>1.0</version><properties><maven.compiler.release>21</maven.compiler.release></properties></project>"
                    .write(to: root.appendingPathComponent("pom.xml"), atomically: true, encoding: .utf8)
            } else {
                file = root.appendingPathComponent("Demo.java")
            }
            text =
                "import java.util.List;\npublic class Demo {\n  /** A stored integer. */ public int value = 1;\n  public int read() { return this.value; }\n  public int invalid = \"bad\";\n}\n"
            settings = NativeLanguageSettings(javaHome: args[1], jdtlsPath: args[2])
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
        let tools = try NativeLanguageToolchain.discover(language, settings: settings)
        if raw == "swift-bsp" {
            try FileManager.default.removeItem(at: root.appendingPathComponent("Package.swift"))
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Owned.xcodeproj"), withIntermediateDirectories: true)
            let sdk = try await DeveloperToolTask().run(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--show-sdk-path"], directory: root
            ) { _ in }
            try require(sdk.exitCode == 0, "Cannot locate installed SDK")
            // A real BSP provider supplies an index from target preparation.
            // Prepare only this owned library's index, without building or
            // launching any app, so the fixture can validate workspace refs.
            let indexStore = cache.appendingPathComponent("bsp/index-store")
            try FileManager.default.createDirectory(at: indexStore, withIntermediateDirectories: true)
            try text.replacingOccurrences(of: "\"bad\"", with: "1").write(
                to: file, atomically: true, encoding: .utf8)
            let indexed = try await DeveloperToolTask().run(
                executable: tools.executable.deletingLastPathComponent().appendingPathComponent("swiftc"),
                arguments: [
                    "-typecheck", "-module-name", "OwnedLibrary", "-index-store-path", indexStore.path,
                    "-sdk", sdk.stdout.trimmingCharacters(in: .whitespacesAndNewlines), file.path,
                ], directory: root
            ) { _ in }
            try text.write(to: file, atomically: true, encoding: .utf8)
            try require(indexed.exitCode == 0, "Owned BSP index preparation failed")
            let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("fixtures/swift_bsp.py")
            let connection = JSONValue([
                "name": "HyCode Owned BSP", "version": "1", "bspVersion": "2.2.0", "languages": ["swift"],
                "argv": [
                    "/usr/bin/python3", fixture.path, root.path, file.path,
                    sdk.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                    cache.appendingPathComponent("bsp").path,
                    tools.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                        .path,
                ],
            ])
            try JSONEncoder().encode(connection).write(to: root.appendingPathComponent("buildServer.json"))
            try require(
                try NativeProjectModel.inspect(language: .swift, root: root) == .xcodeBuildServer,
                "BSP model not detected")
        }
        let server = NativeLanguageServer(language: language)
        let events = ProbeEvents()
        let listener = Task { for await event in server.events { await events.accept(event) } }
        do {
            let isolatedHome =
                raw == "java-maven"
                ? URL(fileURLWithPath: ".build/native-probe-maven-home", isDirectory: true)
                : cache.appendingPathComponent("home")
            try await server.initialize(
                root: root, tools: tools, cache: cache, trusted: true,
                triggerFiles: [file.absoluteString], isolatedHome: isolatedHome,
                offline: raw != "java-maven")
            try await server.open(uri: file.absoluteString, text: text, version: 0)
            try await server.diagnose(uri: file.absoluteString)
            for _ in 0..<300 {
                if await events.errors(file.absoluteString) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(
                await events.errors(file.absoluteString),
                "No initial type diagnostic: " + (await events.described(file.absoluteString)))
            let needle = "counter.value"
            let nameRange: NSRange
            if language == .swift {
                let range = (text as NSString).range(of: needle)
                nameRange = NSRange(location: range.location + "counter.".utf16.count, length: 5)
            } else {
                let range = (text as NSString).range(of: "this.value")
                nameRange = NSRange(location: range.location + 5, length: 5)
            }
            let index = TextLineIndex(text, unicodeLineSeparators: false)
            let position = LSPPosition.at(nameRange.location + 1, in: index)
            let hover = try await server.request("textDocument/hover", uri: file.absoluteString, position: position)
            try require(hover["contents"] != .null, "Missing hover")
            let definition = try await server.request(
                "textDocument/definition", uri: file.absoluteString, position: position)
            try require(!(try LSPLocation.locations(definition)).isEmpty, "Missing definition")
            let symbols = try await server.request(
                "textDocument/documentSymbol", uri: file.absoluteString, position: nil)
            try require(!symbols.array.isEmpty, "Missing symbols")
            let completion = try await server.request(
                "textDocument/completion", uri: file.absoluteString,
                position: LSPPosition.at(nameRange.location, in: index))
            let items = completion["items"] == .null ? completion.array : completion["items"].array
            try require(!items.isEmpty, "Missing completion")
            let format = try await server.request("textDocument/formatting", uri: file.absoluteString, position: nil)
            let edits = try format.decode([LSPTextEdit].self)
            _ = try LSPTextEdits.apply(edits, to: text)
            let literal = (text as NSString).range(of: "\"bad\"")
            try await server.change(
                uri: file.absoluteString,
                range: LSPRange(start: .at(literal.location, in: index), end: .at(NSMaxRange(literal), in: index)),
                text: "1", version: 1)
            try await server.diagnose(uri: file.absoluteString)
            for _ in 0..<200 {
                if !(await events.errors(file.absoluteString)) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(!(await events.errors(file.absoluteString)), "Type diagnostic did not clear after unsaved edit")
            let renamed = try await server.request(
                "textDocument/rename", uri: file.absoluteString, position: position,
                parameters: ["newName": .string("storedValue")])
            let rename = try LSPWorkspaceEdits.parse(renamed, root: root)
            try require(!rename.isEmpty, "Missing rename edit")
            let references = try await server.request(
                "textDocument/references", uri: file.absoluteString, position: position)
            try require(!(try LSPLocation.locations(references)).isEmpty, "Missing semantic references")
            if language == .java {
                let actions = try await server.request(
                    "textDocument/codeAction", uri: file.absoluteString, position: nil,
                    parameters: [
                        "range": LSPRange(start: position, end: position).json,
                        "context": JSONValue(["only": ["source.organizeImports"], "diagnostics": []]),
                    ])
                guard case .object(let fields) = actions.array.first else {
                    throw LanguageServiceFailure("Missing organize-imports action")
                }
                let action = try await server.request(
                    "codeAction/resolve", uri: file.absoluteString, position: nil, parameters: fields)
                let imports = try LSPWorkspaceEdits.parse(action["edit"], root: root)
                try require(!imports.isEmpty, "Missing organize-imports edit")
            }
            print(
                "PASS \(raw): real stdio diagnostics, unsaved edit, hover, definition, references, rename preview, completion, symbols and formatting; generated fixture only, no GUI"
            )
            if raw == "swift-bsp" {
                let log = try String(contentsOf: cache.appendingPathComponent("bsp/requests.log"), encoding: .utf8)
                try require(
                    log.contains("textDocument/sourceKitOptions"), "SourceKit did not consume BSP compiler options")
            }
            await server.close(uri: file.absoluteString)
            await server.stop()
            await listener.value
        } catch {
            await server.stop()
            listener.cancel()
            if let bsp = try? Data(contentsOf: cache.appendingPathComponent("bsp/requests.log")) {
                try? bsp.write(to: URL(fileURLWithPath: ".build/bsp-diagnostic.log"))
            }
            let log = cache.appendingPathComponent("workspace/.metadata/.log")
            if let data = try? Data(contentsOf: log) {
                try? data.write(to: URL(fileURLWithPath: ".build/jdt-diagnostic.log"))
            }
            throw error
        }
    }
}
