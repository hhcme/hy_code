import Foundation

/// One private bootstrap directory per explicitly started zsh session. The run
/// task owns it through process exit; all creation/removal happens off MainActor.
public struct TerminalShellIntegration: Sendable {
    public static let oscCode = 7777
    public static let acceptSequence = "\u{1b}[2000~"
    public let directory: URL
    public let token: String

    public static func prepare(shell: URL) throws -> Self? {
        guard shell.lastPathComponent == "zsh" else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hycode-terminal-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let scripts = [
                ".zshenv": environmentScript,
                ".zprofile": relay(".zprofile", finish: false),
                ".zshrc": relay(".zshrc", finish: true),
                ".zlogin": relay(".zlogin", finish: false, last: true),
                "integration.zsh": integrationScript,
            ]
            for (name, script) in scripts {
                try Data(script.utf8).write(to: directory.appendingPathComponent(name))
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(name).path)
            }
            return Self(directory: directory, token: UUID().uuidString)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    public func environment(_ original: [String: String]) -> [String: String] {
        var result = original
        result["HYCODE_TERMINAL_ZDOTDIR"] = original["ZDOTDIR"] ?? original["HOME"] ?? ""
        result["HYCODE_TERMINAL_ZDOTDIR_SET"] = original["ZDOTDIR"] == nil ? "0" : "1"
        result["HYCODE_TERMINAL_TOKEN"] = token
        result["ZDOTDIR"] = directory.path
        return result
    }
    public func writeAcceptance(
        state: TerminalPromptState, candidate: TerminalCompletionCandidate, identity: String = UUID().uuidString
    ) throws {
        guard state.token == token, state.phase == "edit",
            state.cursor == state.line.unicodeScalars.count,
            state.line.utf8.count <= 4096, candidate.suffix.utf8.count <= 4096,
            !(state.line + candidate.suffix).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
        else { throw TerminalFailure("命令行已变化，请重新选择候选") }
        guard UUID(uuidString: identity) != nil else { throw TerminalFailure("无效的候选请求") }
        let request = identity + "\n" + state.line + "\n" + String(state.cursor) + "\n" + candidate.suffix + "\n"
        let target = directory.appendingPathComponent("completion")
        try Data(request.utf8).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    public func remove() { try? FileManager.default.removeItem(at: directory) }

    private static let environmentScript = #"""
        typeset -g _HYCODE_DIRECTORY=$ZDOTDIR
        typeset -g _HYCODE_USER_ZDOTDIR=$HYCODE_TERMINAL_ZDOTDIR
        typeset -g _HYCODE_USER_ZDOTDIR_SET=$HYCODE_TERMINAL_ZDOTDIR_SET
        typeset -g _HYCODE_USER_ZDOTDIR_EXPORTED=$HYCODE_TERMINAL_ZDOTDIR_SET
        typeset -g _HYCODE_TOKEN=$HYCODE_TERMINAL_TOKEN
        unset HYCODE_TERMINAL_ZDOTDIR HYCODE_TERMINAL_ZDOTDIR_SET HYCODE_TERMINAL_TOKEN
        _hycode_restore_zdotdir() {
          unset ZDOTDIR
          if [[ $_HYCODE_USER_ZDOTDIR_SET == 1 ]]; then
            typeset -g ZDOTDIR=$_HYCODE_USER_ZDOTDIR
            if [[ $_HYCODE_USER_ZDOTDIR_EXPORTED == 1 ]]; then export ZDOTDIR; fi
          fi
        }
        _hycode_capture_zdotdir() {
          _HYCODE_USER_ZDOTDIR=${ZDOTDIR-$HOME}
          _HYCODE_USER_ZDOTDIR_SET=${+ZDOTDIR}
          _HYCODE_USER_ZDOTDIR_EXPORTED=0
          if [[ ${(t)ZDOTDIR} == *export* ]]; then _HYCODE_USER_ZDOTDIR_EXPORTED=1; fi
          if [[ -o rcs ]]; then export ZDOTDIR=$_HYCODE_DIRECTORY; fi
        }
        _hycode_restore_zdotdir
        [[ -r ${ZDOTDIR-$HOME}/.zshenv ]] && source "${ZDOTDIR-$HOME}/.zshenv"
        _hycode_capture_zdotdir
        """#

    private static func relay(_ name: String, finish: Bool, last: Bool = false) -> String {
        var script = """
            _hycode_restore_zdotdir
            [[ -r ${ZDOTDIR-$HOME}/\(name) ]] && source "${ZDOTDIR-$HOME}/\(name)"

            """
        if finish { script += "source \"$_HYCODE_DIRECTORY/integration.zsh\"\n" }
        if !last {
            script +=
                finish
                ? "if [[ -o login ]]; then _hycode_capture_zdotdir; fi\n"
                : "_hycode_capture_zdotdir\n"
        }
        return script
    }

    private static let integrationScript = #"""
        [[ -o interactive ]] || return
        autoload -Uz add-zle-hook-widget
        _hycode_json() {
          REPLY=$1
          REPLY=${REPLY//\\/\\\\}
          REPLY=${REPLY//\"/\\\"}
        }
        _hycode_report() {
          emulate -L zsh
          local phase=edit line=$BUFFER location=$PWD cursor=$CURSOR REPLY payload
          if [[ $1 == finish || $KEYMAP == vicmd ||
                $BUFFER == *[[:cntrl:]]* || $PWD == *[[:cntrl:]]* ||
                ${#BUFFER} -gt 512 || ${#PWD} -gt 512 ]]; then
            phase=finish line='' location=/ cursor=0
          fi
          _hycode_json "$line"; line=$REPLY
          _hycode_json "$location"; location=$REPLY
          printf -v payload '{"token":"%s","phase":"%s","line":"%s","cursor":%d,"directory":"%s","acceptance":"%s"}' \
            "$_HYCODE_TOKEN" "$phase" "$line" "$cursor" "$location" "$_HYCODE_ACCEPTED"
          if [[ $payload != $_HYCODE_LAST_REPORT ]]; then
            printf '\033]7777;%s\007' "$payload"
            typeset -g _HYCODE_LAST_REPORT=$payload
          fi
          return 0
        }
        _hycode_accept() {
          emulate -L zsh
          local identity expected position suffix request=$_HYCODE_DIRECTORY/completion
          [[ -r $request ]] || return 0
          {
            IFS= read -r identity
            IFS= read -r expected
            IFS= read -r position
            IFS= read -r suffix
          } < "$request"
          : > "$request"
          typeset -g _HYCODE_ACCEPTED=$identity
          if [[ $BUFFER == "$expected" && $CURSOR == "$position" &&
                $CURSOR == ${#BUFFER} && $suffix != *[[:cntrl:]]* ]]; then
            LBUFFER+=$suffix
          fi
          return 0
        }
        _hycode_finish() { _hycode_report finish }
        zle -N _hycode_accept
        bindkey -M emacs $'\e[2000~' _hycode_accept
        bindkey -M viins $'\e[2000~' _hycode_accept
        add-zle-hook-widget line-init _hycode_report
        add-zle-hook-widget line-pre-redraw _hycode_report
        add-zle-hook-widget keymap-select _hycode_report
        add-zle-hook-widget line-finish _hycode_finish
        # Keep custom prompt themes; color only the unmodified system defaults.
        if [[ $PROMPT == '%m%# ' || $PROMPT == '%n@%m %1~ %# ' ]]; then
          PROMPT='%F{6}%n@%m%f %F{4}%1~%f %F{2}%#%f '
        fi
        """#
}
