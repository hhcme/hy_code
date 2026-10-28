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
    private(set) var largeFile: LargeFileEditorState?
    private(set) var markupPreview: MarkupPreviewController?
    var pendingReveal: LSPRange?
    private(set) var loading = true
    private(set) var loadError: String?
    private(set) var error: String?
    private(set) var inputError: String?
    private(set) var edits = DocumentEditState()
    private var needsReloadAfterSave = false
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
    @ObservationIgnored private var cacheRelease: DocumentSaveCancellation?
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
    /// Serialized by the existing Rust owner, independent of save/undo state.
    func releaseRebuildableCaches() async throws -> Bool {
        guard !loading, !closed, !closing else { return false }
        let ticket = DocumentSaveCancellation()
        cacheRelease = ticket
        defer { if cacheRelease === ticket { cacheRelease = nil } }
        defer { withExtendedLifetime(access) {} }
        return try await engine.trimRebuildableCaches(cancellation: ticket)
    }
    func cancelCacheRelease() { cacheRelease?.cancel() }
    var semanticByteCount: Int { largeFile.map { Int(clamping: $0.page.totalBytes) } ?? byteCount }
    var workspaceRoot: URL { access.url }
    var workspaceAccess: WorkspaceAccess { access }
    var status: String {
        if loading { return "正在打开…" }
        if loadError != nil { return "无法编辑" }
        if readOnly { return "依赖源代码 · 只读" }
        if toolManaged { return "工具操作中 · 文档暂时只读" }
        if savingCount > 0 { return "正在保存…" }
        if needsReloadAfterSave { return "已写入磁盘 · 需重新载入" }
        if error != nil { return "保存失败 · 更改已保留" }
        if isDirty { return autoSave ? "等待保存" : "未保存" }
        return "已保存"
    }

    init(
        path: String, access: WorkspaceAccess, autoSave: Bool, language: DartWorkspaceController? = nil,
        web: WebWorkspaceController? = nil, native: NativeToolsController? = nil
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
                if let page = content.largePage { self.largeFile = LargeFileEditorState(page: page, document: self) }
                self.editor = NativeTextEditor(document: self, content: content)
                if let format = MarkupFormat.detect(path) {
                    self.markupPreview = MarkupPreviewController(document: self, format: format)
                }
                let owner: (any EditorLanguageController)? =
                    path.lowercased().hasSuffix(".dart")
                    ? language
                    : WebLanguage.detect(path) != nil ? web : native?.owner(path)
                if let owner, content.largePage == nil, content.byteCount <= 1_048_576 {
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
        guard largeFile?.busy != true else { return false }
        let utf8Count = byteCount - removed.utf8.count + replacement.utf8.count
        if let largeFile {
            guard utf8Count <= 1_048_576, !replacement.contains("\0") else {
                inputError = "当前片段的编辑内容限 1 MiB 且不能包含空字符；可切换片段继续编辑"
                return false
            }
            guard
                (largeFile.page.encodedCount(replacement) + largeFile.page.encodedCount(removed))
                    <= largeFile.page.remainingBytes,
                largeFile.page.remainingPieces >= 3
            else {
                inputError = "分段编辑已接近内存或片段预算；请先保存，已有修改仍可保存"
                return false
            }
            inputError = nil
            return !closed && !closing && !synchronizationFailed
        }
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

    func permitsBatch(ranges: [NSRange], replacements: [String], source: NSString) -> Bool {
        guard ranges.count == replacements.count, !readOnly, !toolManaged,
            !closed, !closing, !synchronizationFailed, largeFile?.busy != true
        else { return false }
        let sorted = ranges.sorted { $0.location < $1.location }
        var end = 0
        for range in sorted {
            guard range.location >= end, range.location <= source.length, range.length <= source.length - range.location
            else { return false }
            end = NSMaxRange(range)
        }
        var cost = 0
        var peak = byteCount
        var peakUTF16 = source.length
        for (range, text) in zip(ranges, replacements) {
            let removed = source.substring(with: range)
            guard !text.contains("\0") else {
                inputError = "纯文本编辑不接受空字符"
                return false
            }
            if let largeFile { cost += largeFile.page.encodedCount(text) + largeFile.page.encodedCount(removed) }
            peak += max(0, text.utf8.count - removed.utf8.count)
            peakUTF16 += max(0, text.utf16.count - range.length)
        }
        if let largeFile {
            guard ranges.count <= 1_024, peak <= 1_048_576, cost <= largeFile.page.remainingBytes,
                ranges.count * 3 <= largeFile.page.remainingPieces
            else {
                inputError = "批量替换超过当前片段或编辑预算；已有修改仍可保存，请缩小范围或先保存"
                return false
            }
        } else {
            let encodedPeak = encoding == "utf8" ? peak + (hasBOM ? 3 : 0) : peakUTF16 * 2 + 2
            guard peak <= 8 * 1024 * 1024, encodedPeak <= 8 * 1024 * 1024 else {
                inputError = "普通文档编辑结果超过 8 MiB；大文件可重新打开进入分段模式"
                return false
            }
        }
        inputError = nil
        return true
    }
    func replaced(range: NSRange, text: String, removed: String) {
        guard !closed, !synchronizationFailed else { return }
        pauseAutoSave()
        if let largeFile {
            largeFile.cancellation?.cancel()
            let delta = largeFile.page.encodedCount(text) - largeFile.page.encodedCount(removed)
            largeFile.page.end = UInt64(Int64(largeFile.page.end) + Int64(delta))
            largeFile.page.totalBytes = UInt64(Int64(largeFile.page.totalBytes) + Int64(delta))
            for (token, automatic) in saves.values where automatic { token.cancel() }
        }
        let expected = edits.revision
        edits.edited()
        largeFile?.reserve(
            revision: edits.revision,
            bytes: (largeFile?.page.encodedCount(text) ?? 0) + (largeFile?.page.encodedCount(removed) ?? 0))
        semantic?.didReplace()
        byteCount += text.utf8.count - removed.utf8.count
        onEdit?()  // Pin a preview immediately, before another file can replace it.
        let previous = tail
        let engine = engine
        tail = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            await previous?.value
            guard let self, !self.closed, !self.synchronizationFailed else { return }
            do {
                if let state = try await engine.replace(expected: expected, range: range, text: text) {
                    self.largeFile?.acknowledge(state, revision: expected + 1)
                }
            } catch {
                self.synchronizationFailed = true
                self.error = "文本同步失败，更改仍保留在编辑区：" + error.localizedDescription
                self.editor?.textView.isEditable = false
            }
        }
        markupPreview?.edited()
    }
    func inputChanged(composing: Bool) {
        let finishedComposition = self.composing && !composing
        self.composing = composing
        if finishedComposition { semantic?.refreshDiagnostics() }
        scheduleAutoSave()
        if !composing { editor?.presentation?.schedule(delay: 70) }
        if !composing { markupPreview?.edited() }
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
        largeFile?.cancellation?.cancel()
        editor?.textView.isEditable = false
    }
    func resumeAutoSaveAfterClosing() {
        autoSaveSuspended = false
        closing = false
        editor?.textView.isEditable = !closed && !synchronizationFailed && !readOnly && !toolManaged
        scheduleAutoSave()
        markupPreview?.edited()
    }
    func finishPendingOperations() async { await tail?.value }
    func textSnapshot(revision: UInt64) async throws -> String {
        await tail?.value
        guard !closed, !synchronizationFailed, !composing, !loading, largeFile == nil,
            edits.revision == revision, !Task.isCancelled
        else { throw CancellationError() }
        return try await engine.textSnapshot(revision: revision)
    }
    func syntax(range: NSRange, revision: UInt64) async throws -> SyntaxHighlight {
        await tail?.value
        guard !closed, !synchronizationFailed, edits.revision == revision, !Task.isCancelled else {
            throw CancellationError()
        }
        return try await engine.syntax(revision: revision, range: range)
    }
    func markup(revision: UInt64, markdown: Bool, cancellation: DocumentSaveCancellation? = nil) async throws
        -> MarkupPreviewContent
    {
        await tail?.value
        guard !closed, !synchronizationFailed, !composing, edits.revision == revision, !Task.isCancelled else {
            throw CancellationError()
        }
        return try await engine.markup(revision: revision, markdown: markdown, cancellation: cancellation)
    }
    private func scheduleAutoSave() {
        pauseAutoSave()
        guard autoSave, isDirty, !composing, error == nil, !closed, !autoSaveSuspended, !toolManaged,
            largeFile?.busy != true
        else { return }
        let delay = largeFile == nil ? 800 : 3_000
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, self.autoSave, !self.composing else { return }
            _ = await self.save(automatic: true)
        }
    }
    @discardableResult func save(automatic: Bool = false, forClosing: Bool = false) async -> Bool {
        guard !closing || forClosing else { return false }
        if largeFile?.busy == true {
            await tail?.value
            return await save(automatic: automatic, forClosing: forClosing)
        }
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
                if let status = try await engine.largeStatus() {
                    self.largeFile?.acknowledge(status, revision: revision)
                }
                self.edits.saved(revision)
                self.semantic?.saved(breakpoints: breakpointSnapshot)
                self.error = nil
                return true
            } catch is CancellationError {
                return false
            } catch let failure as WorkspaceFailure where failure.code == "save_committed_rebase" {
                self.edits.saved(revision)
                self.needsReloadAfterSave = true
                self.synchronizationFailed = true
                self.editor?.textView.isEditable = false
                self.error = failure.message
                return !self.isDirty
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
        cancelCacheRelease()
        largeFile?.cancellation?.cancel()
        if loading { tail?.cancel() }
        markupPreview?.deactivate()
        semantic?.close()
        editor?.presentation?.cancel()
        pauseAutoSave()
        for (token, _) in saves.values { token.cancel() }
    }
    func reveal(_ range: LSPRange) {
        pendingReveal = range
        guard !loading, let view = editor?.textView else { return }
        pendingReveal = nil
        if let largeFile {
            largeFile.message = "大文件暂未建立全局行索引，请使用字节位置或整文件查找定位"
            return
        }
        if let semantic {
            semantic.reveal(range)
        } else if let source = view.textStorage?.mutableString,
            let selection = range.range(in: editor!.presentation!.gutter.lines, source: source)
        {
            view.setSelectedRange(selection)
            view.scrollRangeToVisible(selection)
        }
    }
    func largeAction(_ action: LargeFileAction) {
        guard let state = largeFile, !state.busy, !closed, !closing, !synchronizationFailed, !toolManaged else {
            return
        }
        if case .history = action, readOnly { return }
        editor?.textView.unmarkText()
        guard !composing else { return }
        pauseAutoSave()
        state.busy = true
        state.message = nil
        let cancellation = DocumentSaveCancellation()
        state.cancellation = cancellation
        editor?.textView.isEditable = false
        let previous = tail
        let engine = engine
        tail = Task(priority: .utility) { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            await previous?.value
            guard let self else { return }
            defer {
                state.busy = false
                state.cancellation = nil
                self.editor?.textView.isEditable =
                    !self.closed && !self.closing && !self.readOnly && !self.toolManaged && !self.synchronizationFailed
                self.scheduleAutoSave()
            }
            guard !self.closed, !self.closing, !self.synchronizationFailed else { return }
            do {
                let revision = self.edits.revision
                var target: UInt64
                var selection: String?
                var prepared: TextDocumentContent?
                switch action {
                case .page(let offset): target = offset
                case .history(let redo):
                    try cancellation.checkCancellation()
                    prepared = try await engine.history(revision: revision, redo: redo)
                    target = 0
                    self.edits.edited()
                    self.onEdit?()
                    self.markupPreview?.edited()
                case .find(let text, let from):
                    var match = try await engine.find(
                        revision: revision, text: text, from: from, cancellation: cancellation)
                    if match == nil, from > 0 {
                        match = try await engine.find(
                            revision: revision, text: text, from: 0, cancellation: cancellation)
                    }
                    guard let match else {
                        state.message = "整个文件未找到匹配文本"
                        return
                    }
                    state.nextMatch = match + (state.page.encoding == "utf8" ? 1 : 2)
                    target = match
                    selection = text
                }
                let content: TextDocumentContent
                if let prepared {
                    content = prepared
                } else {
                    content = try await engine.page(
                        revision: self.edits.revision, offset: target, cancellation: cancellation)
                }
                guard !self.closed, let page = content.largePage else { return }
                self.byteCount = content.byteCount
                state.accept(page)
                self.editor?.loadPage(content)
                if let selection, let view = self.editor?.textView {
                    let range = (content.text as NSString).range(of: selection)
                    if range.location != NSNotFound {
                        view.setSelectedRange(range)
                        view.scrollRangeToVisible(range)
                    }
                }
            } catch is CancellationError {
                state.message = "操作已取消"
            } catch { state.message = error.localizedDescription }
        }
    }
    func reloadedAfterTool(
        language: DartWorkspaceController?, web: WebWorkspaceController? = nil, native: NativeToolsController? = nil
    ) -> EditorDocument {
        let replacement = EditorDocument(
            path: path, access: access, autoSave: autoSave, language: language, web: web, native: native)
        replacement.onEdit = onEdit
        return replacement
    }
}
