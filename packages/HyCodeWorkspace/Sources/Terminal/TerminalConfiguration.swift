import CHyCodeTerminal
import Foundation

public struct TerminalFailure: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// User terminal configuration is separate from every managed tool/Agent environment.
/// Arguments are passed as argv, never interpreted as a command string by HyCode.
public struct TerminalConfiguration: Sendable {
    public let shell: URL
    public let arguments: [String]
    public let directory: URL
    public let environment: [String: String]

    public init(shell: URL, arguments: [String] = ["-l"], directory: URL, environment: [String: String]) throws {
        guard shell.isFileURL, shell.path.hasPrefix("/"), directory.isFileURL,
            !shell.path.contains("\0"), !directory.path.contains("\0"), arguments.count <= 64,
            arguments.allSatisfy({ !$0.contains("\0") }),
            environment.allSatisfy({
                !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.contains("\0") && !$0.value.contains("\0")
            }),
            arguments.reduce(0, { $0 + $1.utf8.count }) < 32_768,
            environment.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) < 262_144
        else { throw TerminalFailure("终端路径、参数或环境无效或超出预算") }
        self.shell = shell
        self.arguments = arguments
        self.directory = directory
        var values = environment.filter { key, _ in
            !key.hasPrefix("HYCODE_CODEX") && !key.hasPrefix("DYLD_") && !key.hasPrefix("__XPC_")
        }
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["TERM_PROGRAM"] = "HyCode"
        values["SHELL"] = shell.path
        values["PWD"] = directory.path
        if values["LANG"] == nil { values["LANG"] = "en_US.UTF-8" }
        self.environment = values
    }

    /// Shell quoting is used only for explicit path insertion at the prompt.
    public static func quotePath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    public static func pasteNeedsConfirmation(_ text: String) -> Bool {
        // CRLF is one Swift Character; searching for a standalone LF misses it.
        text.unicodeScalars.contains { $0.value == 10 || $0.value == 13 }
    }
    /// Call off the UI thread: the account directory lookup may perform I/O.
    public static func userShell(environment: [String: String]) -> String {
        if let value = environment["SHELL"], value.hasPrefix("/"), !value.contains("\0") { return value }
        var path = [CChar](repeating: 0, count: 4096)
        if hycode_terminal_user_shell(&path, path.count) == 0 {
            return String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return "/bin/zsh"
    }
}
