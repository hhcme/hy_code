import AppKit
import Observation

@MainActor @Observable final class EditorWorkspace {
    private(set) var documents: [String: EditorDocument] = [:]
    var autoSave = UserDefaults.standard.object(forKey: "editor.autoSave") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: "editor.autoSave")
            for document in documents.values { document.autoSave = autoSave }
        }
    }
    private(set) var isClosing = false
    func open(path: String, access: WorkspaceAccess, onEdit: @escaping () -> Void) {
        guard !isClosing, documents[path] == nil else { return }
        let document = EditorDocument(path: path, access: access, autoSave: autoSave)
        document.onEdit = onEdit
        documents[path] = document
    }
    func remove(_ path: String) { documents.removeValue(forKey: path)?.close() }
    func reset() {
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
    /// UI only, called after a user's close/reload/project/quit action. Background
    /// tests never instantiate this owner or invoke alerts.
    func confirmClosing(_ candidates: [EditorDocument], completion: @escaping (Bool) -> Void) {
        guard !isClosing else {
            completion(false)
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
                finishClosing(true, protected: protected, completion: completion)
            } else {
                presentClosePrompt(dirty, candidates: candidates, protected: protected, completion: completion)
            }
        }
    }
    private func finishClosing(_ allowed: Bool, protected: [EditorDocument], completion: (Bool) -> Void) {
        isClosing = false
        completion(allowed)
        for document in protected { document.resumeAutoSaveAfterClosing() }
    }
    private func presentClosePrompt(
        _ dirty: [EditorDocument], candidates: [EditorDocument],
        protected: [EditorDocument], completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = dirty.count == 1 ? "保存对“\(dirty[0].path)”的更改？" : "保存 \(dirty.count) 个文件的更改？"
        alert.informativeText = "保存失败或磁盘文件发生变化时会保留编辑内容。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "丢弃更改")
        alert.addButton(withTitle: "取消")
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else {
                completion(false)
                return
            }
            if response == .alertFirstButtonReturn {
                Task {
                    var allowed = true
                    for document in dirty { if !(await document.save(forClosing: true)) { allowed = false } }
                    self.finishClosing(
                        allowed && !candidates.contains(where: \.isDirty), protected: protected, completion: completion)
                }
            } else {
                self.finishClosing(response == .alertSecondButtonReturn, protected: protected, completion: completion)
            }
        }
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}
