import Foundation
import HyCodeWorkspace
import Observation

@MainActor @Observable final class ProjectAnalysisController {
    private(set) var state = "未打开项目"
    private(set) var running = false
    private(set) var sourceCount = 0
    private(set) var limited = false
    private(set) var skipped = 0
    private(set) var checkedCount = 0
    private(set) var blockedVue = 0
    private(set) var unreadable = 0
    private(set) var watchUnavailable = false
    @ObservationIgnored private var watchAttempted = false
    @ObservationIgnored var onDartProject: (() -> Void)?
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var connect: (@MainActor () async throws -> WebLanguageServer)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var watcher: WorkspaceSourceWatcher?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var full = false
    @ObservationIgnored private var changed = Set<String>()
    @ObservationIgnored private var disk = Set<String>()
    @ObservationIgnored private var known = Set<String>()
    @ObservationIgnored private var dartStarted = false
    func configure(access: WorkspaceAccess?, connect: @escaping @MainActor () async throws -> WebLanguageServer) {
        _ = stop()
        self.access = access
        self.connect = connect
        guard access != nil else { return }
        full = true
        launch(immediate: true)
    }
    @discardableResult func stop() -> Task<Void, Never> {
        generation = UUID()
        let oldWorker = worker
        let oldWatcher = watcher
        let previous = cleanup
        let access = access
        oldWorker?.cancel()
        watcher = nil
        worker = nil
        self.access = nil
        connect = nil
        full = false
        changed.removeAll()
        disk.removeAll()
        known.removeAll()
        dartStarted = false
        sourceCount = 0
        checkedCount = 0
        blockedVue = 0
        unreadable = 0
        watchUnavailable = false
        watchAttempted = false
        skipped = 0
        limited = false
        running = false
        state = "未打开项目"
        let stop = Task {
            let watch = Task.detached(priority: .utility) { oldWatcher?.stop() }
            await watch.value
            await oldWorker?.value
            await previous?.value
            withExtendedLifetime(access) {}
        }
        cleanup = stop
        return stop
    }
    func rescan() {
        guard access != nil else { return }
        full = true
        launch(immediate: true)
    }
    func edited(uri: String) {
        guard let root = access?.url, let url = URL(string: uri), url.path.hasPrefix(root.path + "/") else { return }
        changed.insert(uri)
        launch()
    }
    private func filesChanged(_ event: WorkspaceFileEvents) {
        guard let access else { return }
        full = full || event.rescan
        for path in event.paths {
            if path.hasSuffix(".dart") || path.hasSuffix("pubspec.yaml") {
                if !dartStarted { full = true }
                continue
            }
            let uri = access.url.appendingPathComponent(path).absoluteString
            if !known.contains(uri) { full = true }
            changed.insert(uri)
            disk.insert(path)
        }
        if changed.count > 512 {
            full = true
            changed.removeAll()
            disk.removeAll()
        }
        launch()
    }
    private func launch(immediate: Bool = false) {
        guard worker == nil, let access, let connect else { return }
        let context = generation
        let previous = cleanup
        worker = Task { [weak self, access] in
            await previous?.value
            guard let self, self.generation == context else { return }
            defer {
                if self.generation == context {
                    self.worker = nil
                    self.running = false
                    if self.full || !self.changed.isEmpty { self.launch() }
                }
            }
            do {
                if !immediate { try await Task.sleep(for: .milliseconds(500)) }
                if !self.watchAttempted {
                    self.watchAttempted = true
                    let root = access.url
                    do {
                        let watch = try await Task.detached(priority: .utility) { [weak self] in
                            try WorkspaceSourceWatcher(root: root) { [weak self] event in
                                Task { @MainActor in if self?.generation == context { self?.filesChanged(event) } }
                            }
                        }.value
                        guard self.generation == context, !Task.isCancelled else {
                            await Task.detached(priority: .utility) { watch.stop() }.value
                            return
                        }
                        self.watcher = watch
                    } catch {
                        guard self.generation == context, !Task.isCancelled else { return }
                        self.watchUnavailable = true
                    }
                }
                while self.full || !self.changed.isEmpty {
                    try Task.checkCancellation()
                    guard self.generation == context else { return }
                    self.running = true
                    let sweep = self.full
                    let changes = self.changed
                    let disk = self.disk
                    self.full = false
                    self.changed.removeAll()
                    self.disk.removeAll()
                    let previousCount = self.sourceCount
                    var catalog: ProjectSourceCatalog?
                    if sweep {
                        self.state = "正在扫描项目源文件…"
                        let scan = Task.detached(priority: .utility) { try ProjectSourceCatalog.scan(root: access.url) }
                        let result = try await withTaskCancellationHandler {
                            try await scan.value
                        } onCancel: {
                            scan.cancel()
                        }
                        guard self.generation == context else { return }
                        let known = await Task.detached(priority: .utility) {
                            Set(result.files.map { $0.uri(in: access.url) })
                        }.value
                        guard self.generation == context, !Task.isCancelled else { return }
                        catalog = result
                        self.sourceCount = result.files.count
                        self.skipped = result.skipped
                        self.limited = result.limited
                        self.known = known
                        if result.hasDart, !self.dartStarted {
                            self.dartStarted = true
                            self.onDartProject?()
                        }
                    }
                    guard self.sourceCount > 0 || previousCount > 0 else {
                        self.state = "未发现可分析的 Web 源文件"
                        continue
                    }
                    self.state = sweep ? "正在建立项目分析…" : "正在检查变动及关联文件…"
                    let server = try await connect()
                    guard self.generation == context, !Task.isCancelled else { return }
                    if let catalog {
                        try await server.setProjectFiles(catalog.files)
                    } else if !disk.isEmpty {
                        try await server.refreshProjectFiles(disk)
                    }
                    let report = try await server.checkProject(changed: sweep ? nil : changes)
                    let scope = await server.projectScope()
                    guard self.generation == context, !Task.isCancelled else { return }
                    self.sourceCount = scope.total
                    self.unreadable = scope.failed
                    self.blockedVue = scope.blockedVue
                    self.checkedCount = report.checked.count
                    self.state = "后台监听 · \(self.sourceCount) 个 Web 源文件"
                    if self.limited || self.skipped > 0 || scope.failed > 0 { self.state += "（部分文件未纳入）" }
                    if scope.blockedVue > 0 { self.state += " · \(scope.blockedVue) 个 Vue 文件待工作区信任" }
                    if self.watchUnavailable { self.state += " · 文件监听不可用，可手动重新检查" }
                    self.running = false
                    if self.full || !self.changed.isEmpty { try await Task.sleep(for: .milliseconds(500)) }
                }
            } catch {
                if self.generation == context, !(error is CancellationError) {
                    self.state = "项目检查暂停：" + error.localizedDescription
                }
            }
        }
    }
}
