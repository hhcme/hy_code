import Darwin
import Foundation
import HyCodeWorkspace
import SwiftTerm

/// Explicit CLI smoke probe for sanitizer builds. Uses fixed non-login commands
/// and its own temporary directory; never creates a view/application host.
@main struct TerminalProbe {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw TerminalFailure("Usage: HyCodeTerminalProbe /path/to/HyCodeTerminalHost")
            }
            let helper = URL(fileURLWithPath: CommandLine.arguments[1])
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "HyCodeTerminalProbe-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            try verifyEmulator()
            try await verifyPTY(helper: helper, directory: directory, blocked: false)
            try await verifyPTY(helper: helper, directory: directory, blocked: true)
            print("PASS: 3 terminal model/emulator/PTY/blocked-input checks; no GUI, user configuration or clipboard")
        } catch {
            FileHandle.standardError.write(Data(("Terminal probe failed: " + error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw TerminalFailure(message) }
    }
    static func verifyEmulator() throws {
        var filter = TerminalOutputFilter()
        let rejected = filter.append(Data("\u{1b}Pq#999999999999999999999999\u{1b}\\".utf8))
        try check(rejected.isEmpty, "Graphic control sequence bypassed gate")
        let delegate = ProbeDelegate()
        let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: 80, rows: 5, scrollback: 8))
        let text = "中文🙂🇨🇳👨‍👩‍👧‍👦\r\n" + "a" + String(repeating: "\u{301}", count: 1000) + " done"
        for byte in text.utf8 { terminal.feed(byteArray: Array(filter.append(Data([byte])))) }
        try check(filter.unicodeReplacements > 0, "Unicode budget was not enforced")
        let rendered = terminal.getText(start: Position(col: 0, row: 0), end: Position(col: 79, row: 4))
        try check(rendered.contains("中文🙂🇨🇳👨‍👩‍👧‍👦") && rendered.contains("done"), "Headless terminal content mismatch")
    }
    static func verifyPTY(helper: URL, directory: URL, blocked: Bool) async throws {
        let process = TerminalProcess()
        let script =
            blocked
            ? "stty -echo\nprintf 'READY\\n'\nexec /bin/sleep 30"
            : "stty -echo\nprintf 'READY\\n'\nIFS= read -r value\nprintf 'INPUT:%s\\n' \"$value\"\nstty size"
        let config = try TerminalConfiguration(
            shell: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
            directory: directory, environment: ["PATH": "/usr/bin:/bin", "HOME": directory.path])
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            await process.stop()
        }
        do {
            try await process.start(configuration: config, helper: helper)
            var output = Data()
            var sent = false
            while let data = await process.nextOutput() {
                guard output.count + data.count <= 262_144 else {
                    throw TerminalFailure("Unexpected fixture output size")
                }
                output.append(data)
                if !sent, String(decoding: output, as: UTF8.self).contains("READY") {
                    sent = true
                    if blocked {
                        try await process.send(Data(repeating: 97, count: 200_000))
                        await process.stop()
                    } else {
                        process.resize(columns: 88, rows: 17)
                        try await process.send(Data("中文\n".utf8))
                    }
                }
            }
            let status = await process.waitForExit()
            deadline.cancel()
            try check(sent, "Fixture did not become ready")
            if !blocked {
                let text = String(decoding: output, as: UTF8.self)
                try check(
                    status == 0 && text.contains("INPUT:中文") && text.contains("17 88"), "PTY input or resize failed")
            }
        } catch {
            deadline.cancel()
            await process.stop()
            throw error
        }
    }
}

private final class ProbeDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
