import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable
final class TerminalWorkspaceController {
    private(set) var tabs: [TerminalTab] = []
    private(set) var activeTabID: UUID?
    private(set) var sessions: [UUID: TerminalPaneSession] = [:]
    private(set) var closing = false
    var error: String?
    var showingSettings = false
    var shellPath = UserDefaults.standard.string(forKey: "terminal.shell") ?? "" {
        didSet { UserDefaults.standard.set(shellPath, forKey: "terminal.shell") }
    }
    var loginShell = UserDefaults.standard.object(forKey: "terminal.login") as? Bool ?? true {
        didSet { UserDefaults.standard.set(loginShell, forKey: "terminal.login") }
    }
    var commandCompletion = UserDefaults.standard.object(forKey: "terminal.completion") as? Bool ?? true {
        didSet { UserDefaults.standard.set(commandCompletion, forKey: "terminal.completion") }
    }
    var fontSize = UserDefaults.standard.object(forKey: "terminal.fontSize") as? Double ?? 13 {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "terminal.fontSize")
            for session in sessions.values { session.setFontSize(fontSize) }
        }
    }
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored var executionAllowed: () -> Bool = { false }
    @ObservationIgnored var onOpenFile: (URL, Int, Int) -> Void = { _, _, _ in }
    var activeTab: TerminalTab? { tabs.first { $0.id == activeTabID } }
    var activeSession: TerminalPaneSession? { activeTab.flatMap { sessions[$0.activePane] } }
    var hasLiveSessions: Bool { sessions.values.contains { $0.live } }
    var canCreate: Bool { access != nil && !closing && sessions.count < 8 && executionAllowed() }

    func configure(access: WorkspaceAccess?) {
        self.access = access
        error = nil
    }
    func ensureSession() {
        if tabs.isEmpty { newTab() } else { focus() }
    }
    func newTab(directory: URL? = nil) {
        guard canCreate, let access else {
            error = access == nil ? "请先打开项目" : "其他修改任务正在执行，或已达到 8 个终端会话上限"
            return
        }
        let tab = TerminalTab(title: "终端 \(tabs.count + 1)")
        tabs.append(tab)
        activeTabID = tab.id
        create(tab.activePane, directory: directory ?? access.url, access: access)
    }
    func split(_ axis: TerminalSplitAxis) {
        guard canCreate, let access, let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let directory = activeSession?.directory ?? access.url
        guard let pane = tabs[index].split(axis) else {
            error = "每个标签最多 4 个分屏"
            return
        }
        create(pane, directory: directory, access: access)
    }
    private func create(_ id: UUID, directory: URL, access: WorkspaceAccess) {
        let session = TerminalPaneSession(id: id, directory: directory, access: access, fontSize: fontSize)
        session.onFocus = { [weak self] in self?.selectPane(id) }
        session.onOpenLink = { [weak self, weak session] link in
            guard let self, let session else { return }
            self.openLink(link, from: session)
        }
        sessions[id] = session
        session.start(shell: shellPath, login: loginShell, completion: commandCompletion)
        session.requestFocus()
        error = nil
    }
    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        focus()
    }
    private func selectPane(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.layout.panes.contains(id) }) else { return }
        activeTabID = tabs[index].id
        tabs[index].select(id)
    }
    func focus() { activeSession?.requestFocus() }
    func tabDetail(_ tab: TerminalTab) -> String {
        tab.layout.panes.compactMap { sessions[$0] }.map { $0.directory.path + " · " + $0.status }.joined(
            separator: "\n")
    }
    func rename(_ tab: TerminalTab) {
        guard let window = NSApp.keyWindow else { return }
        WorkbenchPrompt.present(
            in: window, title: "重命名终端", detail: "为此终端标签设置名称。", initialValue: tab.title, accept: "保存"
        ) {
            [weak self] response, title in
            guard response == .accept, let self, let index = self.tabs.firstIndex(where: { $0.id == tab.id }) else {
                return
            }
            self.tabs[index].title = String(title.prefix(80))
        }
    }
    func closeTab(_ tab: TerminalTab) {
        if let current = tabs.first(where: { $0.id == tab.id }) { close(panes: current.layout.panes) }
    }
    func closePane(_ id: UUID) { close(panes: [id]) }
    private func close(panes: [UUID]) {
        guard !closing else { return }
        closing = true
        Task {
            defer { closing = false }
            guard await confirmClosing(panes: panes) else { return }
            for id in panes {
                await sessions[id]?.stop()
                sessions[id] = nil
                if let index = tabs.firstIndex(where: { $0.layout.panes.contains(id) }), !tabs[index].remove(id) {
                    tabs.remove(at: index)
                }
            }
            if !tabs.contains(where: { $0.id == activeTabID }) { activeTabID = tabs.last?.id }
            focus()
        }
    }
    func confirmClosingAll() async -> Bool { await confirmClosing(panes: Array(sessions.keys)) }
    private func confirmClosing(panes: [UUID]) async -> Bool {
        let count = panes.filter { sessions[$0]?.live == true }.count
        guard count > 0 else { return true }
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else { return false }
        return await withCheckedContinuation { continuation in
            WorkbenchPrompt.present(
                in: window, title: "结束终端会话？", detail: "将结束 \(count) 个 Shell 会话及会话中的任务。收起终端面板可让会话继续运行。", accept: "结束会话"
            ) { response, _ in
                continuation.resume(returning: response == .accept)
            }
        }
    }
    func stopAll() async {
        closing = true
        // Sequential cleanup keeps the number of shutdown operations bounded.
        for session in sessions.values { await session.stop() }
        sessions.removeAll()
        tabs.removeAll()
        activeTabID = nil
        closing = false
    }
    private func openLink(_ link: String, from session: TerminalPaneSession) {
        guard let access, link.utf8.count < 8192 else { return }
        let directory = session.directory
        Task {
            do {
                let reference = try await Task.detached(priority: .utility) {
                    try TerminalFileReference.resolve(link, directory: directory, root: access.url)
                }.value
                guard self.access === access, self.sessions[session.id] === session else { return }
                self.onOpenFile(reference.url, reference.line, reference.column)
            } catch {
                guard self.access === access, self.sessions[session.id] === session else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
