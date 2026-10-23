import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable final class NativeCodeController: EditorLanguageController {
    let language: NativeCodeLanguage
    private(set) var semanticRevision: UInt64 = 0
    private(set) var editRevision: UInt64 = 0
    private(set) var status: String
    private(set) var trusted = false
    private(set) var analyzing = false
    private(set) var sourceCount = 0
    private(set) var projectModel = ""
    private(set) var diagnostics: [String: [LSPDiagnostic]] = [:]
    private(set) var diagnosticsLimited = false
    private(set) var locations: [LSPLocation] = []
    private(set) var symbols: [JSONValue] = []
    private(set) var symbolURI = ""
    var onNavigate: ((LSPLocation) -> Void)?
    var onShowResults: (() -> Void)?
    var onEditPreview: ((JSONValue, EditorLanguageFeatures, Int, String) -> Void)?
    var onDiagnosticsChanged: (([String: [LSPDiagnostic]], Bool) -> Void)?
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var settings = NativeLanguageSettings()
    @ObservationIgnored private var dialect = SQLDialect.generic
    @ObservationIgnored private var trustKey = ""
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cacheURL: URL?
    @ObservationIgnored private var service: (any CodeLanguageService)?
    @ObservationIgnored private var startup: Task<Void, Error>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var catalogWorker: Task<Void, Never>?
    @ObservationIgnored private var catalogTicket = UUID()
    @ObservationIgnored private var diagnosticCount = 0
    @ObservationIgnored private var diagnosticInbox = LanguageDiagnosticInbox()
    @ObservationIgnored private var diagnosticWorker: Task<Void, Never>?
    @ObservationIgnored private var diagnosis: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshDiagnosis: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var sentVersions: [String: Int] = [:]
    @ObservationIgnored private var background: [String: NativeSourceCatalog.File] = [:]
    @ObservationIgnored private var files: [NativeSourceCatalog.File] = []
    @ObservationIgnored private var features: [String: WeakFeature] = [:]
    private final class WeakFeature {
        weak var value: EditorLanguageFeatures?
        init(_ value: EditorLanguageFeatures) { self.value = value }
    }
    init(_ language: NativeCodeLanguage) {
        self.language = language
        status = "打开 " + language.title + " 文件后启动工具"
    }
    var supportsWorkspaceEdits: Bool { language != .sql }
    func invalidateEdits() { editRevision &+= 1 }
    func configure(access: WorkspaceAccess?, settings: NativeLanguageSettings, dialect: SQLDialect) {
        stop()
        self.access = access
        self.settings = settings
        self.dialect = dialect
        trustKey = access.map { "native.trust." + language.rawValue + "." + $0.url.standardizedFileURL.path } ?? ""
        trusted = language == .sql || (!trustKey.isEmpty && UserDefaults.standard.bool(forKey: trustKey))
        if access != nil, !trusted { status = language.title + "：在编辑设置中信任项目后启用语义服务" }
    }
    func setTrusted(_ value: Bool) {
        guard language != .sql, !trustKey.isEmpty else { return }
        UserDefaults.standard.set(value, forKey: trustKey)
        restart()
    }
    func updateSettings(_ settings: NativeLanguageSettings, dialect: SQLDialect) {
        self.settings = settings
        self.dialect = dialect
        restart()
    }
    func restart() {
        let current = features.values.compactMap(\.value)
        let access = access
        let files = files
        let settings = settings
        let dialect = dialect
        configure(access: access, settings: settings, dialect: dialect)
        for feature in current where feature.document?.closed == false { feature.reopen() }
        scan(files, limited: false, force: true)
    }
    @discardableResult func stop() -> Task<Void, Never> {
        generation = UUID()
        analyzing = false
        sourceCount = 0
        semanticRevision &+= 1
        editRevision &+= 1
        let oldStartup = startup
        let oldTail = tail
        let oldCatalog = catalogWorker
        let oldCache = cacheURL
        cacheURL = nil
        startup?.cancel()
        listener?.cancel()
        tail?.cancel()
        catalogWorker?.cancel()
        catalogWorker = nil
        catalogTicket = UUID()
        for task in diagnosis.values { task.cancel() }
        refreshDiagnosis?.cancel()
        refreshDiagnosis = nil
        refreshPending = false
        let old = service
        let previous = cleanup
        let access = access
        for feature in features.values {
            feature.value?.setDiagnostics([])
            feature.value?.hoverInteraction.invalidate()
        }
        service = nil
        startup = nil
        listener = nil
        tail = nil
        diagnosis.removeAll()
        features.removeAll()
        sentVersions.removeAll()
        background.removeAll()
        files.removeAll()
        diagnosticInbox.reset()
        diagnosticWorker?.cancel()
        diagnosticWorker = nil
        diagnostics.removeAll()
        diagnosticCount = 0
        diagnosticsLimited = false
        locations.removeAll()
        symbols.removeAll()
        status = "打开 " + language.title + " 文件后启动工具"
        let task = Task {
            await old?.stop()
            _ = try? await oldStartup?.value
            await oldTail?.value
            await oldCatalog?.value
            await previous?.value
            if let oldCache {
                await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: oldCache) }.value
            }
            withExtendedLifetime(access) {}
        }
        cleanup = task
        onDiagnosticsChanged?([:], false)
        return task
    }
    private func ensureService() async throws -> (any CodeLanguageService, Task<Void, Error>) {
        guard let access, trusted else { throw LanguageServiceFailure(language.title + " 尚未获得项目导入信任") }
        if let service, let startup { return (service, startup) }
        let context = generation
        let settings = settings
        let language = language
        let discovered = try await Task.detached(priority: .utility) {
            (
                try language == .sql ? nil : NativeLanguageToolchain.discover(language, settings: settings),
                try NativeProjectModel.inspect(language: language, root: access.url)
            )
        }.value
        guard generation == context, !Task.isCancelled else { throw CancellationError() }
        if let service, let startup { return (service, startup) }
        let tools = discovered.0
        projectModel = discovered.1.title
        let service: any CodeLanguageService
        let startup: Task<Void, Error>
        let previous = cleanup
        let triggers =
            Array(features.keys.prefix(100))
            + files.prefix(100).map { access.url.appendingPathComponent($0.path).absoluteString }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyCode/native-languages/" + context.uuidString + "/" + language.rawValue)
        cacheURL = cache.deletingLastPathComponent()
        if language == .sql {
            service = SQLLanguageService(dialect: dialect)
            startup = Task {
                await previous?.value
                try Task.checkCancellation()
            }
        } else {
            let server = NativeLanguageServer(language: language)
            service = server
            startup = Task { [access] in
                await previous?.value
                try Task.checkCancellation()
                try await server.initialize(
                    root: access.url, tools: tools!, cache: cache, trusted: true, triggerFiles: triggers)
                withExtendedLifetime(access) {}
            }
        }
        self.service = service
        self.startup = startup
        listener = Task { [weak self] in
            for await event in service.events {
                guard let self, self.generation == context else { return }
                self.receive(event)
            }
        }
        status = "正在准备 " + language.title + " 项目模型…"
        return (service, startup)
    }
    private func enqueue(_ action: @escaping @MainActor (any CodeLanguageService) async throws -> Void) {
        let previous = tail
        let context = generation
        tail = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == context, !Task.isCancelled else { return }
            do {
                let (service, startup) = try await self.ensureService()
                try await startup.value
                guard self.generation == context, !Task.isCancelled else { return }
                self.status = self.language.title + " · " + self.projectModel
                try await action(service)
            } catch { if self.generation == context { self.report(error) } }
        }
    }
    func opened(_ feature: EditorLanguageFeatures, text: String) {
        semanticRevision &+= 1
        features[feature.uri] = WeakFeature(feature)
        let uri = feature.uri
        let version = feature.version
        let context = generation
        enqueue { [weak self] service in
            self?.sentVersions[uri] = version
            do { try await service.open(uri: uri, text: text, version: version) } catch {
                if self?.generation == context { self?.sentVersions[uri] = nil }
                throw error
            }
            guard let self, self.generation == context else { return }
            self.background[uri] = nil
            self.sentVersions[uri] = version
            self.scheduleDiagnosis(uri)
        }
    }
    func changed(uri: String, range: LSPRange, text: String, version: Int) {
        semanticRevision &+= 1
        editRevision &+= 1
        diagnosticCount -= diagnostics[uri]?.count ?? 0
        diagnosticInbox.remove(uri)
        diagnostics[uri] = nil
        onDiagnosticsChanged?(diagnostics, diagnosticsLimited)
        diagnosis[uri]?.cancel()
        diagnosis[uri] = nil
        let context = generation
        enqueue { [weak self] service in
            if let document = self?.features[uri]?.value?.document,
                document.semanticByteCount > (self?.language == .sql ? 256 * 1024 : 1_048_576)
            {
                self?.sentVersions[uri] = nil
                await service.close(uri: uri)
                if self?.generation == context { self?.diagnosticsLimited = true }
                throw LanguageServiceFailure("文档超过语义分析预算，基础编辑继续可用")
            }
            if let sent = self?.sentVersions[uri], sent >= version { return }
            do {
                if self?.sentVersions[uri] == nil, let feature = self?.features[uri]?.value,
                    let current = feature.document?.editor?.textView.string
                {
                    let latest = feature.version
                    self?.sentVersions[uri] = latest
                    try await service.open(uri: uri, text: current, version: latest)
                    guard self?.generation == context else { return }
                    self?.sentVersions[uri] = latest
                    self?.scheduleDiagnosis(uri)
                    return
                }
                self?.sentVersions[uri] = version
                try await service.change(uri: uri, range: range, text: text, version: version)
            } catch {
                if self?.generation == context { self?.sentVersions[uri] = nil }
                throw error
            }
            guard let self, self.generation == context else { return }
            self.sentVersions[uri] = version
            self.scheduleDiagnosis(uri)
        }
    }
    func closed(uri: String) {
        semanticRevision &+= 1
        editRevision &+= 1
        features[uri] = nil
        sentVersions[uri] = nil
        diagnosis[uri]?.cancel()
        diagnosis[uri] = nil
        diagnosticCount -= diagnostics[uri]?.count ?? 0
        diagnosticInbox.remove(uri)
        diagnostics[uri] = nil
        onDiagnosticsChanged?(diagnostics, diagnosticsLimited)
        if service != nil || tail != nil { enqueue { await $0.close(uri: uri) } }
        scan(files, limited: diagnosticsLimited)
    }
    func watchedFiles(_ paths: [String]) {
        guard service != nil, let access else { return }
        let changes = paths.prefix(1000).map { (access.url.appendingPathComponent($0).absoluteString, 2) }
        enqueue { await $0.filesChanged(changes) }
    }
    func saved(uri: String) { if service != nil { enqueue { await $0.saved(uri: uri) } } }
    private func scheduleDiagnosis(_ uri: String) {
        diagnosis[uri]?.cancel()
        let context = generation
        let version = sentVersions[uri]
        diagnosis[uri] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(220))
                guard let self, self.generation == context, self.sentVersions[uri] == version else { return }
                await self.tail?.value
                try Task.checkCancellation()
                try await self.service?.diagnose(uri: uri)
            } catch { if !(error is CancellationError), self?.generation == context { self?.report(error) } }
        }
    }
    func scan(_ files: [NativeSourceCatalog.File], limited: Bool, force: Bool = false) {
        self.files = files.filter { $0.language == language }
        sourceCount = self.files.count
        if force { diagnosticsLimited = false }
        diagnosticsLimited = diagnosticsLimited || limited || (!trusted && sourceCount > 0)
        onDiagnosticsChanged?(diagnostics, diagnosticsLimited)
        catalogWorker?.cancel()
        catalogTicket = UUID()
        let scanTicket = catalogTicket
        guard trusted, let access, !self.files.isEmpty || !background.isEmpty else { return }
        let selected = self.files
        analyzing = true
        let context = generation
        // Read and diagnose one background file at a time, outside the live
        // synchronization tail. Opening/editing never waits for a project scan.
        catalogWorker = Task { [weak self, access] in
            guard let self else { return }
            defer { if self.generation == context, self.catalogTicket == scanTicket { self.analyzing = false } }
            let uris = Set(selected.map { access.url.appendingPathComponent($0.path).absoluteString })
            for uri in self.background.keys where !uris.contains(uri) {
                self.enqueue { service in await service.close(uri: uri) }
                self.background[uri] = nil
                self.diagnosticCount -= self.diagnostics[uri]?.count ?? 0
                self.diagnostics[uri] = nil
                self.sentVersions[uri] = nil
                self.diagnosticInbox.remove(uri)
            }
            for file in selected {
                guard !Task.isCancelled, self.generation == context, self.catalogTicket == scanTicket else { return }
                let uri = access.url.appendingPathComponent(file.path).absoluteString
                if self.features[uri]?.value != nil { continue }
                if !force, self.background[uri] == file { continue }
                do {
                    let read = Task.detached(priority: .utility) {
                        try NativeSourceCatalog.read(path: file.path, root: access.url)
                    }
                    let text = try await withTaskCancellationHandler {
                        try await read.value
                    } onCancel: {
                        read.cancel()
                    }
                    guard !Task.isCancelled, self.generation == context, self.catalogTicket == scanTicket,
                        self.features[uri]?.value == nil
                    else { continue }
                    self.enqueue { [weak self] service in
                        guard let self, self.generation == context, self.catalogTicket == scanTicket,
                            self.features[uri]?.value == nil
                        else { return }
                        self.sentVersions[uri] = 0
                        do { try await service.open(uri: uri, text: text, version: 0) } catch {
                            if self.generation == context {
                                self.sentVersions[uri] = nil
                                self.diagnosticsLimited = true
                                self.onDiagnosticsChanged?(self.diagnostics, true)
                            }
                            throw error
                        }
                        guard self.generation == context else { return }
                        self.background[uri] = file
                        self.sentVersions[uri] = 0
                    }
                    let sync = self.tail
                    await sync?.value
                    guard !Task.isCancelled, self.generation == context, self.catalogTicket == scanTicket else {
                        return
                    }
                    try await self.service?.diagnose(uri: uri)
                } catch is CancellationError { return } catch {
                    guard self.generation == context, self.catalogTicket == scanTicket, !Task.isCancelled else {
                        return
                    }
                    self.diagnosticsLimited = true
                    self.status = self.language.title + " 部分文件检查不可用：" + error.localizedDescription
                }
                await Task.yield()
            }
            guard self.generation == context, self.catalogTicket == scanTicket, !Task.isCancelled else { return }
            self.onDiagnosticsChanged?(self.diagnostics, self.diagnosticsLimited)
            withExtendedLifetime(access) {}
        }
    }
    func query(
        _ method: String, feature: EditorLanguageFeatures, position: LSPPosition?, parameters: [String: JSONValue]
    ) async throws -> JSONValue {
        let context = generation
        let revision = feature.version
        let workspaceRevision = editRevision
        await tail?.value
        let (service, startup) = try await ensureService()
        try await startup.value
        guard generation == context, editRevision == workspaceRevision, feature.version == revision,
            features[feature.uri]?.value === feature, sentVersions[feature.uri] == revision
        else { throw CancellationError() }
        let result = try await service.request(method, uri: feature.uri, position: position, parameters: parameters)
        try Task.checkCancellation()
        guard generation == context, editRevision == workspaceRevision, feature.version == revision else {
            throw CancellationError()
        }
        return result
    }
    func resolveCompletion(_ item: JSONValue, feature: EditorLanguageFeatures) async throws -> JSONValue {
        guard case .object(let fields) = item else { return item }
        return try await query("completionItem/resolve", feature: feature, position: nil, parameters: fields)
    }
    func isSynchronized(_ feature: EditorLanguageFeatures, service: WebLanguage.Service?) -> Bool {
        service == nil && features[feature.uri]?.value === feature && sentVersions[feature.uri] == feature.version
    }
    func previewWorkspaceEdit(_ edit: JSONValue, feature: EditorLanguageFeatures, revision: Int, title: String) {
        onEditPreview?(edit, feature, revision, title)
    }
    private func receive(_ event: JSONValue) {
        switch event["method"].string {
        case "textDocument/publishDiagnostics":
            let params = event["params"]
            guard let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL, let access,
                url.path.hasPrefix(access.url.path + "/"), sentVersions[uri] != nil,
                params["version"].int == nil || params["version"].int == sentVersions[uri],
                features[uri]?.value == nil || features[uri]?.value?.version == sentVersions[uri]
            else { return }
            if diagnostics.count >= 2000 && diagnostics[uri] == nil {
                diagnosticsLimited = true
                return
            }
            if params["diagnostics"].array.count > 1000 { diagnosticsLimited = true }
            guard diagnosticInbox.offer(uri: uri, version: sentVersions[uri], values: params["diagnostics"].array)
            else {
                diagnosticsLimited = true
                onDiagnosticsChanged?(diagnostics, true)
                return
            }
            drainDiagnostics()
        case "hycode/diagnosticRefresh":
            refreshPending = true
            guard refreshDiagnosis == nil else { return }
            let context = generation
            refreshDiagnosis = Task { [weak self] in
                guard let self else { return }
                defer { if self.generation == context { self.refreshDiagnosis = nil } }
                do {
                    while self.refreshPending {
                        try await Task.sleep(for: .milliseconds(200))
                        self.refreshPending = false
                        for uri in self.sentVersions.keys.sorted() {
                            try Task.checkCancellation()
                            guard self.generation == context else { return }
                            try await self.service?.diagnose(uri: uri)
                        }
                    }
                } catch { if self.generation == context { self.report(error) } }
            }
        case "hycode/disconnected": status = language.title + " 服务已退出，可在设置重启"
        case "window/showMessage": status = String((event["params"]["message"].string ?? status).prefix(2000))
        default: break
        }
    }
    private func drainDiagnostics() {
        guard diagnosticWorker == nil else { return }
        let context = generation
        diagnosticWorker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == context { self.diagnosticWorker = nil } }
            do {
                while let message = self.diagnosticInbox.take() {
                    try Task.checkCancellation()
                    guard self.generation == context, self.diagnosticInbox.isCurrent(message) else { continue }
                    let parse = Task.detached(priority: .utility) {
                        var values: [LSPDiagnostic] = []
                        for raw in message.values {
                            try Task.checkCancellation()
                            if let value = try? raw.decode(LSPDiagnostic.self) { values.append(value) }
                        }
                        return values
                    }
                    let values = try await withTaskCancellationHandler {
                        try await parse.value
                    } onCancel: {
                        parse.cancel()
                    }
                    guard self.generation == context, self.diagnosticInbox.isCurrent(message),
                        self.sentVersions[message.uri] == message.version,
                        self.features[message.uri]?.value == nil
                            || self.features[message.uri]?.value?.version == message.version
                    else { continue }
                    self.diagnosticCount -= self.diagnostics[message.uri]?.count ?? 0
                    let accepted = Array(values.prefix(max(0, 10_000 - self.diagnosticCount)))
                    if accepted.count < values.count { self.diagnosticsLimited = true }
                    self.diagnosticCount += accepted.count
                    self.diagnostics[message.uri] = accepted
                    self.features[message.uri]?.value?.setDiagnostics(accepted)
                    self.onDiagnosticsChanged?(self.diagnostics, self.diagnosticsLimited)
                }
            } catch {}
        }
    }
    func showLocations(_ result: [LSPLocation], jumpIfSingle: Bool) {
        locations = Array(result.prefix(2000))
        if jumpIfSingle, result.count == 1, let first = result.first { onNavigate?(first) } else { onShowResults?() }
    }
    func clearLocations() { locations.removeAll() }
    func showSymbols(_ feature: EditorLanguageFeatures) {
        Task { [weak self, weak feature] in
            guard let self, let feature else { return }
            do {
                let value = try await query(
                    "textDocument/documentSymbol", feature: feature, position: nil, parameters: [:])
                symbols = Array(value.array.prefix(1000))
                symbolURI = feature.uri
                onShowResults?()
            } catch { report(error) }
        }
    }
    func report(_ error: Error) {
        if !(error is CancellationError) {
            status = language.title + "：" + String(error.localizedDescription.prefix(2000))
        }
    }
}
