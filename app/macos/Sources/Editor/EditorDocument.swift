import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable final class EditorDocument: Identifiable {
    let id = UUID()
    let path: String
    let sourceURL: URL
    let readOnly: Bool
    var toolManaged = false {
        didSet {
            editor?.textView.isEditable = !toolManaged && !readOnly && !closed && !closing && !synchronizationFailed
            if toolManaged {
                pauseAutoSave()
                for (token, automatic) in saves.values where automatic { token.cancel() }
            } else {
                scheduleAutoSave()
            }
        }
    }
    private(set) var semantic: EditorLanguageFeatures?
    var pendingReveal: LSPRange?
    private(set) var loading = true
    private(set) var loadError: String?
    private(set) var error: String?
    private(set) var inputError: String?
    private(set) var edits = DocumentEditState()
    private(set) var savingCount = 0
    private(set) var encoding = "utf8"
    private(set) var lineEnding = "LF"
    private(set) var composing = false
    private(set) var closing = false
    var syntaxLanguage = ""
    var syntaxNotice: String?
    @ObservationIgnored private(set) var editor: NativeTextEditor?
    @ObservationIgnored private let engine: NativeTextDocument
    @ObservationIgnored private let access: WorkspaceAccess
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private(set) var closed = false
    @ObservationIgnored private var synchronizationFailed = false
    @ObservationIgnored private var byteCount = 0
    @ObservationIgnored private var hasBOM = false
    @ObservationIgnored private var autoSaveSuspended = false
    @ObservationIgnored private var saves: [UUID: (DocumentSaveCancellation, Bool)] = [:]
    @ObservationIgnored var onEdit: (() -> Void)?
    var autoSave: Bool {
        didSet {
            if autoSave {
                scheduleAutoSave()
            } else {
                pauseAutoSave()
                for (token, automatic) in saves.values where automatic { token.cancel() }
            }
        }
    }
    var isDirty: Bool { edits.isDirty }
    var workspaceRoot: URL { access.url }
    var workspaceAccess: WorkspaceAccess { access }
    var status: String {
        if loading { return "正在打开…" }
        if loadError != nil { return "无法编辑" }
        if readOnly { return "依赖源代码 · 只读" }
        if toolManaged { return "包操作中 · 清单只读" }
        if savingCount > 0 { return "正在保存…" }
        if error != nil { return "保存失败 · 更改已保留" }
        if isDirty { return autoSave ? "等待保存" : "未保存" }
        return "已保存"
    }

    init(
        path: String, access: WorkspaceAccess, autoSave: Bool, language: DartWorkspaceController? = nil,
        web: WebWorkspaceController? = nil
    ) {
        self.path = path
        readOnly = path.hasPrefix("/")
        let sourceAccess =
            readOnly ? WorkspaceAccess(url: URL(fileURLWithPath: path).deletingLastPathComponent()) : access
        let sourcePath = readOnly ? URL(fileURLWithPath: path).lastPathComponent : path
        sourceURL = sourceAccess.url.appendingPathComponent(sourcePath)
        self.access = sourceAccess
        self.autoSave = autoSave
        engine = NativeTextDocument(root: sourceAccess.url, path: sourcePath)
        let engine = engine
        tail = Task { [weak self, access = sourceAccess] in
            defer { withExtendedLifetime(access) {} }
            do {
                let content = try await engine.open()
                guard let self, !self.closed else { return }
                self.encoding = content.encoding
                self.lineEnding = content.lineEnding
                self.byteCount = content.byteCount
                self.hasBOM = content.hasBOM
                self.editor = NativeTextEditor(document: self, content: content)
                let owner: (any EditorLanguageController)? =
                    path.lowercased().hasSuffix(".dart")
                    ? language
                    : WebLanguage.detect(path) != nil ? web : nil
                if let owner, content.text.utf8.count <= 1_048_576 {
                    self.semantic = EditorLanguageFeatures(document: self, controller: owner, content: content)
                    self.editor?.connect(self.semantic)
                }
                self.loading = false
                if let range = self.pendingReveal { self.reveal(range) }
            } catch {
                guard let self, !self.closed else { return }
                self.loadError = error.localizedDescription
                self.loading = false
            }
        }
    }

    func permitsEdit(range: NSRange, replacement: String, removed: String, currentLength: Int) -> Bool {
        guard !readOnly, !toolManaged else { return false }
        let utf8Count = byteCount - removed.utf8.count + replacement.utf8.count
        let fileBytes =
            encoding == "utf8"
            ? utf8Count + (hasBOM ? 3 : 0)
            : (currentLength - range.length + replacement.utf16.count) * 2 + 2
        guard utf8Count <= 8 * 1024 * 1024, fileBytes <= 8 * 1024 * 1024, !replacement.contains("\0") else {
            inputError = "当前仅支持不含空字符、大小不超过 8 MiB 的文本"
            return false
        }
        inputError = nil
        return !closed && !closing && !synchronizationFailed
    }

    func replaced(range: NSRange, text: String, removed: String) {
        guard !closed, !synchronizationFailed else { return }
        pauseAutoSave()
        let expected = edits.revision
        edits.edited()
        semantic?.didReplace()
        byteCount += text.utf8.count - removed.utf8.count
        onEdit?()  // Pin a preview immediately, before another file can replace it.
        let previous = tail
        let engine = engine
        tail = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            await previous?.value
            guard let self, !self.closed, !self.synchronizationFailed else { return }
            do { try await engine.replace(expected: expected, range: range, text: text) } catch {
                self.synchronizationFailed = true
                self.error = "文本同步失败，更改仍保留在编辑区：" + error.localizedDescription
                self.editor?.textView.isEditable = false
            }
        }
    }
    func inputChanged(composing: Bool) {
        let finishedComposition = self.composing && !composing
        self.composing = composing
        if finishedComposition { semantic?.refreshDiagnostics() }
        scheduleAutoSave()
        if !composing { editor?.presentation?.schedule(delay: 70) }
    }
    func pauseAutoSave() {
        debounce?.cancel()
        debounce = nil
    }
    func suspendAutoSaveForClosing() {
        autoSaveSuspended = true
        pauseAutoSave()
        for (token, automatic) in saves.values where automatic { token.cancel() }
        editor?.textView.unmarkText()
        composing = editor?.textView.hasMarkedText() ?? false
        closing = true
        editor?.textView.isEditable = false
    }
    func resumeAutoSaveAfterClosing() {
        autoSaveSuspended = false
        closing = false
        editor?.textView.isEditable = !closed && !synchronizationFailed && !readOnly && !toolManaged
        scheduleAutoSave()
    }
    func finishPendingOperations() async { await tail?.value }
    func syntax(range: NSRange, revision: UInt64) async throws -> SyntaxHighlight {
        await tail?.value
        guard !closed, !synchronizationFailed, edits.revision == revision, !Task.isCancelled else {
            throw CancellationError()
        }
        return try await engine.syntax(revision: revision, range: range)
    }
    private func scheduleAutoSave() {
        pauseAutoSave()
        guard autoSave, isDirty, !composing, error == nil, !closed, !autoSaveSuspended, !toolManaged else { return }
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            guard !Task.isCancelled, let self, self.autoSave, !self.composing else { return }
            _ = await self.save(automatic: true)
        }
    }
    @discardableResult func save(automatic: Bool = false, forClosing: Bool = false) async -> Bool {
        guard !closing || forClosing else { return false }
        guard !closed, !loading, loadError == nil, !synchronizationFailed, !composing else { return false }
        guard isDirty else { return true }
        if !automatic { pauseAutoSave() }
        let revision = edits.revision
        let breakpointSnapshot = semantic?.breakpointSnapshot() ?? []
        let previous = tail
        let engine = engine
        let token = DocumentSaveCancellation()
        let saveID = UUID()
        saves[saveID] = (token, automatic)
        savingCount += 1
        let operation = Task { [weak self, access] () -> Bool in
            defer { withExtendedLifetime(access) {} }
            await previous?.value
            guard let self else { return false }
            defer {
                self.savingCount -= 1
                self.saves[saveID] = nil
            }
            guard !self.closed, !self.synchronizationFailed, !self.composing,
                !automatic || (self.autoSave && !self.autoSaveSuspended)
            else { return false }
            do {
                try await engine.save(revision: revision, cancellation: token)
                self.edits.saved(revision)
                self.semantic?.saved(breakpoints: breakpointSnapshot)
                self.error = nil
                return true
            } catch is CancellationError {
                return false
            } catch {
                self.error = error.localizedDescription
                return false
            }
        }
        tail = Task { _ = await operation.value }
        return await operation.value
    }
    func close() {
        closed = true
        semantic?.close()
        editor?.presentation?.cancel()
        pauseAutoSave()
        for (token, _) in saves.values { token.cancel() }
    }
    func reveal(_ range: LSPRange) {
        pendingReveal = range
        guard !loading, let view = editor?.textView else { return }
        pendingReveal = nil
        if let semantic {
            semantic.reveal(range)
        } else if let source = view.textStorage?.mutableString,
            let selection = range.range(in: editor!.presentation!.gutter.lines, source: source)
        {
            view.setSelectedRange(selection)
            view.scrollRangeToVisible(selection)
        }
    }
    func reloadedAfterTool(language: DartWorkspaceController?, web: WebWorkspaceController? = nil) -> EditorDocument {
        let replacement = EditorDocument(path: path, access: access, autoSave: autoSave, language: language, web: web)
        replacement.onEdit = onEdit
        return replacement
    }
}
