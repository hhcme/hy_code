import AppKit
import HyCodeWorkspace
import Observation

@MainActor @Observable final class DartWorkspaceController: EditorLanguageController {
    weak var flutter: FlutterWorkspaceController?
    var sdkPath = UserDefaults.standard.string(forKey: "dart.sdkPath") ?? ""
    @ObservationIgnored private var appliedSDKPath = UserDefaults.standard.string(forKey: "dart.sdkPath") ?? ""
    @ObservationIgnored private(set) var semanticRevision: UInt64 = 0
    private(set) var status = "打开 Dart 文件后启动分析"
    private(set) var analyzing = false
    private(set) var toolchain: DartToolchain?
    private(set) var project: DartProjectInfo?
    private(set) var diagnostics: [String: [LSPDiagnostic]] = [:]
    private(set) var diagnosticsLimited = false
    @ObservationIgnored private var diagnosticCount = 0
    private(set) var locations: [LSPLocation] = []
    private(set) var symbols: [JSONValue] = []
    private(set) var symbolURI = ""
    private(set) var output = ""
    private(set) var toolRunning = false
    var packageName = ""
    var addDevDependency = false
    var onNavigate: ((LSPLocation) -> Void)?
    var onShowResults: (() -> Void)?
    var onDiagnosticsChanged: (([String: [LSPDiagnostic]], Bool) -> Void)?
    @ObservationIgnored private var projectAnalysisEnabled = false
    func startProjectAnalysis() {
        projectAnalysisEnabled = true
        enqueue { _ in }
    }
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var server: DartLanguageServer?
    @ObservationIgnored private var startup: Task<Void, Error>?
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var features: [String: WeakFeature] = [:]
    @ObservationIgnored private var runner: DeveloperToolTask?
    @ObservationIgnored private var sentVersions: [String: Int] = [:]
    @ObservationIgnored private var waitingDiagnostics: [String: JSONValue] = [:]
    @ObservationIgnored private var diagnosticWorker: Task<Void, Never>?
    @ObservationIgnored private var pendingDiagnostics: [String: JSONValue] = [:]
    @ObservationIgnored private var diagnosticTickets: [String: UUID] = [:]
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var execution: Task<Void, Never>?
    @ObservationIgnored private var projectRequest = UUID()
    @ObservationIgnored private var activePath = ""
    var prepareTool: ((URL) async -> Bool)?
    var finishedTool: ((URL) -> Void)?
    @ObservationIgnored private var runningDirectory: URL?
    @ObservationIgnored private var restarting = false
    @ObservationIgnored private var pendingOutput = ""
    @ObservationIgnored private var outputFlush: Task<Void, Never>?
    private final class WeakFeature {
        weak var value: EditorLanguageFeatures?
        init(_ value: EditorLanguageFeatures) { self.value = value }
    }

    func configure(access: WorkspaceAccess?) {
        restarting = false
        if self.access?.url != access?.url { activePath = "" }
        stop()
        self.access = access
        refreshProject()
    }
    @discardableResult func stop() -> Task<Void, Never> {
        projectAnalysisEnabled = false
        semanticRevision &+= 1
        for value in features.values {
            value.value?.hoverInteraction.invalidate()
            value.value?.setDiagnostics([])
        }
        generation = UUID()
        outputFlush?.cancel()
        outputFlush = nil
        pendingOutput = ""
        startup?.cancel()
        startup = nil
        listener?.cancel()
        listener = nil
        tail?.cancel()
        tail = nil
        let server = server
        let runner = runner
        let access = access
        let execution = execution
        let previous = cleanup
        let finished = finishedTool
        let directory = runningDirectory
        runningDirectory = nil
        execution?.cancel()
        self.execution = nil
        self.server = nil
        self.runner = nil
        let cleanup = Task {
            async let stopAnalysis: Void = server?.stop() ?? ()
            async let stopTool: Void = runner?.stop() ?? ()
            _ = await (stopAnalysis, stopTool)
            await execution?.value
            await previous?.value
            if let directory { finished?(directory) }
            withExtendedLifetime(access) {}
        }
        self.cleanup = cleanup
        features.removeAll()
        sentVersions.removeAll()
        waitingDiagnostics.removeAll()
        diagnosticWorker?.cancel()
        diagnosticWorker = nil
        pendingDiagnostics.removeAll()
        diagnosticTickets.removeAll()
        diagnostics.removeAll()
        diagnosticCount = 0
        locations.removeAll()
        symbols.removeAll()
        status = "打开 Dart 文件后启动分析"
        analyzing = false
        project = nil
        toolchain = nil
        flutter?.metadata(sdk: nil, project: nil)
        toolRunning = false
        diagnosticsLimited = false
        onDiagnosticsChanged?([:], false)
        return cleanup
    }
    func refreshProject(path: String? = nil) {
        guard let access else { return }
        if let path, !path.hasPrefix("/") { activePath = path }
        let path = activePath
        projectRequest = UUID()
        project = nil
        flutter?.metadata(sdk: nil, project: nil)
        let request = projectRequest
        let generation = generation
        let configured = appliedSDKPath
        Task { [weak self, access] in
            let result = await Task.detached(priority: .utility) {
                (
                    try? DartToolchain.discover(configured: configured),
                    try? DartProjectInfo.inspect(workspace: access.url, path: path)
                )
            }.value
            guard let self, self.generation == generation, self.projectRequest == request else { return }
            self.toolchain = result.0
            self.project = result.1
            self.flutter?.metadata(sdk: result.0, project: result.1)
        }
    }
    func restart() {
        UserDefaults.standard.set(sdkPath, forKey: "dart.sdkPath")
        appliedSDKPath = sdkPath
        let analyzeProject = projectAnalysisEnabled
        let current = features.values.compactMap(\.value)
        let access = access
        let cleanup = stop()
        let generation = generation
        restarting = true
        toolRunning = true
        Task { [weak self] in
            await cleanup.value
            guard let self, self.generation == generation else { return }
            let openedDuringRestart = self.features.values.compactMap(\.value)
            self.configure(access: access)
            if analyzeProject { self.startProjectAnalysis() }
            var replayed = Set<String>()
            for feature in current + openedDuringRestart where feature.document?.closed == false {
                if replayed.insert(feature.uri).inserted { feature.reopen() }
            }
        }
    }
    private func ensureServer() -> (DartLanguageServer, Task<Void, Error>)? {
        guard !restarting else { return nil }
        if let server, let startup { return (server, startup) }
        guard let access else { return nil }
        let server = DartLanguageServer()
        let configured = appliedSDKPath
        let generation = generation
        self.server = server
        status = "正在启动 Dart 分析器…"
        let startup = Task { [weak self, access] in
            let sdk = try await Task.detached(priority: .utility) { try DartToolchain.discover(configured: configured) }
                .value
            try Task.checkCancellation()
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("io.github.hhcme.hycode/analysis/" + generation.uuidString)
            try await server.initialize(root: access.url, toolchain: sdk, cache: cache)
            guard let self, self.generation == generation, !Task.isCancelled else {
                await server.stop()
                throw CancellationError()
            }
            self.toolchain = sdk
            self.status = "Dart \(sdk.dartVersion) · 分析服务已连接"
        }
        self.startup = startup
        listener = Task { [weak self] in
            for await event in server.events {
                guard let self, self.generation == generation else { return }
                self.receive(event)
            }
        }
        return (server, startup)
    }
    private func enqueue(_ action: @escaping @Sendable (DartLanguageServer) async throws -> Void) {
        guard let (server, startup) = ensureServer() else { return }
        let previous = tail
        let generation = generation
        tail = Task { [weak self] in
            await previous?.value
            do {
                try await startup.value
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                try await action(server)
            } catch {
                guard let self, self.generation == generation, !(error is CancellationError) else { return }
                self.status = error.localizedDescription
            }
        }
    }
    func opened(_ feature: EditorLanguageFeatures, text: String) {
        semanticRevision &+= 1
        features[feature.uri] = WeakFeature(feature)
        let uri = feature.uri
        let version = feature.version
        enqueue { [weak self] server in
            try await server.open(uri: uri, text: text, version: version)
            await self?.didSend(uri: uri, version: version)
        }
    }
    func changed(uri: String, range: LSPRange, text: String, version: Int) {
        semanticRevision &+= 1
        diagnosticCount -= diagnostics[uri]?.count ?? 0
        diagnostics[uri] = nil
        onDiagnosticsChanged?(diagnostics, diagnosticsLimited)
        waitingDiagnostics[uri] = nil
        pendingDiagnostics[uri] = nil
        diagnosticTickets[uri] = nil
        enqueue { [weak self] server in
            try await server.change(uri: uri, range: range, text: text, version: version)
            await self?.didSend(uri: uri, version: version)
        }
    }
    private func didSend(uri: String, version: Int) {
        sentVersions[uri] = version
        if let waiting = waitingDiagnostics.removeValue(forKey: uri) { receive(waiting) }
    }
    func closed(uri: String) {
        semanticRevision &+= 1
        features[uri] = nil
        sentVersions[uri] = nil
        waitingDiagnostics[uri] = nil
        pendingDiagnostics[uri] = nil
        diagnosticTickets[uri] = nil
        enqueue { await $0.close(uri: uri) }
    }
    func saved(uri: String) { enqueue { await $0.saved(uri: uri) } }
    func query(
        _ method: String, feature: EditorLanguageFeatures, position: LSPPosition? = nil,
        parameters: [String: JSONValue] = [:]
    ) async throws -> JSONValue {
        guard let (server, startup) = ensureServer() else { throw LanguageServiceFailure("没有打开工作区") }
        let generation = generation
        let version = feature.version
        await tail?.value
        try await startup.value
        try Task.checkCancellation()
        guard self.generation == generation, feature.version == version, features[feature.uri]?.value === feature else {
            throw CancellationError()
        }
        let result = try await server.request(method, uri: feature.uri, position: position)
        guard self.generation == generation, feature.version == version, features[feature.uri]?.value === feature else {
            throw CancellationError()
        }
        return result
    }
    private func receive(_ event: JSONValue) {
        switch event["method"].string {
        case "textDocument/publishDiagnostics": queueDiagnostics(event)
        case "$/analyzerStatus":
            if case .bool(let busy) = event["params"]["isAnalyzing"] {
                analyzing = busy
                status = busy ? "Dart 项目分析中…" : "Dart 分析服务已连接 · 后台监听"
            }
        case "hycode/disconnected":
            analyzing = false
            status = "Dart 分析器已退出，使用“重启分析器”重新连接"
        case "window/showMessage": status = event["params"]["message"].string ?? status
        default: break
        }
    }
    private func queueDiagnostics(_ event: JSONValue) {
        let params = event["params"]
        guard let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL,
            let root = access?.url, url.path.hasPrefix(root.path + "/")
        else { return }
        if let feature = features[uri]?.value, params["version"].int == nil, sentVersions[uri] != feature.version {
            waitingDiagnostics[uri] = event
            return
        }
        guard pendingDiagnostics.count < 500 || pendingDiagnostics[uri] != nil else {
            diagnosticsLimited = true
            return
        }
        pendingDiagnostics[uri] = params
        diagnosticTickets[uri] = UUID()
        guard diagnosticWorker == nil else { return }
        let generation = generation
        diagnosticWorker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.diagnosticWorker = nil } }
            while let (uri, params) = self.pendingDiagnostics.first {
                self.pendingDiagnostics[uri] = nil
                let ticket = self.diagnosticTickets[uri]
                defer { if self.diagnosticTickets[uri] == ticket { self.diagnosticTickets[uri] = nil } }
                let values = await Task.detached(priority: .utility) {
                    try? JSONValue.array(Array(params["diagnostics"].array.prefix(1_000))).decode([LSPDiagnostic].self)
                }.value
                guard self.generation == generation, !Task.isCancelled else { return }
                guard ticket == self.diagnosticTickets[uri], let values else { continue }
                if let feature = self.features[uri]?.value {
                    if let version = params["version"].int {
                        guard version == feature.version else { continue }
                    } else {
                        // Dart 3.11 omits diagnostic versions. This only gates
                        // display behind sent edits; it cannot prove freshness.
                        guard self.sentVersions[uri] == feature.version else { continue }
                    }
                }
                if values.isEmpty {
                    self.diagnosticCount -= self.diagnostics[uri]?.count ?? 0
                    self.diagnostics[uri] = nil
                    self.features[uri]?.value?.setDiagnostics([])
                    self.onDiagnosticsChanged?(self.diagnostics, self.diagnosticsLimited)
                    continue
                }
                guard self.diagnostics.count < 500 || self.diagnostics[uri] != nil else {
                    self.diagnosticsLimited = true
                    continue
                }
                let otherCount = self.diagnosticCount - (self.diagnostics[uri]?.count ?? 0)
                let count = min(1_000, max(0, 5_000 - otherCount))
                self.diagnosticsLimited = self.diagnosticsLimited || params["diagnostics"].array.count > count
                let limited = Array(values.prefix(count))
                self.diagnosticCount = otherCount + limited.count
                self.diagnostics[uri] = limited.isEmpty ? nil : limited
                self.features[uri]?.value?.setDiagnostics(limited)
                self.onDiagnosticsChanged?(self.diagnostics, self.diagnosticsLimited)
            }
        }
    }
    func showLocations(_ result: [LSPLocation], jumpIfSingle: Bool) {
        locations = result
        if jumpIfSingle, result.count == 1, let first = result.first { onNavigate?(first) } else { onShowResults?() }
    }
    func report(_ error: Error) { if !(error is CancellationError) { status = error.localizedDescription } }
    func clearLocations() { locations.removeAll() }
    func showSymbols(_ feature: EditorLanguageFeatures) {
        Task {
            do {
                symbols = try await query("textDocument/documentSymbol", feature: feature).array
                symbolURI = feature.uri
            } catch {
                report(error)
            }
        }
    }
    func runPub(_ verb: String) {
        guard ["get", "outdated", "upgrade", "add", "remove", "deps"].contains(verb) else { return }
        guard !toolRunning, flutter?.active != true, flutter?.commandRunning != true, let project, let sdk = toolchain
        else { return }
        var arguments = ["pub", verb]
        if verb == "add" || verb == "remove" {
            let name = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.range(of: #"^[a-z][a-z0-9_]*(?::[^\s]+)?$"#, options: .regularExpression) != nil else {
                output = "请输入包名或 包名:版本约束"
                return
            }
            if verb == "add", addDevDependency { arguments.append("--dev") }
            arguments.append(name)
        }
        if verb == "deps" { arguments.append("--json") }
        let executable = project.isFlutter ? sdk.flutter : sdk.dart
        guard let executable else {
            output = "此项目需要 Flutter SDK，请在设置中选择 Flutter SDK"
            return
        }
        execute(executable: executable, arguments: arguments, directory: project.root)
    }
    func execute(executable: URL, arguments: [String], directory: URL) {
        guard !toolRunning else { return }
        toolRunning = true
        runningDirectory = directory
        output = "> " + executable.lastPathComponent + " " + arguments.joined(separator: " ") + "\n"
        let runner = DeveloperToolTask()
        let generation = generation
        let access = access
        self.runner = runner
        execution = Task { [weak self, access] in
            defer { withExtendedLifetime(access) {} }
            defer {
                if let self, self.generation == generation {
                    self.finishedTool?(directory)
                    self.semanticRevision &+= 1
                    for value in self.features.values { value.value?.hoverInteraction.invalidate() }
                    self.runningDirectory = nil
                }
            }
            do {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                if let prepare = self.prepareTool, !(await prepare(directory)) {
                    self.toolRunning = false
                    self.runner = nil
                    self.output += "\n清单未能保存或正在关闭，未执行工具命令"
                    return
                }
                guard self.generation == generation, !Task.isCancelled else { return }
                let result = try await runner.run(executable: executable, arguments: arguments, directory: directory) {
                    [weak self] text in
                    await self?.appendOutput(text, generation: generation)
                }
                guard self.generation == generation else { return }
                self.flushOutput(generation: generation)
                self.output += "\n任务结束：\(result.exitCode)" + (result.truncated ? "（输出已截断）" : "")
            } catch {
                guard let self, self.generation == generation else { return }
                self.flushOutput(generation: generation)
                self.output += "\n" + error.localizedDescription
            }
            guard let self, self.generation == generation else { return }
            self.toolRunning = false
            self.runner = nil
            self.refreshProject()
        }
    }
    private func appendOutput(_ text: String, generation: UUID) {
        guard self.generation == generation else { return }
        pendingOutput += text
        if pendingOutput.utf8.count > 131_072 { pendingOutput = String(pendingOutput.suffix(65_536)) }
        guard outputFlush == nil else { return }
        outputFlush = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            self?.flushOutput(generation: generation)
        }
    }
    private func flushOutput(generation: UUID) {
        guard self.generation == generation else { return }
        outputFlush?.cancel()
        outputFlush = nil
        output += pendingOutput
        pendingOutput = ""
        if output.utf8.count > 262_144 { output = String(output.suffix(131_072)) }
    }
    func cancelTool() {
        let runner = runner
        Task { await runner?.cancel() }
    }
}
