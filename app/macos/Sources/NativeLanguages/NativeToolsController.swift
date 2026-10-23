import Foundation
import HyCodeWorkspace
import Observation

/// One metadata scan/watcher, independent service owners and native documents.
@MainActor @Observable final class NativeToolsController {
    let swift = NativeCodeController(.swift)
    let java = NativeCodeController(.java)
    let sql = NativeCodeController(.sql)
    var sourceKitPath = UserDefaults.standard.string(forKey: "native.sourceKitPath") ?? ""
    var javaHome = UserDefaults.standard.string(forKey: "native.javaHome") ?? ""
    var jdtlsPath = UserDefaults.standard.string(forKey: "native.jdtlsPath") ?? ""
    var dialect =
        SQLDialect(rawValue: UserDefaults.standard.string(forKey: "native.sqlDialect") ?? "generic") ?? .generic
    private(set) var status = "未打开项目"
    private(set) var running = false
    private(set) var watchUnavailable = false
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var watcher: WorkspaceSourceWatcher?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var forceScan = false
    var hasWorkspace: Bool { access != nil }
    var owners: [NativeCodeController] { [swift, java, sql] }
    func owner(_ path: String) -> NativeCodeController? {
        switch NativeCodeLanguage.detect(path) {
        case .swift: swift
        case .java: java
        case .sql: sql
        default: nil
        }
    }
    private var settings: NativeLanguageSettings {
        NativeLanguageSettings(sourceKitPath: sourceKitPath, javaHome: javaHome, jdtlsPath: jdtlsPath)
    }
    func configure(access: WorkspaceAccess?) {
        generation = UUID()
        revision &+= 1
        worker?.cancel()
        worker = nil
        let watcher = watcher
        self.watcher = nil
        Task.detached(priority: .utility) { watcher?.stop() }
        self.access = access
        watchUnavailable = false
        for owner in owners { owner.configure(access: access, settings: settings, dialect: dialect) }
        status = access == nil ? "未打开项目" : "准备扫描 Swift / Java / SQL…"
        if access != nil { rescan() }
    }
    func applySettings() {
        UserDefaults.standard.set(sourceKitPath, forKey: "native.sourceKitPath")
        UserDefaults.standard.set(javaHome, forKey: "native.javaHome")
        UserDefaults.standard.set(jdtlsPath, forKey: "native.jdtlsPath")
        UserDefaults.standard.set(dialect.rawValue, forKey: "native.sqlDialect")
        let current = owners
        // Owners retain their live feature identities across restart. Updating
        // settings uses their normal restart path rather than reopening files.
        for owner in current { owner.updateSettings(settings, dialect: dialect) }
        rescan(force: true)
    }
    func rescan(force: Bool = false) {
        revision &+= 1
        forceScan = forceScan || force
        guard worker == nil, let access else { return }
        let context = generation
        running = true
        worker = Task { [weak self, access] in
            guard let self else { return }
            defer {
                if self.generation == context {
                    self.worker = nil
                    self.running = false
                }
            }
            do {
                if self.watcher == nil {
                    let watch = await Task.detached(priority: .utility) { [weak self] in
                        Result {
                            try WorkspaceSourceWatcher(root: access.url) { [weak self] event in
                                Task { @MainActor in
                                    guard let self, self.generation == context else { return }
                                    for owner in self.owners { owner.watchedFiles(event.paths) }
                                    if event.rescan
                                        || event.paths.contains(where: {
                                            NativeCodeLanguage.detect($0) != nil
                                                || [
                                                    "Package.swift", "Package.resolved", "pom.xml", "build.gradle",
                                                    "build.gradle.kts", "buildServer.json",
                                                ].contains(URL(fileURLWithPath: $0).lastPathComponent)
                                        })
                                    {
                                        self.rescan()
                                    }
                                }
                            }
                        }
                    }.value
                    guard self.generation == context, !Task.isCancelled else {
                        if case .success(let watcher) = watch { Task.detached(priority: .utility) { watcher.stop() } }
                        return
                    }
                    switch watch {
                    case .success(let watcher):
                        self.watcher = watcher
                        self.watchUnavailable = false
                    case .failure: self.watchUnavailable = true
                    }
                }
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(250))
                    let revision = self.revision
                    let force = self.forceScan
                    self.forceScan = false
                    let task = Task.detached(priority: .utility) { try NativeSourceCatalog.scan(root: access.url) }
                    let catalog = try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: {
                        task.cancel()
                    }
                    guard self.generation == context else { return }
                    if self.revision != revision {
                        self.forceScan = self.forceScan || force
                        continue
                    }
                    for owner in self.owners {
                        owner.scan(catalog.files, limited: catalog.limited || self.watchUnavailable, force: force)
                    }
                    self.status =
                        "Swift / Java / SQL：发现 \(catalog.files.count) 个源文件"
                        + (catalog.limited || self.watchUnavailable ? " · 扫描/监听范围受限" : "")
                    return
                }
            } catch is CancellationError {} catch {
                if self.generation == context { self.status = "源文件扫描/监听不可用：" + error.localizedDescription }
            }
            withExtendedLifetime(access) {}
        }
    }
    func stop() async {
        generation = UUID()
        worker?.cancel()
        worker = nil
        running = false
        let watcher = watcher
        self.watcher = nil
        await Task.detached(priority: .utility) { watcher?.stop() }.value
        for owner in owners { await owner.stop().value }
    }
}
