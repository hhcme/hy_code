import CryptoKit
import Darwin
import Foundation
import HyCodeWorkspace

/// Opt-in single-worker GB regression, generated valid UTF-8 only, no user
/// files or GUI. Not part of ordinary tests: roughly 2.1GB temporary disk and
/// several GB sequential I/O. Invoke under taskpolicy -b / nice for low priority.
@main struct LargeFileProbe {
    static func main() async throws {
        guard CommandLine.arguments.dropFirst().elementsEqual(["--gib1"]) else { throw ProbeError.usage }
        try await Task.detached(priority: .utility) { try await run() }.value
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hycode-gib-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let free =
            (try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?
            .uint64Value ?? 0
        guard free > 4 * 1024 * 1024 * 1024 else { throw ProbeError.diskBudget }
        let file = root.appendingPathComponent("generated.log")
        guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw ProbeError.fixture }
        let writer = try FileHandle(forWritingTo: file)
        let chunk = Data(String(repeating: String(repeating: "x", count: 126) + "\r\n", count: 2048).utf8)
        let chunks = 4112  // 1GiB +4MiB; physically written valid text, no sparse NULs.
        var expected = SHA256()
        let marker = Data("\nGB-END-😀-中文\n".utf8)
        let start = ContinuousClock.now
        for index in 0..<chunks {
            try writer.write(contentsOf: chunk)
            if index == 0 {
                var modified = chunk
                modified.replaceSubrange(0..<4, with: Data("EDIT".utf8))
                expected.update(data: modified)
            } else {
                expected.update(data: chunk)
            }
            // Generation <=~64MiB/s, one worker, bounded 256KiB buffers.
            if index.isMultiple(of: 32) { try await Task.sleep(for: .milliseconds(125)) }
        }
        try writer.write(contentsOf: marker)
        try writer.synchronize()
        try writer.close()
        expected.update(data: marker)
        let bytes = UInt64(chunk.count * chunks + marker.count)
        let document = NativeTextDocument(root: root, path: "generated.log")
        let openedAt = ContinuousClock.now
        let content = try await document.open()
        let openMS = milliseconds(openedAt)
        guard let page = content.largePage, page.totalBytes == bytes, content.text.utf8.count <= 65_536 else {
            throw ProbeError.page
        }
        try await document.replace(expected: 0, range: NSRange(location: 0, length: 4), text: "EDIT")
        let token = DocumentSaveCancellation()
        let timeout = Task {
            try await Task.sleep(for: .seconds(60))
            token.cancel()
        }
        defer { timeout.cancel() }
        let findAt = ContinuousClock.now
        let found = try await document.find(revision: 1, text: "GB-END-😀", from: 0, cancellation: token)
        let findMS = milliseconds(findAt)
        guard found == UInt64(chunk.count * chunks + 1) else { throw ProbeError.search }
        let last = try await document.page(revision: 1, offset: page.last)
        guard last.text.hasSuffix(String(decoding: marker, as: UTF8.self)) else { throw ProbeError.page }
        let saveAt = ContinuousClock.now
        try await document.save(revision: 1, cancellation: token)
        let saveMS = milliseconds(saveAt)
        let reader = try FileHandle(forReadingFrom: file)
        var actual = SHA256()
        var count: UInt64 = 0
        while let data = try reader.read(upToCount: 256 * 1024), !data.isEmpty {
            actual.update(data: data)
            count += UInt64(data.count)
            if count.isMultiple(of: 8 * 1024 * 1024) { try await Task.sleep(for: .milliseconds(20)) }
        }
        try reader.close()
        let expectedDigest = expected.finalize()
        let actualDigest = actual.finalize()
        guard actualDigest == expectedDigest, count == bytes else { throw ProbeError.truncated }
        var usage = rusage()
        _ = getrusage(RUSAGE_SELF, &usage)
        let report: [String: Any] = [
            "result": "pass", "valid_generated_utf8_bytes": bytes, "page_utf8_bytes": content.text.utf8.count,
            "whole_file_save_and_sha256": "pass", "sha256": actualDigest.map { String(format: "%02x", $0) }.joined(),
            "open_ms": openMS, "full_literal_search_ms": findMS, "full_atomic_save_ms": saveMS,
            "total_ms_including_throttled_fixture": milliseconds(start), "peak_rss_bytes": usage.ru_maxrss,
            "gui_created": false, "user_files_read": false, "fixture_removed_on_exit": true,
            "does_not_measure":
                "TextKit windows, caret, scrolling, IME, rendering, cold storage or larger-size acceptance",
        ]
        print(
            String(
                decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
                as: UTF8.self))
    }
    static func milliseconds(_ start: ContinuousClock.Instant) -> Double {
        let c = start.duration(to: .now).components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
    enum ProbeError: Error { case usage, diskBudget, fixture, page, search, truncated }
}
