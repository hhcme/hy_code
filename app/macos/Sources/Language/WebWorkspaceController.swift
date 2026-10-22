import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable final class WebWorkspaceController: EditorLanguageController {
    var nodePath = UserDefaults.standard.string(forKey: "web.nodePath") ?? ""
    @ObservationIgnored private var appliedNode = UserDefaults.standard.string(forKey: "web.nodePath") ?? ""
    private(set) var semanticRevision: UInt64 = 0
    private(set) var editRevision: UInt64 = 0
    private(set) var status = "打开 Web 文件后启动语言服务"
    private(set) var diagnostics: [String: [LSPDiagnostic]] = [:]
    private(set) var diagnosticsLimited = false
    @ObservationIgnored private var diagnosticCount = 0
    private(set) var locations: [LSPLocation] = []
    private(set) var symbols: [JSONValue] = []
    private(set) var symbolURI = ""
    private(set) var project: WebProject?
    private(set) var toolchain: WebToolchain?
    private(set) var output = ""
    private(set) var toolRunning = false
    private(set) var projectCodeTrusted = false
    let projectAnalysis = ProjectAnalysisController()
    var onDiagnosticsChanged: (([String: [LSPDiagnostic]], Bool) -> Void)?
    @ObservationIgnored private var trustKey = ""
    var packageName = ""
    var addDevDependency = false
    var onNavigate: ((LSPLocation) -> Void)?
    var onShowResults: (() -> Void)?
    var onEditPreview: ((JSONValue, EditorLanguageFeatures, Int, String) -> Void)?
    var supportsWorkspaceEdits: Bool { true }
    func invalidateEdits() { editRevision &+= 1 }
    func isSynchronized(_ feature: EditorLanguageFeatures, service: WebLanguage.Service?) -> Bool {
        guard let service, let language = WebLanguage.detect(feature.document?.path ?? "") else { return false }
        return language.synchronizes(with: service) && features[feature.uri]?.value === feature
            && sentVersions[feature.uri] == feature.version
    }
    func previewWorkspaceEdit(_ edit: JSONValue, feature: EditorLanguageFeatures, revision: Int, title: String) {
        onEditPreview?(edit, feature, revision, title)
    }
    var prepareTool: ((URL) async -> Bool)?
    var finishedTool: ((URL) -> Void)?
    var executionAllowed: (() -> Bool)?
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var server: WebLanguageServer?
    @ObservationIgnored private var startup: Task<Void, Error>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var execution: Task<Void, Never>?
    @ObservationIgnored private var runner: DeveloperToolTask?
    @ObservationIgnored private var runningDirectory: URL?
    @ObservationIgnored private var projectTicket = UUID()
    @ObservationIgnored private var activePath = ""
    @ObservationIgnored private var features: [String: WeakFeature] = [:]
    @ObservationIgnored private var sentVersions: [String: Int] = [:]
    @ObservationIgnored private var pendingDiagnostics: [String: JSONValue] = [:]
    @ObservationIgnored private var diagnosticTask: Task<Void, Never>?
    @ObservationIgnored private var diagnosticTickets: [String: UUID] = [:]
    @ObservationIgnored private var diagnosticsByService: [String: [String: [LSPDiagnostic]]] = [:]
    @ObservationIgnored private var pendingOutput = ""
    @ObservationIgnored private var flush: Task<Void, Never>?
    @ObservationIgnored private var restarting = false
    private final class WeakFeature {
        weak var value: EditorLanguageFeatures?
        init(_ value: EditorLanguageFeatures) { self.value = value }
    }
    private var services: URL {
        if Bundle.main.bundleURL.pathExtension == "app", let resources = Bundle.main.resourceURL {
            return resources.appendingPathComponent("web-language-services")
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/web-language-services")
    }
    func configure(access: WorkspaceAccess?) {
        stop()
        self.access = access
        trustKey = access.map { "web.projectPlugins." + $0.url.standardizedFileURL.path } ?? ""
        projectCodeTrusted = !trustKey.isEmpty && UserDefaults.standard.bool(forKey: trustKey)
        activePath = ""
        refreshProject()
        projectAnalysis.configure(access: access) { [weak self] in
            guard let self else { throw CancellationError() }
            let (server, startup) = try await self.ensureServer()
            try await startup.value
            return server
        }
    }
    @discardableResult func stop() -> Task<Void, Never> {
        semanticRevision &+= 1
        editRevision &+= 1
        generation = UUID()
        projectTicket = UUID()
        for feature in features.values {
            feature.value?.hoverInteraction.invalidate()
            feature.value?.setDiagnostics([])
        }
        let oldServer = server
        let oldRunner = runner
        let oldExecution = execution
        let analysisCleanup = projectAnalysis.stop()
        let previous = cleanup
        let access = access
        let directory = runningDirectory
        let finished = finishedTool
        startup?.cancel()
        listener?.cancel()
        tail?.cancel()
        execution?.cancel()
        diagnosticTask?.cancel()
        flush?.cancel()
        server = nil
        startup = nil
        listener = nil
        tail = nil
        execution = nil
        runner = nil
        diagnosticTask = nil
        flush = nil
        runningDirectory = nil
        restarting = false
        features.removeAll()
        sentVersions.removeAll()
        pendingDiagnostics.removeAll()
        diagnosticTickets.removeAll()
        diagnosticsByService.removeAll()
        diagnostics.removeAll()
        diagnosticCount = 0
        locations.removeAll()
        symbols.removeAll()
        project = nil
        toolchain = nil
        toolRunning = false
        diagnosticsLimited = false
        pendingOutput = ""
        status = "打开 Web 文件后启动语言服务"
        let task = Task {
            async let analysis: Void = oldServer?.stop() ?? ()
            async let command: Void = oldRunner?.stop() ?? ()
            _ = await (analysis, command)
            await analysisCleanup.value
            await oldExecution?.value
            await previous?.value
            if let directory { finished?(directory) }
            withExtendedLifetime(access) {}
        }
        cleanup = task
        onDiagnosticsChanged?([:], false)
        return task
    }
    func refreshProject(path: String? = nil) {
        guard let access else { return }
        if let path, !path.hasPrefix("/") { activePath = path }
        let path = activePath
        let node = appliedNode
        let services = services
        projectTicket = UUID()
        let ticket = projectTicket
        let generation = generation
        Task { [weak self, access] in
            let result = await Task.detached(priority: .utility) {
                (
                    try? WebProject.inspect(workspace: access.url, path: path),
                    try? WebToolchain.discover(configured: node, services: services)
                )
            }.value
            guard let self, self.generation == generation, self.projectTicket == ticket else { return }
            self.project = result.0
            self.toolchain = result.1
        }
    }
    func restart() {
        UserDefaults.standard.set(nodePath, forKey: "web.nodePath")
        appliedNode = nodePath
        let current = features.values.compactMap(\.value)
        let access = access
        let task = stop()
        let generation = generation
        restarting = true
        Task { [weak self] in
            await task.value
            guard let self, self.generation == generation else { return }
            let latest = self.features.values.compactMap(\.value)
            self.configure(access: access)
            var seen = Set<String>()
            for feature in current + latest where feature.document?.closed == false {
                if seen.insert(feature.uri).inserted { feature.reopen() }
            }
        }
    }
    func setProjectCodeTrusted(_ trusted: Bool) {
        guard !trustKey.isEmpty, !toolRunning else { return }
        UserDefaults.standard.set(trusted, forKey: trustKey)
        projectCodeTrusted = trusted
        restart()
    }
    private func ensureServer() async throws -> (WebLanguageServer, Task<Void, Error>) {
        guard !restarting, let access else { throw LanguageServiceFailure("Web 服务正在重启或没有工作区") }
        if let server, let startup { return (server, startup) }
        let context = generation
        let configured = appliedNode
        let directory = services
        let tools = try await Task.detached(priority: .utility) {
            try WebToolchain.discover(configured: configured, services: directory)
        }.value
        guard generation == context, !restarting, !Task.isCancelled else { throw CancellationError() }
        if let server, let startup { return (server, startup) }
        let server = WebLanguageServer(root: access.url, tools: tools, allowProjectPlugins: projectCodeTrusted)
        self.server = server
        toolchain = tools
        let generation = generation
        let previous = cleanup
        let task = Task { [weak self, access] in
            await previous?.value
            try Task.checkCancellation()
            let command = DeveloperToolTask()
            let result = try await command.run(
                executable: tools.node, arguments: ["--version"], directory: tools.services
            ) { _ in }
            guard result.exitCode == 0, WebToolchain.supportsNode(result.stdout) else {
                throw LanguageServiceFailure("Web 工具要求 Node.js 22.22.2 或更新")
            }
            guard let self, self.generation == generation, !Task.isCancelled else { throw CancellationError() }
            self.status = "Web 语言服务就绪 · " + result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            withExtendedLifetime(access) {}
        }
        startup = task
        listener = Task { [weak self] in
            for await event in server.events {
                guard let self, self.generation == generation else { return }
                self.receive(event)
            }
        }
        return (server, task)
    }
    private func enqueue(_ action: @escaping @Sendable (WebLanguageServer) async throws -> Void) {
        let previous = tail
        let generation = generation
        tail = Task { [weak self] in
            await previous?.value
            do {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                let (server, startup) = try await self.ensureServer()
                try await startup.value
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                try await action(server)
            } catch { if self?.generation == generation { self?.report(error) } }
        }
    }
    func opened(_ feature: EditorLanguageFeatures, text: String) {
        semanticRevision &+= 1
        features[feature.uri] = WeakFeature(feature)
        guard let language = WebLanguage.detect(feature.document?.path ?? "") else { return }
        let uri = feature.uri
        let version = feature.version
        enqueue { [weak self] server in
            try await server.open(uri: uri, language: language, text: text, version: version)
            await self?.sent(uri, version: version)
        }
    }
    func changed(uri: String, range: LSPRange, text: String, version: Int) {
        semanticRevision &+= 1
        editRevision &+= 1
        diagnosticCount -= diagnostics[uri]?.count ?? 0
        diagnostics[uri] = nil
        diagnosticsByService[uri] = nil
        onDiagnosticsChanged?(diagnostics, diagnosticsLimited)
        for key in diagnosticTickets.keys.filter({ $0.hasSuffix("|" + uri) }) {
            diagnosticTickets[key] = nil
            pendingDiagnostics[key] = nil
        }
        let context = generation
        enqueue { [weak self] server in
            try await server.change(uri: uri, range: range, text: text, version: version)
            guard await self?.generation == context else { return }
            await self?.sent(uri, version: version)
            await self?.projectAnalysis.edited(uri: uri)
        }
    }
    private func sent(_ uri: String, version: Int) {
        if features[uri]?.value != nil { sentVersions[uri] = version }
    }
    func closed(uri: String) {
        semanticRevision &+= 1
        editRevision &+= 1
        features[uri] = nil
        sentVersions[uri] = nil
        for key in diagnosticTickets.keys.filter({ $0.hasSuffix("|" + uri) }) {
            diagnosticTickets[key] = nil
            pendingDiagnostics[key] = nil
        }
        // A pending open may still be discovering Node; close behind that open
        // even before the actor has been assigned to this owner.
        if server != nil || tail != nil {
            let context = generation
            enqueue { [weak self] server in
                await server.close(uri: uri)
                await self?.closedOnServer(uri: uri, context: context)
            }
        }
    }
    private func closedOnServer(uri: String, context: UUID) {
        guard generation == context else { return }
        projectAnalysis.edited(uri: uri)
    }
    func saved(uri: String) { if server != nil { enqueue { await $0.saved(uri: uri) } } }
    func query(
        _ method: String, feature: EditorLanguageFeatures, position: LSPPosition?,
        parameters: [String: JSONValue]
    ) async throws -> JSONValue {
        let generation = generation
        let revision = feature.version
        let workspaceRevision = editRevision
        let (server, startup) = try await ensureServer()
        await tail?.value
        try await startup.value
        try Task.checkCancellation()
        guard self.generation == generation, editRevision == workspaceRevision,
            feature.version == revision, features[feature.uri]?.value === feature
        else { throw CancellationError() }
        let value = try await server.request(method, uri: feature.uri, position: position, parameters: parameters)
        guard self.generation == generation, editRevision == workspaceRevision,
            feature.version == revision, features[feature.uri]?.value === feature
        else { throw CancellationError() }
        return value
    }
    private func receive(_ event: JSONValue) {
        switch event["method"].string {
        case "textDocument/publishDiagnostics": queueDiagnostics(event)
        case "hycode/disconnected": status = (event["hycodeService"].string ?? "Web") + " 服务已退出，请重启分析器"
        case "window/showMessage": status = event["params"]["message"].string ?? status
        default: break
        }
    }
    private func queueDiagnostics(_ event: JSONValue) {
        let params = event["params"]
        guard let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL,
            let root = access?.url, url.path.hasPrefix(root.path + "/")
        else { return }
        let key = (event["hycodeService"].string ?? "web") + "|" + uri
        let service = event["hycodeService"].string ?? "web"
        guard pendingDiagnostics.count < 500 || pendingDiagnostics[key] != nil else {
            diagnosticsLimited = true
            return
        }
        if params["diagnostics"].array.count > 1_000 { diagnosticsLimited = true }
        var tagged = params
        if case .object(var fields) = tagged {
            fields["diagnostics"] = .array(
                params["diagnostics"].array.prefix(1_000).map { value in
                    guard case .object(var diagnostic) = value else { return value }
                    diagnostic["hycodeService"] = .string(service)
                    return .object(diagnostic)
                })
            tagged = .object(fields)
        }
        pendingDiagnostics[key] = tagged
        diagnosticTickets[key] = UUID()
        guard diagnosticTask == nil else { return }
        let generation = generation
        diagnosticTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.diagnosticTask = nil } }
            while let (key, params) = self.pendingDiagnostics.first {
                self.pendingDiagnostics[key] = nil
                let ticket = self.diagnosticTickets[key]
                let uri = params["uri"].string ?? ""
                let values = await Task.detached(priority: .utility) {
                    try? JSONValue.array(Array(params["diagnostics"].array.prefix(1_000))).decode([LSPDiagnostic].self)
                }.value
                guard self.generation == generation, !Task.isCancelled else { return }
                guard ticket == self.diagnosticTickets[key], let values else { continue }
                self.diagnosticTickets[key] = nil
                if let feature = self.features[uri]?.value {
                    if let version = params["version"].int {
                        guard version == feature.version else { continue }
                    } else {
                        guard self.sentVersions[uri] == feature.version else { continue }
                    }
                }
                if self.diagnostics.count >= 500, self.diagnostics[uri] == nil, !values.isEmpty {
                    self.diagnosticsLimited = true
                    continue
                }
                let otherCount = self.diagnosticCount - (self.diagnostics[uri]?.count ?? 0)
                var remaining = min(1_000, max(0, 5_000 - otherCount))
                var services = self.diagnosticsByService[uri] ?? [:]
                services[key] = values
                var combined: [LSPDiagnostic] = []
                for service in services.keys.sorted() {
                    let items = services[service] ?? []
                    self.diagnosticsLimited = self.diagnosticsLimited || items.count > remaining
                    let retained = Array(items.prefix(remaining))
                    remaining -= retained.count
                    services[service] = retained.isEmpty ? nil : retained
                    combined.append(contentsOf: retained)
                }
                self.diagnosticCount = otherCount + combined.count
                self.diagnostics[uri] = combined.isEmpty ? nil : combined
                self.diagnosticsByService[uri] = combined.isEmpty ? nil : services
                self.features[uri]?.value?.setDiagnostics(self.diagnostics[uri] ?? [])
                self.onDiagnosticsChanged?(self.diagnostics, self.diagnosticsLimited)
            }
        }
    }
    func showLocations(_ result: [LSPLocation], jumpIfSingle: Bool) {
        locations = result
        if jumpIfSingle, result.count == 1, let first = result.first { onNavigate?(first) } else { onShowResults?() }
    }
    func showSymbols(_ feature: EditorLanguageFeatures) {
        let generation = generation
        let uri = feature.uri
        Task { [weak self, weak feature] in
            do {
                guard let self, let feature else { return }
                let value = try await self.query(
                    "textDocument/documentSymbol", feature: feature, position: nil, parameters: [:])
                guard self.generation == generation else { return }
                self.symbols = Array(value.array.prefix(2_000))
                self.symbolURI = uri
            } catch { if self?.generation == generation { self?.report(error) } }
        }
    }
    func clearLocations() { locations.removeAll() }
    func resolveCompletion(_ item: JSONValue, feature: EditorLanguageFeatures) async throws -> JSONValue {
        guard item["data"] != .null, case .object(let parameters) = item else { return item }
        return try await query("completionItem/resolve", feature: feature, position: nil, parameters: parameters)
    }
    func report(_ error: Error) { if !(error is CancellationError) { status = error.localizedDescription } }
    var canRunTool: Bool { !toolRunning && project != nil && toolchain != nil && executionAllowed?() == true }
    func run(_ action: String, package: String? = nil) {
        guard canRunTool, let project, let tools = toolchain, let access else { return }
        let package = package ?? packageName
        let dev = addDevDependency
        toolRunning = true
        runningDirectory = project.root
        output = "准备 " + project.manager.rawValue + " " + action + "…\n"
        let generation = generation
        let runner = DeveloperToolTask()
        self.runner = runner
        execution = Task { [weak self, access] in
            guard let self else { return }
            defer {
                withExtendedLifetime(access) {}
                if self.generation == generation {
                    self.finishedTool?(project.root)
                    self.runningDirectory = nil
                    self.toolRunning = false
                    self.runner = nil
                    self.execution = nil
                    self.refreshProject()
                }
            }
            do {
                guard await self.prepareTool?(project.root) == true, self.generation == generation, !Task.isCancelled
                else { return }
                let (current, executable) = try await Task.detached(priority: .utility) {
                    let workspace = access.url.resolvingSymlinksInPath().standardizedFileURL
                    let relative =
                        project.root == workspace ? "" : String(project.root.path.dropFirst(workspace.path.count + 1))
                    return (
                        try WebProject.inspect(workspace: workspace, path: relative),
                        try tools.packageManager(project.manager)
                    )
                }.value
                guard self.generation == generation, !Task.isCancelled else { return }
                guard let current, current.root == project.root, current.manager == project.manager,
                    action != "script" || current.scripts[package] == project.scripts[package]
                else { throw LanguageServiceFailure("保存后包管理器或脚本已改变，请检查后重新运行") }
                var yarnMajor: Int?
                if project.manager == .yarn {
                    let version = try await runner.run(
                        executable: executable, arguments: ["--version"], directory: project.root,
                        environment: tools.environment
                    ) { _ in }
                    guard version.exitCode == 0 else { throw LanguageServiceFailure("无法读取 Yarn 版本") }
                    yarnMajor = Int(
                        version.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").first ?? ""
                    )
                }
                let args = try current.arguments(action: action, package: package, dev: dev, yarnMajor: yarnMajor)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.output += "> " + project.manager.rawValue + " " + args.joined(separator: " ") + "\n"
                let result = try await runner.run(
                    executable: executable, arguments: args, directory: project.root,
                    environment: tools.environment
                ) { [weak self] text in await self?.appendOutput(text, generation: generation) }
                guard self.generation == generation else { return }
                self.flushOutput()
                self.output += "\n任务结束：\(result.exitCode)" + (result.truncated ? "（输出已截断）" : "")
            } catch {
                if self.generation == generation {
                    self.flushOutput()
                    self.output += "\n" + error.localizedDescription
                }
            }
        }
    }
    private func appendOutput(_ text: String, generation: UUID) {
        guard self.generation == generation else { return }
        pendingOutput += text
        if pendingOutput.utf8.count > 131_072 { pendingOutput = String(pendingOutput.suffix(65_536)) }
        guard flush == nil else { return }
        flush = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard self?.generation == generation else { return }
            self?.flushOutput()
        }
    }
    private func flushOutput() {
        flush?.cancel()
        flush = nil
        output += pendingOutput
        pendingOutput = ""
        if output.utf8.count > 262_144 { output = String(output.suffix(131_072)) }
    }
    func cancelTool() {
        let runner = runner
        Task { await runner?.cancel() }
    }
}
