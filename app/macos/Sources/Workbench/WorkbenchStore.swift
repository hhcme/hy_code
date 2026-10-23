import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable
final class WorkbenchStore {
    private(set) var rootURL: URL?
    private(set) var sessionID = UUID()
    private(set) var tabs = BrowserTabs()
    private(set) var history = NavigationHistory()
    private(set) var snapshots: [String: DirectorySnapshot] = [:]
    @ObservationIgnored private(set) var treeNameWidths: [String: [String: Double]] = [:]
    private(set) var errors: [String: String] = [:]
    private(set) var loadingPaths: Set<String> = []
    private(set) var treeRevision = 0
    private(set) var treeCollapseRevision = 0
    private(set) var treeResetRevision = 0
    private(set) var directoryRevisions: [String: Int] = [:]
    private(set) var browsingLocation: BrowserLocation?
    private(set) var recentProjects: RecentProjects = {
        guard let data = UserDefaults.standard.data(forKey: "workbench.recentProjects") else { return RecentProjects() }
        return (try? JSONDecoder().decode(RecentProjects.self, from: data)) ?? RecentProjects()
    }()
    var selectedEntry: WorkspaceEntry?
    var docking = WorkbenchDocking()
    let editing = EditorWorkspace()
    let dart = DartWorkspaceController()
    let flutter = FlutterWorkspaceController()
    let web = WebWorkspaceController()
    let problems = WorkspaceProblemsController()
    var analysisLanguage = "dart"
    var languageController: any EditorLanguageController { analysisLanguage == "web" ? web : dart }
    var autoSave: Bool {
        get { editing.autoSave }
        set { editing.autoSave = newValue }
    }
    var activeImage: ImagePreviewDocument? { tabs.active.flatMap { editing.images[$0.location.path] } }
    var activeDocument: EditorDocument? { tabs.active.flatMap { editing.documents[$0.location.path] } }
    @ObservationIgnored let dockingSession = UUID()
    var includeHidden = false { didSet { if oldValue != includeHidden { refresh() } } }
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var requests: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var projectIntent = UUID()
    @ObservationIgnored private var startupAttempted = false
    @ObservationIgnored private var requestIDs: [String: UUID] = [:]

    /// The header, switcher and tree derive identity from the active directory,
    /// never from the most recent history entry.
    var currentProject: RecentProject? { rootURL.map { RecentProject(path: $0.path) } }
    var projectName: String { currentProject?.name ?? "HyCode" }
    var location: BrowserLocation? { browsingLocation }
    var currentDirectory: String {
        guard let location else { return "" }
        if location.path.hasPrefix("/") { return "" }
        if case .directory(let path) = location { return path }
        return location.path.split(separator: "/").dropLast().joined(separator: "/")
    }
    var currentSnapshot: DirectorySnapshot? { snapshots[currentDirectory] }
    var isLoading: Bool { !loadingPaths.isEmpty }
    var informationEntry: WorkspaceEntry? {
        if let selectedEntry { return selectedEntry }
        if case .file(let entry) = location { return entry }
        guard rootURL != nil else { return nil }
        return WorkspaceEntry(name: location?.title ?? projectName, relativePath: currentDirectory, kind: .directory)
    }

    /// Only invoked by explicit user actions, never startup or background tests.
    func chooseProject() {
        guard !editing.isClosing else { return }
        startupAttempted = true
        projectIntent = UUID()
        let panel = NSOpenPanel()
        panel.title = "打开项目目录"
        panel.prompt = "打开项目"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let rootURL { panel.directoryURL = rootURL }
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openProject(url)
        }
    }

    func openProject(_ url: URL) {
        guard !editing.isClosing else { return }
        startupAttempted = true
        let intent = UUID()
        projectIntent = intent
        editing.confirmClosing(Array(editing.documents.values)) { [weak self] allowed in
            guard let self, allowed, self.projectIntent == intent else { return }
            await self.stopProjectTools()
            guard self.projectIntent == intent else { return }
            self.editing.releaseClosingProtection()
            self.installProject(url)
        }
    }

    private func installProject(_ url: URL) {
        resetProject()
        access = WorkspaceAccess(url: url)
        rootURL = url
        problems.configure(root: url)
        dart.onDiagnosticsChanged = { [weak self] values, limited in
            self?.problems.update("dart", values: values, limited: limited)
        }
        web.onDiagnosticsChanged = { [weak self] values, limited in
            self?.problems.update("web", values: values, limited: limited)
        }
        web.projectAnalysis.onDartProject = { [weak self] in self?.dart.startProjectAnalysis() }
        editing.language = dart
        editing.web = web
        editing.isDocumentVisible = { [weak self] path in self?.tabs.tabs.contains { $0.location.path == path } == true
        }
        editing.onLanguageFilesApplied = { [weak self] paths in
            guard let self else { return }
            let active = self.tabs.activeID
            for path in paths {
                self.tabs.open(
                    .file(
                        WorkspaceEntry(
                            name: URL(fileURLWithPath: path).lastPathComponent,
                            relativePath: path, kind: .file)), preview: false)
            }
            if let active { self.tabs.activate(active) }
        }
        web.onEditPreview = { [weak self] edit, feature, revision, title in
            self?.editing.previewLanguageEdit(edit, feature: feature, revision: revision, title: title)
        }
        web.configure(access: access)
        dart.flutter = flutter
        dart.configure(access: access)
        flutter.configure(access: access)
        flutter.onNavigate = { [weak self] in self?.navigateSemantic($0) }
        flutter.executionAllowed = { [weak self] in
            guard let self else { return false }
            return !self.dart.toolRunning && !self.web.toolRunning && !self.editing.isClosing
                && !self.editing.preparingLanguageEdit && self.editing.editPreview == nil
        }
        flutter.prepareRun = { [weak self] in
            guard let self, !self.dart.toolRunning, !self.web.toolRunning, !self.editing.isClosing else { return false }
            return await self.editing.saveAll()
        }
        flutter.onReveal = { [weak self] in
            guard let self else { return }
            if !self.docking.isVisible(.debug) { self.docking.toggle(.debug) }
        }
        flutter.onBreakpointsChanged = { [weak self] in
            for document in self?.editing.documents.values ?? [String: EditorDocument]().values {
                document.editor?.presentation?.gutter.needsDisplay = true
            }
        }
        dart.onNavigate = { [weak self] in self?.navigateSemantic($0) }
        let session = sessionID
        dart.prepareTool = { [weak self] root in
            guard let self, self.sessionID == session, !self.web.toolRunning else { return false }
            return await self.editing.preparePackageTool(root)
        }
        web.executionAllowed = { [weak self] in
            guard let self else { return false }
            return !self.dart.toolRunning && !self.flutter.active && !self.flutter.commandRunning
                && !self.editing.isClosing
                && !self.editing.preparingLanguageEdit && self.editing.editPreview == nil
        }
        web.prepareTool = { [weak self] root in
            guard let self, self.sessionID == session, !self.dart.toolRunning, !self.editing.isClosing else {
                return false
            }
            guard await self.editing.saveAll() else { return false }
            return await self.editing.preparePackageTool(root)
        }
        web.finishedTool = { [weak self] root in
            guard let self, self.sessionID == session else { return }
            self.editing.finishPackageTool(root)
        }
        web.onNavigate = { [weak self] in self?.navigateSemantic($0) }
        web.onShowResults = { [weak self] in
            guard let self else { return }
            self.analysisLanguage = "web"
            if !self.docking.isVisible(.problems) { self.docking.toggle(.problems) }
        }
        dart.finishedTool = { [weak self] root in
            guard let self, self.sessionID == session else { return }
            self.editing.finishPackageTool(root)
        }
        dart.onShowResults = { [weak self] in
            guard let self else { return }
            self.analysisLanguage = "dart"
            if !self.docking.isVisible(.problems) { self.docking.toggle(.problems) }
        }
        navigate(.directory(""), preview: false)
        requestDirectory("")
        recentProjects.remember(RecentProject(path: url.path))
        saveRecentProjects()
        if let access {
            Task { [weak self, access] in
                let data = await Task.detached(priority: .utility) {
                    defer { withExtendedLifetime(access) {} }
                    return try? access.url.bookmarkData(
                        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                }.value
                guard let self, let data else { return }
                self.recentProjects.updateBookmark(data, path: url.standardizedFileURL.path)
                self.saveRecentProjects()
            }
        }
    }

    func switchProject(_ project: RecentProject) {
        guard !editing.isClosing else { return }
        startupAttempted = true
        guard rootURL?.standardizedFileURL.path != project.path else { return }
        let intent = UUID()
        projectIntent = intent
        Task { [weak self] in
            let url = await Task.detached(priority: .userInitiated) {
                if let bookmark = project.bookmark {
                    var stale = false
                    if let url = try? URL(
                        resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
                    {
                        return url
                    }
                }
                return URL(fileURLWithPath: project.path, isDirectory: true)
            }.value
            guard let self, self.projectIntent == intent else { return }
            self.openProject(url)
        }
    }

    private func saveRecentProjects() {
        if let data = try? JSONEncoder().encode(recentProjects) {
            UserDefaults.standard.set(data, forKey: "workbench.recentProjects")
        }
    }

    /// The first scene appearance may reopen the last workspace. Any explicit
    /// project action consumes startup so a delayed task cannot override it.
    func restorePreviousProjectIfNeeded() {
        guard !startupAttempted else { return }
        startupAttempted = true
        guard rootURL == nil, let project = recentProjects.startupProject else { return }
        switchProject(project)
    }

    private func stopProjectTools() async {
        let analysis = dart.stop()
        let runtime = flutter.stop()
        let web = web.stop()
        await analysis.value
        await runtime.value
        await web.value
    }

    func closeProject() {
        startupAttempted = true
        let intent = UUID()
        projectIntent = intent
        editing.confirmClosing(Array(editing.documents.values)) { [weak self] allowed in
            guard let self, allowed, self.projectIntent == intent else { return }
            await self.stopProjectTools()
            guard self.projectIntent == intent else { return }
            self.recentProjects.closeWorkspace()
            self.saveRecentProjects()
            self.resetProject()
        }
    }

    private func resetProject() {
        problems.configure(root: nil)
        editing.reset()
        dart.configure(access: nil)
        web.configure(access: nil)
        flutter.configure(access: nil)
        projectIntent = UUID()
        sessionID = UUID()
        for request in requests.values { request.cancel() }
        requests.removeAll()
        requestIDs.removeAll()
        loadingPaths.removeAll()
        snapshots.removeAll()
        treeNameWidths.removeAll()
        errors.removeAll()
        rootURL = nil
        access = nil
        selectedEntry = nil
        tabs = BrowserTabs()
        history = NavigationHistory()
        browsingLocation = nil
        directoryRevisions.removeAll()
        treeRevision += 1
    }

    func navigate(_ location: BrowserLocation, preview: Bool, recordHistory: Bool = true) {
        guard rootURL != nil, !editing.isClosing else { return }
        let currentEntries = snapshots[location.parentDirectory ?? ""]?.entries ?? []
        let resolved = location.resolvingFile(in: currentEntries)
        if case .file(let entry) = resolved, !ImagePreviewFormat.matches(entry.relativePath) {
            dart.refreshProject(path: entry.relativePath)
            web.refreshProject(path: entry.relativePath)
            analysisLanguage = WebLanguage.detect(entry.relativePath) != nil ? "web" : "dart"
        }
        browsingLocation = resolved
        tabs.open(resolved, preview: preview)
        if case .file(let entry) = resolved, let access {
            let session = sessionID
            editing.open(path: entry.relativePath, access: access) { [weak self] in
                guard let self, self.sessionID == session,
                    let tab = self.tabs.tabs.first(where: { $0.location.path == entry.relativePath })
                else { return }
                self.tabs.pin(tab.id)
            }
        }
        editing.prune(keeping: Set(tabs.tabs.map { $0.location.path }))
        editing.activateImage(path: tabs.active?.location.path)
        if recordHistory { history.visit(resolved) }
        if case .file(let entry) = resolved {
            selectedEntry = entry
        } else {
            selectedEntry = WorkspaceEntry(
                name: resolved.path.isEmpty ? projectName : resolved.title, relativePath: resolved.path,
                kind: .directory)
        }
        // A directory selection does not enumerate it or create a document tab.
        // Explicit outline expansion owns directory reads.
        if !resolved.isDirectory { requestDirectory(currentDirectory) }
    }

    func open(_ entry: WorkspaceEntry, preview: Bool) {
        navigate(entry.isDirectory ? .directory(entry.relativePath) : .file(entry), preview: preview)
    }

    func activateTab(_ id: UUID) {
        guard !editing.isClosing else { return }
        tabs.activate(id)
        editing.activateImage(path: tabs.active?.location.path)
        guard let active = tabs.active else { return }
        if !ImagePreviewFormat.matches(active.location.path) {
            dart.refreshProject(path: active.location.path)
            web.refreshProject(path: active.location.path)
            analysisLanguage = WebLanguage.detect(active.location.path) != nil ? "web" : "dart"
        }
        browsingLocation = active.location
        history.visit(active.location)
        if case .file(let entry) = active.location { selectedEntry = entry }
        requestDirectory(currentDirectory)
    }
    func pinTab(_ id: UUID) { tabs.pin(id) }
    func closeTab(_ id: UUID) {
        guard let tab = tabs.tabs.first(where: { $0.id == id }) else { return }
        let documents = editing.documents[tab.location.path].map { [$0] } ?? []
        let session = sessionID
        editing.confirmClosing(documents) { [weak self] allowed in
            guard let self, allowed, self.sessionID == session else { return }
            self.removeTab(id, path: tab.location.path)
        }
    }
    private func removeTab(_ id: UUID, path: String) {
        editing.remove(path)
        tabs.close(id)
        editing.activateImage(path: tabs.active?.location.path)
        selectedEntry = nil
        browsingLocation = tabs.active?.location ?? .directory(currentDirectory)
        if !ImagePreviewFormat.matches(browsingLocation?.path ?? "") {
            dart.refreshProject(path: browsingLocation?.path ?? "")
            web.refreshProject(path: browsingLocation?.path ?? "")
        }
        if let location {
            history.visit(location)
            requestDirectory(currentDirectory)
        }
    }
    func saveActiveDocument() {
        guard !editing.isClosing else { return }
        if let document = activeDocument { Task { await document.save() } }
    }
    func saveAllDocuments() {
        guard !editing.isClosing else { return }
        Task { _ = await editing.saveAll() }
    }
    func reloadActiveDocument() {
        guard let document = activeDocument, let access else { return }
        let session = sessionID
        editing.confirmClosing([document]) { [weak self] allowed in
            guard let self, allowed, self.sessionID == session else { return }
            self.editing.releaseClosingProtection()
            self.editing.remove(document.path)
            self.editing.open(path: document.path, access: access) { [weak self] in
                guard let self, self.sessionID == session,
                    let tab = self.tabs.tabs.first(where: { $0.location.path == document.path })
                else { return }
                self.tabs.pin(tab.id)
            }
        }
    }
    func prepareToCloseWindow(completion: @escaping (Bool) -> Void) {
        projectIntent = UUID()
        editing.confirmClosing(Array(editing.documents.values)) { [weak self] allowed in
            if allowed, let self {
                self.editing.reset()
                await self.stopProjectTools()
                self.tabs = BrowserTabs()
                self.history = NavigationHistory()
                self.browsingLocation = self.rootURL == nil ? nil : .directory("")
            }
            completion(allowed)
        }
    }
    func goBack() {
        guard !editing.isClosing else { return }
        if let destination = history.back() { navigate(destination, preview: true, recordHistory: false) }
    }
    func showProblems(_ category: ProblemCategory? = nil) {
        problems.category = category
        if !docking.isVisible(.problems) { docking.toggle(.problems) }
    }
    func navigateSemantic(_ target: LSPLocation) {
        guard let rootURL, let url = URL(string: target.uri), url.isFileURL, url.host == nil || url.host == "localhost"
        else { return }
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(rootURL.path + "/") ? String(path.dropFirst(rootURL.path.count + 1)) : path
        let entry = WorkspaceEntry(name: url.lastPathComponent, relativePath: relative, kind: .file)
        navigate(.file(entry), preview: false)
        editing.documents[relative]?.reveal(target.range)
    }
    func goForward() {
        guard !editing.isClosing else { return }
        if let destination = history.forward() { navigate(destination, preview: true, recordHistory: false) }
    }
    func goToParent() {
        guard let parent = location?.parentDirectory else { return }
        navigate(.directory(parent), preview: true)
    }
    func openSelected() { if let selectedEntry { open(selectedEntry, preview: false) } }

    func collapseDirectories() {
        treeCollapseRevision += 1
        treeRevision += 1
    }

    func requestDirectory(_ path: String, force: Bool = false) {
        guard let access else { return }
        if !force, snapshots[path] != nil || requests[path] != nil || errors[path] != nil { return }
        requests[path]?.cancel()
        let requestID = UUID()
        let session = sessionID
        let hidden = includeHidden
        let reader = NativeDirectoryReader(rootPath: access.url.path)
        requestIDs[path] = requestID
        errors[path] = nil
        loadingPaths.insert(path)
        markDirectoryChanged(path)
        requests[path] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let snapshot = try await reader.list(relativePath: path, includeHidden: hidden)
                let widths = try await ProjectTreeText.nameWidths(for: snapshot.entries)
                guard let self, self.sessionID == session, self.requestIDs[path] == requestID, !Task.isCancelled else {
                    return
                }
                self.treeNameWidths[path] = widths
                self.snapshots[path] = snapshot
                self.tabs.updateFileMetadata(from: snapshot.entries)
                if let selected = self.selectedEntry,
                    let updated = snapshot.entries.first(where: { $0.relativePath == selected.relativePath })
                {
                    self.selectedEntry = updated
                }
                self.completeRequest(path)
            } catch {
                guard let self, self.sessionID == session, self.requestIDs[path] == requestID else { return }
                self.errors[path] = error is CancellationError ? "目录读取已取消" : error.localizedDescription
                self.completeRequest(path)
            }
        }
    }

    func refresh() {
        guard rootURL != nil else { return }
        for request in requests.values { request.cancel() }
        requests.removeAll()
        requestIDs.removeAll()
        loadingPaths.removeAll()
        snapshots.removeAll()
        treeNameWidths.removeAll()
        errors.removeAll()
        selectedEntry = nil
        treeResetRevision += 1
        directoryRevisions.removeAll()
        treeRevision += 1
        requestDirectory("")
        if !currentDirectory.isEmpty { requestDirectory(currentDirectory) }
    }

    func cancelReading() {
        for (path, request) in requests {
            request.cancel()
            errors[path] = "目录读取已取消"
            markDirectoryChanged(path)
        }
        requests.removeAll()
        requestIDs.removeAll()
        loadingPaths.removeAll()
        treeRevision += 1
    }

    private func completeRequest(_ path: String) {
        requests[path] = nil
        requestIDs[path] = nil
        loadingPaths.remove(path)
        markDirectoryChanged(path)
    }
    private func markDirectoryChanged(_ path: String) {
        treeRevision += 1
        directoryRevisions[path] = treeRevision
    }
}
