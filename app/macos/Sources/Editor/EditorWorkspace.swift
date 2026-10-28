import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable final class EditorWorkspace {
    private(set) var videos: [String: VideoPreviewDocument] = [:]
    private(set) var images: [String: ImagePreviewDocument] = [:]
    private(set) var documents: [String: EditorDocument] = [:]
    weak var language: DartWorkspaceController?
    weak var web: WebWorkspaceController?
    weak var native: NativeToolsController?
    var packageToolRoot: URL?
    private(set) var agentWriteID: UUID?
    var preparingLanguageEdit = false
    var editPreview: LanguageEditPreview?
    var editRequest = UUID()
    var isDocumentVisible: ((String) -> Bool)?
    var onLanguageFilesApplied: (([String]) -> Void)?
    private var pendingToolReload: [String: UUID] = [:]
    @ObservationIgnored private var sharedCacheRelease: DocumentSaveCancellation?
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
        guard !isClosing, documents[path] == nil, images[path] == nil, videos[path] == nil else { return }
        if ImagePreviewFormat.matches(path) {
            images[path] = ImagePreviewDocument(path: path, access: access)
            return
        }
        if VideoPreviewFormat.matches(path) {
            videos[path] = VideoPreviewDocument(path: path, access: access)
            return
        }
        let document = EditorDocument(
            path: path, access: access, autoSave: autoSave, language: language, web: web, native: native)
        if agentWriteID != nil || (packageToolRoot != nil && isManifest(document)) { document.toolManaged = true }
        document.onEdit = { [weak self] in
            // Include buffers above the semantic size limit and other language
            // families in the fence used by unversioned workspace edit replies.
            self?.web?.invalidateEdits()
            if let native = self?.native { for owner in native.owners { owner.invalidateEdits() } }
            onEdit()
        }
        documents[path] = document
    }
    func remove(_ path: String) {
        web?.invalidateEdits()
        if let native { for owner in native.owners { owner.invalidateEdits() } }
        documents.removeValue(forKey: path)?.close()
        images.removeValue(forKey: path)?.suspend()
        videos.removeValue(forKey: path)?.suspend()
    }
    func reset() {
        sharedCacheRelease?.cancel()
        editRequest = UUID()
        editPreview = nil
        preparingLanguageEdit = false
        packageToolRoot = nil
        agentWriteID = nil
        pendingToolReload.removeAll()
        for document in documents.values { document.close() }
        documents.removeAll()
        for image in images.values { image.suspend() }
        images.removeAll()
        for video in videos.values { video.suspend() }
        videos.removeAll()
    }
    func activatePreview(path: String?) {
        sharedCacheRelease?.cancel()
        if let path { documents[path]?.cancelCacheRelease() }
        for (key, video) in videos {
            if key == path { video.activate() } else { video.suspend() }
        }
        for (key, image) in images {
            if key == path { image.activate() } else { image.suspend() }
        }
    }
    func releaseInactiveCaches(activePath: () -> String?) async -> WorkbenchCacheCleanup {
        var result = WorkbenchCacheCleanup()
        let ticket = DocumentSaveCancellation()
        sharedCacheRelease = ticket
        defer { if sharedCacheRelease === ticket { sharedCacheRelease = nil } }
        // Snapshot owners, not their text. No tabs are closed, native undo
        // managers reset, buffers reloaded, tasks cancelled, or services stopped.
        for document in Array(documents.values) where document.path != activePath() {
            do {
                if try await document.releaseRebuildableCaches() { result.documents += 1 }
            } catch is CancellationError {
                // A newly activated/closed document keeps its queued cache.
            } catch { result.failures += 1 }
        }
        do {
            result.grammars = try await NativeCacheMaintenance.shared.releaseUnusedSyntaxGrammars(
                protecting: activePath(), cancellation: ticket)
        } catch is CancellationError {
        } catch { result.failures += 1 }
        return result
    }
    func prune(keeping paths: Set<String>) {
        for path in videos.keys where !paths.contains(path) { remove(path) }
        for path in images.keys where !paths.contains(path) { remove(path) }
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
        guard !isClosing, agentWriteID == nil, packageToolRoot == nil, !preparingLanguageEdit, editPreview == nil else {
            return false
        }
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
    /// A writing agent owns disk changes while the native document owners are
    /// frozen. Never save dirty buffers implicitly to enable an agent task.
    func prepareAgentWrite(_ id: UUID) async -> Bool {
        guard !isClosing, agentWriteID == nil, packageToolRoot == nil, !preparingLanguageEdit, editPreview == nil,
            !documents.values.contains(where: { $0.isDirty || $0.composing || $0.loading })
        else { return false }
        agentWriteID = id
        let protected = Array(documents.values)
        for document in protected { document.toolManaged = true }
        for document in protected { await document.finishPendingOperations() }
        guard agentWriteID == id, !isClosing, !protected.contains(where: { $0.isDirty || $0.composing }) else {
            finishAgentWrite(id, reload: false)
            return false
        }
        return true
    }
    func finishAgentWrite(_ id: UUID, reload: Bool = true) {
        guard agentWriteID == id else { return }
        agentWriteID = nil
        for (path, document) in documents {
            document.toolManaged = false
            guard reload, !document.isDirty, !document.readOnly else { continue }
            if isClosing {
                pendingToolReload[path] = document.id
            } else {
                document.close()
                documents[path] = document.reloadedAfterTool(language: language, web: web, native: native)
            }
        }
    }
    func finishPackageTool(_ root: URL, reload: Bool = true) {
        guard packageToolRoot == root else { return }
        packageToolRoot = nil
        for (path, document) in documents where isManifest(document) {
            document.toolManaged = false
            if reload, isClosing, !document.isDirty { pendingToolReload[path] = document.id }
            if reload, !isClosing, !document.isDirty {
                document.close()
                documents[path] = document.reloadedAfterTool(language: language, web: web, native: native)
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
                documents[path] = document.reloadedAfterTool(language: language, web: web, native: native)
            }
        }
    }
    private func presentClosePrompt(
        _ dirty: [EditorDocument], candidates: [EditorDocument],
        protected: [EditorDocument], completion: @escaping (Bool) async -> Void
    ) {
        let finish: (WorkbenchPromptResponse) -> Void = { [weak self] response in
            guard let self else {
                Task { await completion(false) }
                return
            }
            if response == .accept {
                Task {
                    var allowed = true
                    for document in dirty { if !(await document.save(forClosing: true)) { allowed = false } }
                    await self.finishClosing(
                        allowed && !candidates.contains(where: \.isDirty), protected: protected, completion: completion)
                }
            } else {
                Task {
                    await self.finishClosing(
                        response == .alternate, protected: protected, completion: completion)
                }
            }
        }
        if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            WorkbenchPrompt.present(
                in: window,
                title: dirty.count == 1 ? "保存对“\(dirty[0].path)”的更改？" : "保存 \(dirty.count) 个文件的更改？",
                detail: "保存失败或磁盘文件发生变化时会保留编辑内容。", accept: "保存", alternate: "丢弃更改"
            ) {
                response, _ in finish(response)
            }
        } else {
            finish(.cancel)
        }
    }
}
