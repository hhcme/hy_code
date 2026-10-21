import Foundation
import HyCodeWorkspace

/// Headless bounded probe: no AppKit, NSApplication, user interface or user files
/// unless the caller explicitly supplies --path. Default uses 72 temporary entries.
@main
struct DirectoryProbe {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let fixture = args.isEmpty
        let root: URL
        if fixture {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-probe-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } else {
            guard args.count == 2, args[0] == "--path" else {
                throw ProbeError.usage
            }
            root = URL(fileURLWithPath: args[1])
        }
        defer { if fixture { try? FileManager.default.removeItem(at: root) } }
        if fixture {
            for index in 0..<64 { try Data("sample".utf8).write(to: root.appendingPathComponent("file-\(index).txt")) }
            for index in 0..<8 {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("dir-\(index)"), withIntermediateDirectories: false)
            }
        }
        let reader = NativeDirectoryReader(rootPath: root.path)
        var samples: [Double] = []
        var textSamples: [Double] = []
        var entries = 0
        for _ in 0..<7 {
            let start = ContinuousClock.now
            let snapshot = try await reader.list(relativePath: "", includeHidden: true)
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            let textStart = ContinuousClock.now
            _ = try await ProjectTreeText.nameWidths(for: snapshot.entries)
            let textElapsed = textStart.duration(to: .now).components
            textSamples.append(Double(textElapsed.seconds) * 1000 + Double(textElapsed.attoseconds) / 1e15)
            entries = snapshot.entries.count
        }
        let sorted = samples.sorted()
        let payload: [String: Any] = [
            "mode": fixture ? "temporary-fixture" : "explicit-directory",
            "entries": entries, "samples_ms": samples, "median_ms": sorted[sorted.count / 2],
            "maximum_ms": sorted.last ?? 0, "includes": "queue + Rust enumerate/metadata/sort + JSON + Swift decode",
            "text_preparation_samples_ms": textSamples,
            "text_preparation_includes": "background actor + CoreText system font and name widths, no AppKit",
            "does_not_measure": "tree UI, storage cold start, scrolling or screen presentation",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
    private enum ProbeError: Error { case usage }
}
