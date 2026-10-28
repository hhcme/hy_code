import AppKit
import HyCodeWorkspace
import Observation
import SwiftTerm

/// This owner retains the terminal buffer/view while its tab or tool is hidden.
/// UI callbacks and emulator access stay on MainActor; the PTY owns all I/O.
@MainActor @Observable
final class TerminalPaneSession: NSObject, @preconcurrency TerminalViewDelegate {
    let id: UUID
    private(set) var directory: URL
    private(set) var reportedDirectory = false
    private(set) var status = "正在启动…"
    private(set) var live = true
    private(set) var shellTitle = ""
    var issue: String?
    var searching = false
    var query = ""
    var searchFound = true
    private(set) var completions: [TerminalCompletionCandidate] = []
    var completionChoice = 0
    private(set) var completionOrigin = CGPoint.zero
    @ObservationIgnored let view: HyCodeTerminalView
    @ObservationIgnored private let process = TerminalProcess()
    @ObservationIgnored private let access: WorkspaceAccess
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var inputTail: Task<Void, Never>?
    @ObservationIgnored private var inputBytes = 0
    @ObservationIgnored private var integration: TerminalShellIntegration?
    @ObservationIgnored private var prompt: TerminalPromptState?
    @ObservationIgnored private var dismissedPrompt: TerminalPromptState?
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var completionRevision = 0
    @ObservationIgnored private var pendingAcceptance: String?
    @ObservationIgnored private var promptReady = false
    @ObservationIgnored var onFocus: () -> Void = {}
    @ObservationIgnored var onOpenLink: (String) -> Void = { _ in }

    init(id: UUID, directory: URL, access: WorkspaceAccess, fontSize: Double) {
        self.id = id
        self.directory = directory
        self.access = access
        view = HyCodeTerminalView(
            frame: .zero, font: .monospacedSystemFont(ofSize: min(24, max(10, fontSize)), weight: .regular),
            options: TerminalOptions(
                cols: 100, rows: 28, cursorStyle: .steadyBar, scrollback: 2000,
                enableSixelReported: false, kittyImageCacheLimitBytes: 8 * 1024 * 1024))
        super.init()
        view.terminalDelegate = self
        view.bellStyle = .none
        view.optionAsMetaKey = false
        view.caretViewTracksFocus = true
        view.scrollerStyle = .overlay
        view.linkReporting = .implicit
        view.onFocus = { [weak self] in self?.onFocus() }
        view.onFind = { [weak self] in self?.searching = true }
        view.onPaste = { [weak self] in self?.paste($0) }
        view.onWillInput = { [weak self] in
            self?.promptReady = false
            self?.dismissCompletion()
        }
        view.onDismissCompletion = { [weak self] in
            guard let self, !completions.isEmpty || completionTask != nil else { return }
            dismissCompletion()
        }
        view.onCompletionKey = { [weak self] in self?.completionKey($0) ?? false }
        view.onManualCompletion = { [weak self] in self?.requestCompletion(manual: true) ?? false }
        view.getTerminal().registerOscHandler(code: TerminalShellIntegration.oscCode) { [weak self] bytes in
            self?.receivePrompt(Data(bytes))
        }
        view.applyTheme()
    }
    func start(shell: String, login: Bool, completion: Bool) {
        guard run == nil else { return }
        run = Task { [weak self, process] in
            guard let self else { return }
            do {
                let helper = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent(
                    "HyCodeTerminalHost")
                let directory = directory
                let prepared = try await Task.detached(priority: .utility) {
                    var environment = ProcessInfo.processInfo.environment
                    let path = shell.isEmpty ? TerminalConfiguration.userShell(environment: environment) : shell
                    guard path.hasPrefix("/"), !path.contains("\0") else {
                        throw TerminalFailure("请填写 Shell 可执行文件的绝对路径")
                    }
                    let shellURL = URL(fileURLWithPath: path)
                    let integration = completion ? try TerminalShellIntegration.prepare(shell: shellURL) : nil
                    if let integration { environment = integration.environment(environment) }
                    do {
                        let config = try TerminalConfiguration(
                            shell: URL(fileURLWithPath: path), arguments: login ? ["-l"] : [],
                            directory: directory, environment: environment)
                        return (config, integration)
                    } catch {
                        integration?.remove()
                        throw error
                    }
                }.value
                integration = prepared.1
                try await process.start(configuration: prepared.0, helper: helper)
                status = "运行中"
                let terminal = view.getTerminal()
                process.resize(columns: terminal.cols, rows: terminal.rows)
                var chunks = 0
                var reportedLimit = false
                while let data = await process.nextOutput() {
                    view.feed(byteArray: Array(data)[...])
                    view.onViewportChange()
                    updateCompletionOrigin()
                    chunks += 1
                    if !reportedLimit, chunks % 16 == 1, await process.outputWasLimited() {
                        reportedLimit = true
                        issue = "部分终端控制序列或过长 Unicode 组合已达到显示预算。"
                    }
                    // At most 32 KiB per UI delivery; yield under a fast output producer.
                    try? await Task.sleep(for: .milliseconds(8))
                }
                if !reportedLimit, await process.outputWasLimited() {
                    issue = "部分终端控制序列或过长 Unicode 组合已达到显示预算。"
                }
                let code = await process.waitForExit()
                live = false
                view.enabledForInput = false
                status = "已退出 · \(code)"
            } catch {
                live = false
                view.enabledForInput = false
                status = "启动失败"
                issue = error.localizedDescription
            }
            dismissCompletion()
            if let integration {
                await Task.detached(priority: .utility) { integration.remove() }.value
                self.integration = nil
            }
        }
    }
    func stop() async {
        dismissCompletion()
        await process.stop()
        await run?.value
        await inputTail?.value
        run = nil
        inputTail = nil
        view.terminalDelegate = nil
        view.enabledForInput = false
        live = false
    }
    func requestFocus() {
        onFocus()
        view.focusWhenVisible = true
        view.focusIfPossible()
    }
    func setFontSize(_ size: Double) {
        view.font = .monospacedSystemFont(ofSize: min(24, max(10, size)), weight: .regular)
    }
    func search(next: Bool = true) {
        guard query.utf8.count <= 1024 else {
            searchFound = false
            return
        }
        searchFound = query.isEmpty || (next ? view.findNext(query) : view.findPrevious(query))
    }
    private func enqueue(_ data: Data, onlyWhenShellForeground: Bool = false) {
        guard live else {
            issue = "终端已退出，请新建会话"
            return
        }
        guard inputBytes + data.count <= 262_144 else {
            issue = "待发送输入超过 256 KiB，请稍后重试"
            return
        }
        inputBytes += data.count
        let previous = inputTail
        inputTail = Task { [weak self, process] in
            await previous?.value
            do {
                try await process.send(data, onlyWhenShellForeground: onlyWhenShellForeground)
            } catch { self?.issue = error.localizedDescription }
            self?.inputBytes -= data.count
        }
    }
    func dismissCompletion() {
        dismissedPrompt = prompt
        completionRevision += 1
        completionTask?.cancel()
        completionTask = nil
        if !completions.isEmpty { completions = [] }
    }
    private func receivePrompt(_ bytes: Data) {
        guard let integration,
            let next = TerminalPromptState.decode(bytes, token: integration.token)
        else { return }
        if next.acceptance == pendingAcceptance || next.phase == "finish" { pendingAcceptance = nil }
        guard next != prompt else { return }
        prompt = next
        promptReady = next.phase == "edit"
        dismissCompletion()
        dismissedPrompt = nil
        guard next.phase == "edit" else { return }
        directory = URL(fileURLWithPath: next.directory)
        reportedDirectory = true
        requestCompletion()
    }
    @discardableResult private func requestCompletion(manual: Bool = false) -> Bool {
        guard live, promptReady, pendingAcceptance == nil, view.terminalVisible, !searching, !view.hasMarkedText(),
            view.window?.firstResponder === view,
            !view.getTerminal().isCurrentBufferAlternate,
            !view.canScroll || view.scrollPosition >= 0.999,
            let prompt, prompt.phase == "edit", manual || prompt != dismissedPrompt,
            let request = TerminalCompletionRequest.parse(line: prompt.line, cursor: prompt.cursor),
            manual || !request.prefix.isEmpty || !request.words.isEmpty
        else { return false }
        completionTask?.cancel()
        completionRevision += 1
        let revision = completionRevision
        let root = access.url
        let directory = URL(fileURLWithPath: prompt.directory)
        completionTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(manual ? 0 : 120)) } catch { return }
            let worker = Task.detached(priority: .utility) {
                TerminalCompletionProvider.suggestions(for: request, directory: directory, root: root)
            }
            let values = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, revision == completionRevision,
                self.prompt == prompt, live, view.terminalVisible, !view.hasMarkedText(),
                view.window?.firstResponder === view,
                !view.getTerminal().isCurrentBufferAlternate
            else { return }
            completions = values
            completionTask = nil
            completionChoice = 0
            updateCompletionOrigin()
        }
        return true
    }
    private func completionKey(_ key: UInt16) -> Bool {
        guard !completions.isEmpty else { return false }
        switch key {
        case 48: acceptCompletion()
        case 125: completionChoice = (completionChoice + 1) % completions.count
        case 126: completionChoice = (completionChoice + completions.count - 1) % completions.count
        case 53: dismissCompletion()
        default: return false
        }
        return true
    }
    func acceptCompletion() {
        guard live, pendingAcceptance == nil, let integration, let prompt, prompt.phase == "edit",
            completions.indices.contains(completionChoice)
        else { return }
        let candidate = completions[completionChoice]
        let identity = UUID().uuidString
        let data = Data(TerminalShellIntegration.acceptSequence.utf8)
        guard inputBytes + data.count <= 262_144 else { return }
        pendingAcceptance = identity
        dismissCompletion()
        // Reserve the input order immediately. A following Enter must run after
        // the accepted insertion, even while its private file is being written.
        let previous = inputTail
        inputBytes += data.count
        inputTail = Task { [weak self, process] in
            await previous?.value
            do {
                try await Task.detached(priority: .utility) {
                    try integration.writeAcceptance(state: prompt, candidate: candidate, identity: identity)
                }.value
                try await process.send(data, onlyWhenShellForeground: true)
            } catch {
                self?.pendingAcceptance = nil
                self?.issue = error.localizedDescription
            }
            self?.inputBytes -= data.count
        }
        requestFocus()
    }
    private func updateCompletionOrigin() {
        guard !completions.isEmpty, let window = view.window else { return }
        let screen = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let local = view.convert(window.convertFromScreen(screen), from: nil)
        completionOrigin = CGPoint(x: max(0, local.minX), y: max(0, view.bounds.height - local.minY + 2))
    }
    private func paste(_ text: String) {
        guard text.utf8.count <= 262_000 else {
            issue = "一次最多粘贴 256 KiB 文本"
            return
        }
        // Prevent pasted control sequences from closing a bracketed-paste envelope.
        let safe = String(text.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\r" || $0 == "\t" })
        func insert() {
            let terminal = view.getTerminal()
            if terminal.bracketedPasteMode { view.send(txt: "\u{1b}[200~") }
            view.send(txt: safe)
            if terminal.bracketedPasteMode { view.send(txt: "\u{1b}[201~") }
        }
        if TerminalConfiguration.pasteNeedsConfirmation(safe) {
            guard let window = view.window else { return }
            WorkbenchPrompt.present(
                in: window, title: "粘贴多行到终端？",
                detail: "文本包含换行，Shell 可能立即执行其中的命令。\n\n" + String(safe.prefix(240)), accept: "粘贴"
            ) {
                [weak self] response, _ in
                guard response == .accept, self?.live == true else { return }
                insert()
            }
        } else {
            insert()
        }
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        process.resize(columns: newCols, rows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {
        shellTitle = String(title.filter { !$0.isNewline }.prefix(120))
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, directory.utf8.count < 8192, let url = URL(string: directory), url.isFileURL,
            url.host == nil || url.host == "" || url.host == "localhost"
        else { return }
        self.directory = url.standardizedFileURL
        reportedDirectory = true
    }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { enqueue(Data(data)) }
    func scrolled(source: TerminalView, position: Double) {
        view.onViewportChange()
        if view.canScroll, position < 0.999 { dismissCompletion() }
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { onOpenLink(link) }
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func clipboardRead(source: TerminalView) -> Data? { nil }
}
