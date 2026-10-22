import AppKit
import Observation

@MainActor @Observable final class EditorWorkspace {
    private(set) var documents: [String: EditorDocument] = [:]
    weak var language: DartWorkspaceController?
    weak var web: WebWorkspaceController?
    var packageToolRoot: URL?
    var preparingLanguageEdit = false
    var editPreview: LanguageEditPreview?
    var editRequest = UUID()
    var isDocumentVisible: ((String) -> Bool)?
    var onLanguageFilesApplied: (([String]) -> Void)?
    private var pendingToolReload: [String: UUID] = [:]
    private func isManifest(_ document: EditorDocument) -> Bool {
        !document.readOnly
            && [
                "pubspec.yaml", "pubspec.lock", "package.json", "package-lock.json", "npm-shrinkwrap.json",
                "pnpm-lock.yaml", "pnpm-workspace.yaml", "yarn.lock", ".yarnrc.yml",
            ].contains(document.sourceURL.lastPathComponent)
    }
    var autoSave = UserDefaults.standard.object(forKey: "editor.autoSave") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: "editor.autoSave")
            for document in documents.values { document.autoSave = autoSave }
        }
    }
    private(set) var isClosing = false
    func open(path: String, access: WorkspaceAccess, onEdit: @escaping () -> Void) {
        guard !isClosing, documents[path] == nil else { return }
        let document = EditorDocument(path: path, access: access, autoSave: autoSave, language: language, web: web)
        if packageToolRoot != nil && isManifest(document) { document.toolManaged = true }
        document.onEdit = { [weak self] in
            // Include buffers above the semantic size limit and other language
            // families in the fence used by unversioned workspace edit replies.
            self?.web?.invalidateEdits()
            onEdit()
        }
        documents[path] = document
    }
    func remove(_ path: String) {
        web?.invalidateEdits()
        documents.removeValue(forKey: path)?.close()
    }
    func reset() {
        editRequest = UUID()
        editPreview = nil
        preparingLanguageEdit = false
        packageToolRoot = nil
        pendingToolReload.removeAll()
        for document in documents.values { document.close() }
        documents.removeAll()
    }
    func prune(keeping paths: Set<String>) {
        for (path, document) in documents where !paths.contains(path) && !document.isDirty { remove(path) }
    }
    func saveAll() async -> Bool {
        guard !isClosing else { return false }
        var success = true
        for document in documents.values where document.isDirty {
            if !(await document.save()) { success = false }
        }
        return success && !documents.values.contains(where: \.isDirty)
    }
    func preparePackageTool(_ root: URL) async -> Bool {
        guard !isClosing, packageToolRoot == nil, !preparingLanguageEdit, editPreview == nil else { return false }
        packageToolRoot = root
        let protected = documents.values.filter(isManifest)
        for document in protected { document.toolManaged = true }
        for document in protected {
            await document.finishPendingOperations()
            if document.isDirty, !(await document.save()) {
                finishPackageTool(root, reload: false)
                return false
            }
        }
        guard !isClosing, !protected.contains(where: \.isDirty) else {
            finishPackageTool(root, reload: false)
            return false
        }
        return true
    }
    func finishPackageTool(_ root: URL, reload: Bool = true) {
        guard packageToolRoot == root else { return }
        packageToolRoot = nil
        for (path, document) in documents where isManifest(document) {
            document.toolManaged = false
            if reload, isClosing, !document.isDirty { pendingToolReload[path] = document.id }
            if reload, !isClosing, !document.isDirty {
                document.close()
                documents[path] = document.reloadedAfterTool(language: language, web: web)
            }
        }
    }
    /// UI only, called after a user's close/reload/project/quit action. Background
    /// tests never instantiate this owner or invoke alerts.
    func confirmClosing(_ candidates: [EditorDocument], completion: @escaping (Bool) async -> Void) {
        guard !isClosing else {
            Task { await completion(false) }
            return
        }
        isClosing = true
        let protected = Array(documents.values)
        for document in protected { document.suspendAutoSaveForClosing() }
        Task {
            // Cancel not-yet-committed automatic writes, then drain every
            // protected document before discard/reopen can race an old writer.
            for document in protected { await document.finishPendingOperations() }
            let dirty = candidates.filter(\.isDirty)
            if dirty.isEmpty {
                await finishClosing(true, protected: protected, completion: completion)
            } else {
                presentClosePrompt(dirty, candidates: candidates, protected: protected, completion: completion)
            }
        }
    }
    func releaseClosingProtection() { isClosing = false }
    private func finishClosing(_ allowed: Bool, protected: [EditorDocument], completion: (Bool) async -> Void) async {
        await completion(allowed)
        isClosing = false
        for document in protected { document.resumeAutoSaveAfterClosing() }
        let pending = pendingToolReload
        pendingToolReload.removeAll()
        for (path, id) in pending {
            if let document = documents[path], document.id == id, !document.isDirty {
                document.close()
                documents[path] = document.reloadedAfterTool(language: language, web: web)
            }
        }
    }
    private func presentClosePrompt(
        _ dirty: [EditorDocument], candidates: [EditorDocument],
        protected: [EditorDocument], completion: @escaping (Bool) async -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = dirty.count == 1 ? "保存对“\(dirty[0].path)”的更改？" : "保存 \(dirty.count) 个文件的更改？"
        alert.informativeText = "保存失败或磁盘文件发生变化时会保留编辑内容。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "丢弃更改")
        alert.addButton(withTitle: "取消")
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else {
                Task { await completion(false) }
                return
            }
            if response == .alertFirstButtonReturn {
                Task {
                    var allowed = true
                    for document in dirty { if !(await document.save(forClosing: true)) { allowed = false } }
                    await self.finishClosing(
                        allowed && !candidates.contains(where: \.isDirty), protected: protected, completion: completion)
                }
            } else {
                Task {
                    await self.finishClosing(
                        response == .alertSecondButtonReturn, protected: protected, completion: completion)
                }
            }
        }
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
