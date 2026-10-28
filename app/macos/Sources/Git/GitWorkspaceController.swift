import AppKit
import CryptoKit
import Foundation
import HyCodeWorkspace
import Observation

enum GitToolDialog: String, Identifiable {
    case branch, settings, push
    var id: String { rawValue }
}

@MainActor @Observable final class GitReviewState {
    let location: GitDiffLocation
    var diff: GitDiff?
    var savedDiff: GitDiff?
    var loading = false
    var error: String?
    var ticket = UUID()
    var paths: [String] = []
    var fileIndex: Int { paths.firstIndex(of: location.path) ?? 0 }
    var document: EditorDocument?
    var bufferRevision: UInt64?
    var bufferTicket = UUID()
    var bufferLoading = false
    var bufferError: String?
    var readonlyReason: String?
    var bufferReview = GitBufferReview()
    var permitsSelection: Bool {
        guard let document else { return true }
        return bufferReview.canSelect(document: document.id, revision: document.edits.revision, dirty: document.isDirty)
    }
    var reviewedSelection: GitSelection? { permitsSelection ? (document == nil ? diff : savedDiff)?.selection : nil }
    init(_ location: GitDiffLocation) { self.location = location }
}

struct GitConsoleEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let title: String
    let detail: String
    let failed: Bool
}

@MainActor @Observable final class GitWorkspaceController {
    private(set) var snapshot: GitStatusSnapshot?
    private(set) var references: [GitReference] = []
    private(set) var remotes: [GitRemote] = []
    private(set) var commits: [GitCommit] = []
    private(set) var graph: [GitGraphRow] = []
    private(set) var graphColumns = 2
    private(set) var commitFiles: [GitCommitFile] = []
    private(set) var selectedCommit: GitCommit?
    private(set) var selections: [String: GitSelection] = [:]
    private(set) var selecting: Set<String> = []
    private var blockChoices: [String: (ids: Set<Int>, total: Int)] = [:]
    private(set) var loading = false
    private(set) var historyLoading = false
    private(set) var detailsLoading = false
    private(set) var writing = false
    private(set) var ready = false
    private(set) var notRepository = false
    private(set) var needsGitAccess = false
    private(set) var operation = ""
    private(set) var console: [GitConsoleEntry] = []
    private(set) var lastFetch: Date?
    var message = "" {
        didSet {
            if message != oldValue { messageRevision &+= 1 }
            persistDraft()
        }
    }
    var messageComposing = false
    var amend = false
    var stagedMode = false
    var fileFilter = ""
    var directoryGrouping = false {
        didSet { if oldValue != directoryGrouping, let activeReview { loadDiff(activeReview) } }
    }
    private(set) var selectedChange: GitDiffLocation?
    var selectedChangeID: String? {
        selectedChange.map { ($0.comparison == .staged ? "index\0" : "work\0") + $0.path }
    }
    var query = GitHistoryQuery()
    var selectedRemote = ""
    var pushTarget = ""
    var pushPreview: GitPushPlan?
    var pushPreviewLoading = false
    var dialog: GitToolDialog?
    var error: String?
    private(set) var statusError: String?
    private(set) var remoteIssue: String?
    var notice: String?
    var showingConsole = false
    var selectedParent: String?
    var comparisonLeft: GitCommit?
    private(set) var objectComparison: GitComparison?
    @ObservationIgnored private var repository: GitRepository?
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var historyID = UUID()
    @ObservationIgnored private var detailsID = UUID()
    @ObservationIgnored private var nextOffset: Int?
    @ObservationIgnored private var tips: [String] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: GitRepositoryWatcher?
    @ObservationIgnored private var metadataWatcher: GitRepositoryWatcher?
    @ObservationIgnored private var gitAccess: [WorkspaceAccess] = []
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var reviews: [GitDiffLocation: GitReviewState] = [:]
    @ObservationIgnored private var activeReview: GitDiffLocation?
    @ObservationIgnored private var suppressFollowup = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var amendRequests = GitAmendRequests()
    @ObservationIgnored private var messageRevision: UInt64 = 0
    @ObservationIgnored private var selectionRequests = GitSelectionRequests()
    @ObservationIgnored private var draftKey: String?
    @ObservationIgnored private var beforeAmend = ""
    @ObservationIgnored var executionAllowed: () -> Bool = { false }
    @ObservationIgnored var prepareWrite: (UUID, Set<String>?) async -> Bool = { _, _ in false }
    @ObservationIgnored var finishWrite: (UUID, Bool) -> Void = { _, _ in }
    @ObservationIgnored var onDiskChanged: () -> Void = {}
    @ObservationIgnored var openDiff: (GitDiffLocation) -> Void = { _ in }
    @ObservationIgnored var openSource: (String) -> Void = { _ in }
    @ObservationIgnored var dirtyPaths: () -> Set<String> = { [] }
    @ObservationIgnored var savePaths: (Set<String>) async -> Bool = { _ in false }
    @ObservationIgnored var documentForDiff: (String) -> EditorDocument? = { _ in nil }
    @ObservationIgnored var reloadDocument: (String) -> Void = { _ in }

    var canLoadMore: Bool { nextOffset != nil && commits.count < 2000 }
    var changes: [GitStatusEntry] { snapshot?.entries ?? [] }
    var branchTitle: String { snapshot?.branchTitle ?? (loading ? "正在读取 Git…" : "Git") }
    var available: Bool { access != nil }
    var feedbackError: String? { error ?? statusError }
    var blockedBufferPaths: Set<String> {
        Set(reviews.values.filter { $0.document != nil && !$0.permitsSelection }.map { $0.location.path })
    }
    func retry() { if !stopping && !writing { configure(access: access, gitAccess: gitAccess) } }
    var selectedCount: Int { selections.count }
    var canCommit: Bool {
        ready && !writing && !loading && !messageComposing && selecting.isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (stagedMode ? changes.contains(where: \.staged) || amend : !selections.isEmpty || amend)
            && snapshot?.hasConflicts != true && snapshot?.operation == nil
            && dirtyPaths().isDisjoint(
                with: stagedMode ? Set(changes.filter(\.staged).map(\.path)) : Set(selections.keys))
    }
    func configure(access: WorkspaceAccess?, gitAccess: [WorkspaceAccess] = []) {
        persistDraft()
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        debounce?.cancel()
        watcher?.stop()
        watcher = nil
        metadataWatcher?.stop()
        metadataWatcher = nil
        self.gitAccess = gitAccess
        needsGitAccess = false
        self.access = access
        repository = nil
        snapshot = nil
        selectedChange = nil
        ready = false
        notRepository = false
        references = []
        remotes = []
        commits = []
        graph = []
        commitFiles = []
        selectedCommit = nil
        objectComparison = nil
        comparisonLeft = nil
        selections = [:]
        blockChoices = [:]
        selecting = []
        selectionRequests = GitSelectionRequests()
        reviews = [:]
        activeReview = nil
        error = nil
        statusError = nil
        remoteIssue = nil
        notice = nil
        dialog = nil
        suppressFollowup = false
        stopping = false
        amendRequests.cancel()
        messageComposing = false
        nextOffset = nil
        tips = []
        lastFetch = nil
        amend = false
        stagedMode = false
        draftKey = access.map {
            "git.message."
                + SHA256.hash(data: Data($0.url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }
                .joined()
        }
        message = draftKey.flatMap { UserDefaults.standard.string(forKey: $0) } ?? ""
        guard let access else {
            loading = false
            return
        }
        loading = true
        let ticket = generation
        tasks["configure"] = Task { [weak self, access] in
            do {
                let repository = try await GitRepository.open(
                    root: access.url, authorizedDirectories: gitAccess.map(\.url))
                guard let self, self.generation == ticket, !Task.isCancelled else { return }
                self.repository = repository
                self.loading = false
                self.ready = repository != nil
                self.notRepository = repository == nil
                if let repository {
                    let watcher = try? await Task.detached(priority: .utility) { [weak self] in
                        try GitRepositoryWatcher(root: repository.identity.root) { [weak self] paths, rescan in
                            Task { @MainActor in self?.changed(paths, rescan: rescan, generation: ticket) }
                        }
                    }.value
                    guard self.generation == ticket, !Task.isCancelled else {
                        watcher?.stop()
                        return
                    }
                    self.watcher = watcher
                    if !repository.identity.commonDirectory.path.hasPrefix(repository.identity.root.path + "/") {
                        let metadata = try? await Task.detached(priority: .utility) { [weak self] in
                            try GitRepositoryWatcher(root: repository.identity.commonDirectory) { [weak self] _, _ in
                                Task { @MainActor in self?.changed([], rescan: true, generation: ticket) }
                            }
                        }.value
                        guard self.generation == ticket, !Task.isCancelled else {
                            metadata?.stop()
                            return
                        }
                        self.metadataWatcher = metadata
                    }
                    if watcher == nil { self.notice = "Git 文件监听不可用，请手动刷新" }
                    self.refresh()
                }
            } catch {
                guard let self, self.generation == ticket else { return }
                self.loading = false
                self.error = error.localizedDescription
                self.needsGitAccess = (error as? GitFailure)?.code == .authorization
            }
        }
    }
    func authorizeGitDirectory() {
        guard !stopping, needsGitAccess, let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.title = "授权 Git 公共管理目录"
        panel.prompt = "授权"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        let session = generation
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.generation == session, !self.stopping else {
                return
            }
            let grant = WorkspaceAccess(url: url)
            self.configure(access: self.access, gitAccess: self.gitAccess + [grant])
        }
    }
    private func persistDraft() {
        if let draftKey, message.utf8.count <= 65_536 { UserDefaults.standard.set(message, forKey: draftKey) }
    }
    private func changed(_ paths: [String], rescan: Bool, generation: UUID) {
        guard self.generation == generation, !stopping else { return }
        let all = rescan || paths.contains { $0 == ".git" || $0.hasPrefix(".git/") }
        if all { selections = [:] } else { for path in paths { selections[path] = nil } }
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, !self.writing else { return }
            self.refresh()
        }
    }
    func refresh() {
        guard !stopping, !writing, let repository else { return }
        tasks["refresh"]?.cancel()
        let session = generation
        let ticket = UUID()
        refreshID = ticket
        loading = true
        tasks["refresh"] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let snapshot = try await repository.status()
                let references = try await repository.references()
                let remotes: [GitRemote]
                let remoteIssue: String?
                do {
                    remotes = try await repository.remotes()
                    remoteIssue = nil
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    remotes = []
                    remoteIssue = "远端配置暂不可用：" + error.localizedDescription
                }
                guard let self, self.generation == session, self.refreshID == ticket, !Task.isCancelled else { return }
                if self.snapshot?.head != snapshot.head || self.snapshot?.indexDigest != snapshot.indexDigest {
                    self.selections = [:]
                }
                let valid = Set(snapshot.entries.map(\.path))
                self.selections = self.selections.filter { valid.contains($0.key) }
                self.snapshot = snapshot
                self.references = references
                self.remotes = remotes
                self.remoteIssue = remoteIssue
                if !self.remotes.contains(where: { $0.name == self.selectedRemote }) {
                    self.selectedRemote = self.remotes.first?.name ?? ""
                }
                self.loading = false
                // Refreshing actual state must not erase a failed write's
                // explanation before the user can read it.
                self.statusError = nil
                self.loadHistory()
                if let location = self.activeReview {
                    switch location.comparison {
                    case .working, .staged, .unstaged: self.loadDiff(location)
                    default: break
                    }
                }
            } catch {
                guard let self, self.generation == session, self.refreshID == ticket else { return }
                self.loading = false
                if !(error is CancellationError) { self.statusError = error.localizedDescription }
            }
        }
    }
    func choose(_ entry: GitStatusEntry, selected: Bool) {
        blockChoices[entry.path] = nil
        guard !stopping, !writing, let repository, let snapshot else { return }
        tasks["select:" + entry.path]?.cancel()
        selectionRequests.cancel([entry.path])
        selecting = selectionRequests.pending
        if !selected {
            selections[entry.path] = nil
            return
        }
        if dirtyPaths().contains(entry.path) {
            error = "文件正文尚未保存或未完成当前版本审查，请保存或重新载入后选择"
            return
        }
        if entry.staged && entry.unstaged {
            error = "此文件同时有暂存与未暂存内容，请切换暂存区视图明确提交来源"
            return
        }
        if let activeReview, activeReview.path == entry.path, let bound = reviews[activeReview]?.reviewedSelection {
            selections[entry.path] = bound
            return
        }
        let request = selectionRequests.begin([entry.path])
        selecting = selectionRequests.pending
        let session = generation
        tasks["select:" + entry.path] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let value = try await repository.captureSelection(entry.path, snapshot: snapshot)
                guard let self, self.generation == session, !Task.isCancelled,
                    self.selectionRequests.accepts(request, path: entry.path)
                else { return }
                self.selectionRequests.finish(request)
                self.selecting = self.selectionRequests.pending
                self.selections[entry.path] = value
            } catch {
                guard let self, self.generation == session else { return }
                self.selectionRequests.finish(request)
                self.selecting = self.selectionRequests.pending
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func selectionState(_ path: String) -> NSControl.StateValue {
        if selecting.contains(path), let pending = blockChoices[path] {
            return pending.ids.isEmpty ? .off : pending.ids.count == pending.total ? .on : .mixed
        }
        guard let selection = selections[path] else { return .off }
        return selection.partial == nil ? .on : .mixed
    }
    func blockIsSelected(_ state: GitReviewState, id: Int) -> Bool {
        if selecting.contains(state.location.path), let pending = blockChoices[state.location.path] {
            return pending.ids.contains(id)
        }
        guard let selected = selections[state.location.path] else { return false }
        return selected.partial?.blocks.contains(id) ?? true
    }
    func chooseBlock(_ state: GitReviewState, id: Int, selected: Bool, reviewID: UUID?, savedID: UUID?, ticket: UUID) {
        let path = state.location.path
        guard !stopping, !writing, !stagedMode, !selecting.contains(path), state.location.comparison == .working,
            state.ticket == ticket, state.diff?.id == reviewID, state.savedDiff?.id == savedID,
            activeReview == state.location, reviews[state.location] === state, !state.loading,
            state.permitsSelection, let repository, let snapshot, let diff = state.savedDiff,
            let text = diff.text, let candidate = diff.selection, !candidate.bothLayersChanged
        else { return }
        let all = Set(text.blocks.map(\.id))
        guard all.contains(id) else { return }
        var ids = selections[path].map { $0.partial?.blocks ?? all } ?? []
        if selected { ids.insert(id) } else { ids.remove(id) }
        tasks["select:" + path]?.cancel()
        selectionRequests.cancel([path])
        if ids.isEmpty {
            selections[path] = nil
            blockChoices[path] = nil
            selecting = selectionRequests.pending
            return
        }
        let remaining: Int
        do {
            remaining =
                GitPartialSelection.retainedByteLimit
                - (try GitPartialSelection.retainedBytes(selections.values.filter { $0.path != path }))
        } catch {
            self.error = error.localizedDescription
            return
        }
        let request = selectionRequests.begin([path])
        blockChoices[path] = (ids, all.count)
        selecting = selectionRequests.pending
        let session = generation
        tasks["select:" + path] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            defer {
                if let self, self.generation == session, self.selectionRequests.accepts(request, path: path) {
                    self.blockChoices[path] = nil
                    self.selectionRequests.finish(request)
                    self.selecting = self.selectionRequests.pending
                }
            }
            do {
                let value = try await repository.capturePartialSelection(
                    diff, blocks: ids, snapshot: snapshot, maximumBytes: remaining)
                guard let self, !self.stopping, self.generation == session, !Task.isCancelled,
                    self.selectionRequests.accepts(request, path: path), !self.dirtyPaths().contains(path)
                else { return }
                _ = try GitPartialSelection.retainedBytes(self.selections.values.filter { $0.path != path } + [value])
                self.selections[path] = value
            } catch {
                guard let self, self.generation == session, self.selectionRequests.accepts(request, path: path) else {
                    return
                }
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func restoreBlock(_ state: GitReviewState, id: Int, reviewID: UUID?, ticket: UUID) {
        guard !stopping, !writing, activeReview == state.location, reviews[state.location] === state,
            state.ticket == ticket, state.diff?.id == reviewID, !state.loading, !state.bufferLoading,
            let document = state.document, !document.composing, !document.closing,
            state.bufferRevision == document.edits.revision, let diff = state.diff, let comparison = diff.text,
            document.editor?.textView.isEditable == true
        else { return }
        let session = generation
        let revision = document.edits.revision
        let key = "restore-block:" + state.location.key
        tasks[key]?.cancel()
        tasks[key] = Task { [weak self, weak state, weak document] in
            do {
                let plan = try await Task.detached(priority: .utility) {
                    try GitBlockEdit.restoring(id, in: comparison)
                }.value
                guard let self, !self.stopping, self.generation == session, !Task.isCancelled,
                    let state, self.activeReview == state.location, state.diff?.id == diff.id,
                    let document, state.document === document, document.edits.revision == revision
                else { return }
                if document.editor?.restoreComparison(plan, revision: revision) != true {
                    state.bufferError = "正文已变化或暂不能编辑，未还原；请等待差异更新"
                }
            } catch {
                guard let self, self.generation == session, !Task.isCancelled else { return }
                state?.bufferError = error.localizedDescription
            }
        }
    }
    func selectVisible(_ entries: [GitStatusEntry], selected: Bool) {
        guard !stopping else { return }
        tasks["select-batch"]?.cancel()
        if !selected {
            for entry in entries { choose(entry, selected: false) }
            return
        }
        let dirty = dirtyPaths()
        let entries = entries.filter {
            !$0.conflicted && !$0.submodule && !($0.staged && $0.unstaged) && !dirty.contains($0.path)
        }
        guard let repository, let snapshot, !writing else { return }
        let paths = entries.map(\.path)
        for path in paths { blockChoices[path] = nil }
        let session = generation
        let request = selectionRequests.begin(paths)
        selecting = selectionRequests.pending
        tasks["select-batch"] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let values = try await repository.captureSelections(paths, snapshot: snapshot)
                guard let self, self.generation == session, !Task.isCancelled else { return }
                let dirty = self.dirtyPaths()
                for value in values
                where !dirty.contains(value.path) && self.selectionRequests.accepts(request, path: value.path) {
                    let bound = self.activeReview.flatMap {
                        $0.path == value.path ? self.reviews[$0]?.reviewedSelection : nil
                    }
                    self.selections[value.path] = bound ?? value
                }
                self.selectionRequests.finish(request)
                self.selecting = self.selectionRequests.pending
            } catch {
                guard let self, self.generation == session else { return }
                self.selectionRequests.finish(request)
                self.selecting = self.selectionRequests.pending
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func bufferChanged(_ path: String) {
        blockChoices[path] = nil
        for state in reviews.values where state.location.path == path && state.document != nil {
            state.bufferRevision = nil
            state.bufferReview.invalidate()
        }
        selections[path] = nil
        selectionRequests.cancel([path])
        selecting = selectionRequests.pending
        tasks["select:" + path]?.cancel()
        tasks["select-batch"]?.cancel()
    }
    func show(_ entry: GitStatusEntry, comparison: GitComparison? = nil) {
        guard let repository else { return }
        let value = comparison ?? (stagedMode && entry.staged ? .staged : .working)
        let location = GitDiffLocation(repositoryID: repository.identity.id, path: entry.path, comparison: value)
        openDiff(location)
    }
    func review(_ location: GitDiffLocation) -> GitReviewState {
        if let value = reviews[location] { return value }
        let value = GitReviewState(location)
        reviews[location] = value
        return value
    }
    func releaseDiff(_ location: GitDiffLocation) {
        if activeReview == location { activeReview = nil }
        tasks["diff:" + location.key]?.cancel()
        for (key, task) in tasks where key.hasPrefix("buffer:" + location.key + "\0") { task.cancel() }
        reviews[location] = nil
    }
    func pruneReviews(keeping locations: Set<GitDiffLocation>) {
        for location in Array(reviews.keys) where !locations.contains(location) { releaseDiff(location) }
    }
    func loadDiff(_ location: GitDiffLocation) {
        guard !stopping, let repository, location.repositoryID == repository.identity.id else { return }
        selectedChange =
            location.comparison == .working || location.comparison == .unstaged || location.comparison == .staged
            ? location : nil
        activeReview = location
        for (key, task) in tasks
        where (key.hasPrefix("diff:") || key.hasPrefix("buffer:")) && key != "diff:" + location.key { task.cancel() }
        // Retain only the active bounded diff projection. Open tabs retain their
        // identity, not one full patch and two text projections per file.
        for (key, value) in reviews where key != location {
            value.diff = nil
            value.savedDiff = nil
            value.loading = false
            value.document = nil
            value.bufferTicket = UUID()
            value.bufferLoading = false
        }
        let state = review(location)
        let ticket = UUID()
        let session = generation
        state.ticket = ticket
        state.loading = true
        state.error = nil
        state.bufferRevision = nil
        state.bufferReview.invalidate()
        state.bufferError = nil
        state.readonlyReason = nil
        tasks["diff:" + location.key]?.cancel()
        let snapshot = self.snapshot
        let grouping = directoryGrouping && !stagedMode
        tasks["diff:" + location.key] = Task { [weak self, weak state, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let diff = try await repository.diff(
                    path: location.path, comparison: location.comparison, snapshot: snapshot)
                let paths: [String]
                switch location.comparison {
                case .commit(let object, let parent):
                    paths = try await repository.files(in: object, parent: parent).map(\.path)
                case .objects(let left, let right):
                    paths = try await repository.files(in: right, parent: left).map(\.path)
                case .working, .staged, .unstaged:
                    paths = await Task.detached(priority: .utility) {
                        let entries = snapshot?.entries ?? []
                        switch location.comparison {
                        case .staged: return GitChangeListRow.ordered(entries.filter(\.staged)).map(\.path)
                        case .unstaged: return GitChangeListRow.ordered(entries.filter(\.unstaged)).map(\.path)
                        default: return GitChangeListRow.reviewPaths(entries, path: location.path, grouping: grouping)
                        }
                    }.value
                }
                guard let self, self.generation == session, let state, state.ticket == ticket, !Task.isCancelled else {
                    return
                }
                if let chosen = self.selections[location.path], chosen.partial != nil,
                    diff.selection.map({ chosen.sameRevision(as: $0) }) != true
                {
                    self.selections[location.path] = nil
                    self.blockChoices[location.path] = nil
                    self.selectionRequests.cancel([location.path])
                    self.selecting = self.selectionRequests.pending
                    self.tasks["select:" + location.path]?.cancel()
                }
                state.diff = diff
                state.savedDiff = diff
                if diff.editableWorkingText {
                    state.document = self.documentForDiff(location.path)
                } else {
                    state.document = nil
                }
                state.paths = paths
                state.loading = false
            } catch {
                guard let self, self.generation == session, let state, state.ticket == ticket else { return }
                state.loading = false
                if !(error is CancellationError) { state.error = error.localizedDescription }
            }
        }
    }
    func previewBuffer(_ state: GitReviewState) {
        let prefix = "buffer:" + state.location.key + "\0"
        for (key, task) in tasks where key.hasPrefix(prefix) { task.cancel() }
        let bufferTicket = UUID()
        let key = prefix + bufferTicket.uuidString
        state.bufferTicket = bufferTicket
        state.bufferLoading = false
        if state.document?.largeFile != nil {
            state.document = nil
            state.bufferRevision = nil
            state.bufferReview.invalidate()
            state.readonlyReason = "已打开的文档使用分段编辑；此处显示已保存版本，可打开源文件继续编辑"
            return
        }
        guard !stopping, !state.loading, let repository, let document = state.document, !document.loading,
            !document.composing, document.largeFile == nil, let base = state.savedDiff, let saved = base.text
        else { return }
        let session = generation
        let ticket = state.ticket
        let revision = document.edits.revision
        let reviewRequest = state.bufferReview.begin(document: document.id, revision: revision)
        state.bufferLoading = true
        state.bufferError = nil
        tasks[key] = Task { [weak self, weak state, access] in
            defer { withExtendedLifetime(access) {} }
            guard let self else { return }
            // Distinct keys keep cancelled predecessors owned until they have
            // reaped their process. stop() drains all unfinished generations.
            defer { self.tasks[key] = nil }
            guard let state else { return }
            defer {
                if self.generation == session && state.ticket == ticket && state.bufferTicket == bufferTicket {
                    state.bufferLoading = false
                }
            }
            @MainActor func current() -> Bool {
                !Task.isCancelled && !self.stopping && self.generation == session && state.ticket == ticket
                    && state.bufferTicket == bufferTicket && self.activeReview == state.location
                    && state.document === document && document.edits.revision == revision && !document.composing
                    && state.bufferReview.accepts(reviewRequest)
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard current() else { return }
                let snapshot = try await document.textSnapshot(revision: revision)
                guard current() else { return }
                let result = try await repository.preview(base, buffer: snapshot)
                guard current() else { return }
                state.diff = result
                state.bufferRevision = revision
                state.bufferReview.accept(
                    reviewRequest, buffer: snapshot, saved: saved.right.text, dirty: document.isDirty)
            } catch {
                guard current() else { return }
                if !(error is CancellationError) { state.bufferError = "编辑内容保留；差异更新暂不可用：" + error.localizedDescription }
            }
        }
    }
    func suspendDiff() {
        activeReview = nil
        for (key, task) in tasks where key.hasPrefix("diff:") || key.hasPrefix("buffer:") { task.cancel() }
        for state in reviews.values {
            state.diff = nil
            state.savedDiff = nil
            state.loading = false
            state.document = nil
            state.bufferLoading = false
        }
    }
    func adjacent(_ location: GitDiffLocation, direction: Int) {
        let state = review(location)
        guard let index = state.paths.firstIndex(of: location.path), state.paths.indices.contains(index + direction)
        else { return }
        openDiff(
            GitDiffLocation(
                repositoryID: location.repositoryID, path: state.paths[index + direction],
                comparison: location.comparison))
    }
    func loadHistory(more: Bool = false) {
        guard !stopping, let repository, !writing, !more || canLoadMore else { return }
        tasks["history"]?.cancel()
        let ticket = UUID()
        historyID = ticket
        let session = generation
        let query = self.query
        let offset = more ? nextOffset ?? 0 : 0
        let tips = more ? self.tips : []
        historyLoading = true
        tasks["history"] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let page = try await repository.history(query, tips: tips, offset: offset)
                guard let self, self.generation == session, self.historyID == ticket, !Task.isCancelled else { return }
                let values = more ? self.commits + page.commits : page.commits
                let graph = await Task.detached(priority: .utility) { GitGraphRow.layout(values) }.value
                guard self.generation == session, self.historyID == ticket, !Task.isCancelled else { return }
                self.commits = values
                self.graph = graph
                self.graphColumns = max(2, graph.map(\.columns).max() ?? 2)
                self.tips = page.tips
                self.nextOffset = page.nextOffset
                self.historyLoading = false
            } catch {
                guard let self, self.generation == session, self.historyID == ticket else { return }
                self.historyLoading = false
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func selectCommit(_ commit: GitCommit) {
        selectedCommit = commit
        objectComparison = nil
        selectedParent = commit.parents.first
        loadCommitFiles()
    }
    func loadCommitFiles() {
        guard !stopping, let repository, let selectedCommit else { return }
        let parent = selectedParent
        let comparison = objectComparison
        let session = generation
        let ticket = UUID()
        detailsID = ticket
        tasks["details"]?.cancel()
        detailsLoading = true
        commitFiles = []
        tasks["details"] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let files: [GitCommitFile]
                if case .objects(let left, let right)? = comparison {
                    files = try await repository.files(in: right, parent: left)
                } else {
                    files = try await repository.files(in: selectedCommit.object, parent: parent)
                }
                guard let self, self.generation == session, self.detailsID == ticket, !Task.isCancelled else { return }
                self.commitFiles = files
                self.detailsLoading = false
            } catch {
                guard let self, self.generation == session, self.detailsID == ticket else { return }
                self.detailsLoading = false
                self.error = error.localizedDescription
            }
        }
    }
    func showHistoryFile(_ file: GitCommitFile) {
        guard let repository, let selectedCommit else { return }
        openDiff(
            GitDiffLocation(
                repositoryID: repository.identity.id, path: file.path,
                comparison: objectComparison ?? .commit(selectedCommit.object, parent: selectedParent)))
    }
    func compare(_ left: GitCommit, _ right: GitCommit) {
        selectedCommit = right
        selectedParent = nil
        objectComparison = .objects(left: left.object, right: right.object)
        loadCommitFiles()
    }
    func compareToHead(_ object: String) {
        guard !stopping, let repository, let head = snapshot?.head else { return }
        let session = generation
        tasks["compare"]?.cancel()
        tasks["compare"] = Task { [weak self] in
            do {
                let left = try await repository.commit(object)
                let right = try await repository.commit(head)
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.compare(left, right)
            } catch {
                if let self, self.generation == session, !(error is CancellationError) {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func locateHash() {
        guard !stopping, let repository else { return }
        let text = query.text
        let session = generation
        tasks["locate"]?.cancel()
        tasks["locate"] = Task { [weak self] in
            do {
                let commit = try await repository.findCommit(text)
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.query = GitHistoryQuery()
                self.query.reference = commit.object
                self.selectCommit(commit)
                self.loadHistory()
            } catch {
                if let self, self.generation == session, !(error is CancellationError) {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func setAmend(_ value: Bool) {
        guard !stopping, amend != value, !writing else { return }
        tasks["amend"]?.cancel()
        amendRequests.cancel()
        amend = value
        if !value {
            message = beforeAmend
            return
        }
        beforeAmend = message
        guard let repository, let head = snapshot?.head else {
            amend = false
            return
        }
        let request = amendRequests.begin(head: head, messageRevision: messageRevision)
        let session = generation
        tasks["amend"] = Task { [weak self] in
            do {
                let commit = try await repository.commit(head)
                guard let self, self.generation == session, self.amend,
                    self.amendRequests.accepts(
                        request, head: self.snapshot?.head, messageRevision: self.messageRevision), !Task.isCancelled
                else { return }
                self.message = commit.message
            } catch {
                if let self, self.generation == session, !(error is CancellationError) {
                    self.error = error.localizedDescription
                }
            }
        }
    }
    func saveAndRefresh(_ paths: Set<String>) {
        guard !stopping else { return }
        let session = generation
        tasks["save-files"] = Task { [weak self] in
            guard let self, self.generation == session, !self.stopping else { return }
            let saved = await self.savePaths(paths)
            guard self.generation == session, !self.stopping else { return }
            if saved {
                for path in paths { self.selections[path] = nil }
                self.refresh()
            } else {
                self.error = "保存未完成，原输入已保留；请处理文档错误后重新审查"
            }
        }
    }
    func commit(push: Bool) {
        guard canCommit, let snapshot else { return }
        let selections = Array(self.selections.values)
        let staged = stagedMode
        let message = self.message
        let amend = self.amend
        let paths = Set(staged ? changes.filter(\.staged).flatMap(\.paths) : selections.flatMap(\.paths))
        runWrite("提交", paths: paths, reload: false) { repository in
            try await repository.createCommit(
                selections: selections, staged: staged, message: message, amend: amend, snapshot: snapshot)
        } success: { [weak self] in
            guard let self else { return }
            self.message = ""
            self.amend = false
            self.selections = [:]
            if push { self.requestPush() }
        }
    }
    func captureForAction(
        _ entry: GitStatusEntry, completion: @escaping @MainActor (GitSelection, GitStatusSnapshot) -> Void
    ) {
        guard !stopping, !writing, let snapshot, let repository else { return }
        guard !dirtyPaths().contains(entry.path) else {
            error = "文件正文尚未保存或与磁盘版本不同，请保存或重新载入后审查"
            return
        }
        let session = generation
        let bound = activeReview.flatMap { $0.path == entry.path ? reviews[$0]?.reviewedSelection : nil }
        tasks["prepare-action"]?.cancel()
        tasks["prepare-action"] = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            do {
                let selection: GitSelection
                if let bound {
                    selection = bound
                } else {
                    selection = try await repository.captureSelection(entry.path, snapshot: snapshot)
                }
                guard let self, self.generation == session, !self.stopping, !Task.isCancelled else { return }
                completion(selection, snapshot)
            } catch {
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func fileAction(_ action: GitFileAction, entry: GitStatusEntry) {
        captureForAction(entry) { [weak self] selection, snapshot in
            self?.fileAction(action, selection: selection, snapshot: snapshot)
        }
    }
    func fileAction(_ action: GitFileAction, selection: GitSelection, snapshot: GitStatusSnapshot) {
        let reload = action == .discardUnstaged || action == .restoreHead
        runWrite("文件操作 · " + selection.path, paths: Set(selection.paths), reload: reload) { repository in
            try await repository.fileAction(action, selections: [selection], snapshot: snapshot)
        }
    }
    func switchBranch(_ reference: GitReference) {
        guard let snapshot else { return }
        runWrite("切换分支", paths: nil, reload: true) { try await $0.switchBranch(reference, snapshot: snapshot) }
    }
    func createBranch(_ name: String) {
        guard let snapshot, let head = snapshot.head else {
            error = "请先创建初始提交"
            return
        }
        runWrite("创建并切换分支", paths: nil, reload: true) {
            try await $0.createBranch(name: name, start: head, switchTo: true, snapshot: snapshot)
        } success: { [weak self] in
            self?.dialog = nil
        }
    }
    func deleteBranch(_ reference: GitReference) {
        guard let snapshot else { return }
        runWrite("安全删除分支", paths: [], reload: false) { try await $0.deleteBranch(reference, snapshot: snapshot) }
    }
    func fetch() {
        guard let remote = remotes.first(where: { $0.name == selectedRemote }) else {
            dialog = .settings
            return
        }
        runWrite("获取 \(remote.name)", paths: [], reload: false) {
            try await $0.fetch(remote: remote)
        } success: { [weak self] in
            self?.lastFetch = Date()
        }
    }
    func pull() {
        guard let snapshot, let remote = remotes.first(where: { $0.name == selectedRemote }) else {
            dialog = .settings
            return
        }
        runWrite("仅快进拉取", paths: nil, reload: true) { try await $0.pullFastForward(remote: remote, snapshot: snapshot) }
    }
    func requestPush() {
        guard !stopping, ready, !writing else { return }
        guard !remotes.isEmpty else {
            dialog = .settings
            notice = "本地提交保留；请先配置推送远端"
            return
        }
        pushTarget =
            snapshot?.upstream.flatMap { value -> String? in
                let prefix = selectedRemote + "/"
                return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : nil
            } ?? snapshot?.branch ?? ""
        dialog = .push
        updatePushPreview()
    }
    func updatePushPreview() {
        guard !stopping, let repository, let remote = remotes.first(where: { $0.name == selectedRemote }) else {
            return
        }
        tasks["push-preview"]?.cancel()
        pushPreview = nil
        pushPreviewLoading = true
        let target = pushTarget
        let session = generation
        tasks["push-preview"] = Task { [weak self] in
            do {
                let current = try await repository.status()
                let plan = try await repository.pushPlan(remote: remote, target: target, snapshot: current)
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.pushPreview = plan
                self.pushPreviewLoading = false
            } catch {
                guard let self, self.generation == session, !Task.isCancelled else { return }
                self.pushPreviewLoading = false
                self.error = error.localizedDescription
            }
        }
    }
    func push() {
        guard let plan = pushPreview, let remote = remotes.first(where: { $0.name == plan.remote }) else { return }
        runWrite("推送到 \(plan.remote)/\(plan.targetBranch)", paths: [], reload: false) {
            try await $0.push(plan, remote: remote)
        } success: { [weak self] in
            self?.dialog = nil
        }
    }
    func setIdentity(name: String, email: String) {
        runWrite("设置仓库身份", paths: [], reload: false) { try await $0.setIdentity(name: name, email: email) }
    }
    func setRemote(name: String, url: String) {
        let replacing = remotes.contains { $0.name == name }
        runWrite("保存远端", paths: [], reload: false) {
            try await $0.setRemote(name: name, url: url, replacing: replacing)
        }
    }
    func removeRemote(_ name: String) {
        runWrite("删除远端", paths: [], reload: false) { try await $0.removeRemote(name) }
    }
    func runWrite(
        _ title: String, paths: Set<String>?, reload: Bool,
        action: @escaping @Sendable (GitRepository) async throws -> GitWriteResult,
        success: @escaping @MainActor () -> Void = {}
    ) {
        guard !stopping, !writing, ready, executionAllowed(), let repository else {
            error = "请先结束存活终端会话，或等待 Codex、项目工具及当前 Git 操作完成后重试"
            return
        }
        writing = true
        operation = title
        error = nil
        notice = nil
        suppressFollowup = false
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        selecting = []
        selectionRequests = GitSelectionRequests()
        blockChoices = [:]
        loading = false
        historyLoading = false
        detailsLoading = false
        let session = generation
        let id = UUID()
        writeTask = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            guard let self else { return }
            let prepared = await self.prepareWrite(id, paths)
            guard prepared else {
                self.writing = false
                self.operation = ""
                self.writeTask = nil
                self.error = "受影响文档尚未保存、正在组合输入或有其他修改任务；请处理后重试"
                return
            }
            var succeeded = false
            do {
                let result = try await action(repository)
                self.record(title, detail: result.summary + "\n" + result.detail, failed: false)
                if self.generation == session {
                    self.notice = result.summary + (result.commit.map { " · " + $0.prefix(8) } ?? "")
                    succeeded = true
                }
            } catch {
                let text = error is CancellationError ? "已请求停止；请刷新核对仓库实际状态" : error.localizedDescription
                self.record(title, detail: text, failed: true)
                if self.generation == session { self.error = text }
            }
            self.finishWrite(id, reload)
            guard self.generation == session else { return }
            self.writing = false
            self.operation = ""
            self.writeTask = nil
            if reload && !self.stopping { self.onDiskChanged() }
            if !self.stopping { self.refresh() }
            if succeeded && !self.suppressFollowup { success() }
        }
    }
    private func record(_ title: String, detail: String, failed: Bool) {
        console.append(GitConsoleEntry(title: title, detail: String(detail.prefix(8192)), failed: failed))
        if console.count > 100 { console.removeFirst(console.count - 100) }
    }
    func cancel() {
        suppressFollowup = true
        writeTask?.cancel()
    }
    func stop() async {
        stopping = true
        suppressFollowup = true
        debounce?.cancel()
        watcher?.stop()
        watcher = nil
        metadataWatcher?.stop()
        metadataWatcher = nil
        let pending = Array(tasks.values)
        for task in pending { task.cancel() }
        tasks.removeAll()
        writeTask?.cancel()
        await writeTask?.value
        for task in pending { await task.value }
        persistDraft()
    }
    func resumeIfNeeded() {
        if stopping && !writing && access != nil { configure(access: access, gitAccess: gitAccess) }
    }
}
