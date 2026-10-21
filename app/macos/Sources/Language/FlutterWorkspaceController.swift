import AppKit
import HyCodeWorkspace
import Observation

enum FlutterToolDialog: String, Identifiable {
    case configuration, breakpoints
    var id: String { rawValue }
}

/// Sole owner of this workspace's explicit Flutter runtime/tool tasks. The Dart
/// language owner supplies metadata; opening a project never runs these tools.
@MainActor @Observable final class FlutterWorkspaceController {
    var launch = FlutterLaunchConfiguration() { didSet { persist() } }
    private(set) var devices: [FlutterDevice] = []
    private(set) var state = FlutterDebugState()
    private(set) var status = "选择 SDK 与 Flutter 包后可运行"
    private(set) var output = ""
    private(set) var commandRunning = false
    private(set) var controlsBusy = false
    private(set) var inspectorBusy = false
    private var breakpointStore = FlutterBreakpointStore()
    var breakpoints: [String: [FlutterBreakpoint]] { breakpointStore.projected }
    private(set) var verified: [String: Set<Int>] = [:]
    private(set) var threads: [JSONValue] = []
    private(set) var frames: [JSONValue] = []
    private(set) var scopes: [JSONValue] = []
    private(set) var variables: [JSONValue] = []
    private(set) var tests = FlutterTestResults()
    private(set) var widgets: [FlutterInspectorTree.Row] = []
    private(set) var selectedFrame: Int?
    private(set) var sdk: DartToolchain?
    private(set) var project: DartProjectInfo?
    private(set) var runningRoot: URL?
    var expression = ""
    var evaluation = ""
    var testPath = ""
    var buildTarget = "macos"
    var coverage = false
    var section = FlutterToolSection.console
    var dialog: FlutterToolDialog?
    private(set) var configurationContext = UUID()
    private(set) var sessionTitle = "Flutter"
    var onNavigate: ((LSPLocation) -> Void)?
    var onReveal: (() -> Void)?
    var onBreakpointsChanged: (() -> Void)?
    var prepareRun: (() async -> Bool)?
    var executionAllowed: (() -> Bool)?
    @ObservationIgnored private var access: WorkspaceAccess?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var session: FlutterDebugSession?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var command: DeveloperToolTask?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, Never>?
    @ObservationIgnored private var breakpointTail: Task<Void, Never>?
    @ObservationIgnored private var reload: Task<Void, Never>?
    @ObservationIgnored private var flush: Task<Void, Never>?
    @ObservationIgnored private var pendingOutput = ""
    @ObservationIgnored private var isolate = ""
    @ObservationIgnored private var inspectorGroup = ""
    @ObservationIgnored private var inspectorGeneration = UUID()
    @ObservationIgnored private var initialized = false
    @ObservationIgnored private var preferencesKey = ""
    @ObservationIgnored private var breakpointTickets: [String: UUID] = [:]
    @ObservationIgnored private var variableTicket = UUID()
    @ObservationIgnored private var evaluationTicket = UUID()
    @ObservationIgnored private var pendingReload = false
    @ObservationIgnored private var sessionFailure: String?
    private struct Preferences: Codable {
        var launch: FlutterLaunchConfiguration
        var breakpoints: [String: [FlutterBreakpoint]]
    }
    var active: Bool { [.starting, .running, .paused, .stopping].contains(state.phase) }
    var available: Bool { project?.isFlutter == true && sdk?.flutter != nil && access != nil }
    var canRunTool: Bool { !active && !commandRunning && sdk?.flutter != nil && executionAllowed?() == true }
    var canStart: Bool { available && !active && !commandRunning && executionAllowed?() == true }
    var canInspect: Bool { !isolate.isEmpty && [.running, .paused].contains(state.phase) }
    var canReload: Bool { [.running, .paused].contains(state.phase) && launch.mode == .debug && !controlsBusy }
    var canEditConfiguration: Bool { !active && !commandRunning }
    func applyConfiguration(_ draft: FlutterConfigurationDraft) throws {
        launch = try draft.validated(context: configurationContext, current: launch, busy: !canEditConfiguration)
    }
    func configure(access: WorkspaceAccess?) {
        configurationContext = UUID()
        dialog = nil
        section = .console
        sessionTitle = "Flutter"
        self.access = access
        preferencesKey = access.map { "flutter.workspace." + $0.url.standardizedFileURL.path } ?? ""
        initialized = false
        devices = []
        verified = [:]
        breakpointStore = FlutterBreakpointStore()
        launch = FlutterLaunchConfiguration()
        sdk = nil
        project = nil
        if let data = UserDefaults.standard.data(forKey: preferencesKey), data.count <= 262_144,
            let value = try? JSONDecoder().decode(Preferences.self, from: data),
            (try? value.launch.validate()) != nil,
            value.breakpoints.count <= 1_000, value.breakpoints.values.reduce(0, { $0 + $1.count }) <= 1_000
        {
            launch = value.launch
            breakpointStore = FlutterBreakpointStore(
                saved: value.breakpoints.filter { path, values in
                    path.hasPrefix(access!.url.path + "/")
                        && values.allSatisfy {
                            $0.line > 0 && $0.condition.count <= 4_096 && $0.logMessage.count <= 4_096
                        }
                })
        }
        initialized = true
        onBreakpointsChanged?()
    }
    func metadata(sdk: DartToolchain?, project: DartProjectInfo?) {
        self.sdk = sdk
        self.project = project
    }
    private func persist() {
        guard initialized, !preferencesKey.isEmpty,
            let data = try? JSONEncoder().encode(Preferences(launch: launch, breakpoints: breakpointStore.persisted)),
            data.count <= 262_144
        else { return }
        UserDefaults.standard.set(data, forKey: preferencesKey)
    }
    func start(debug: Bool) {
        guard available, !active, !commandRunning, executionAllowed?() == true, let sdk, let project, let access else {
            return
        }
        let configuration = launch
        guard !configuration.deviceID.isEmpty else {
            status = "请先刷新并选择运行设备"
            onReveal?()
            return
        }
        do { try configuration.validate() } catch {
            status = error.localizedDescription
            return
        }
        let id = UUID()
        sessionID = id
        state.start()
        section = .console
        let device = devices.first { $0.id == configuration.deviceID }?.name ?? configuration.deviceID
        sessionTitle = URL(fileURLWithPath: configuration.program).lastPathComponent + " (" + device + ")"
        sessionFailure = nil
        status = "准备运行…"
        runningRoot = project.root
        controlsBusy = false
        output = ""
        frames = []
        scopes = []
        variables = []
        threads = []
        widgets = []
        pendingReload = false
        isolate = ""
        inspectorGeneration = UUID()
        inspectorGroup = "hycode-" + id.uuidString
        let session = FlutterDebugSession()
        self.session = session
        onReveal?()
        listener = Task { [weak self] in
            for await event in session.events {
                guard let self, self.sessionID == id else { return }
                self.receive(event)
            }
            guard let self, self.sessionID == id else { return }
            self.receive(JSONValue(["event": "hycode/disconnected"]))
        }
        let previous = cleanup
        operation = Task { [weak self, access] in
            await previous?.value
            guard let self, self.sessionID == id, !Task.isCancelled else { return }
            guard await self.prepareRun?() == true, self.sessionID == id, !Task.isCancelled else {
                if self.sessionID == id {
                    self.status = "运行已取消：保存未完成"
                    self.sessionFailure = self.status
                    self.state.receive(JSONValue(["event": "terminated"]))
                    await session.stop()
                }
                return
            }
            do {
                let root = project.root
                let program = configuration.program
                let valid = await Task.detached(priority: .utility) {
                    let target = root.appendingPathComponent(program).resolvingSymlinksInPath()
                    let workspace = access.url.resolvingSymlinksInPath().path
                    let package = root.resolvingSymlinksInPath().path
                    return (package == workspace || package.hasPrefix(workspace + "/"))
                        && target.path.hasPrefix(package + "/")
                        && FileManager.default.fileExists(atPath: target.path)
                }.value
                guard valid else { throw LanguageServiceFailure("入口不存在或指向包外，请检查运行配置") }
                guard self.sessionID == id, !Task.isCancelled else { return }
                try await session.start(
                    executable: sdk.flutter!, arguments: ["debug_adapter"], directory: root,
                    launch: configuration.launchArguments(root: root, debug: debug),
                    breakpoints: self.breakpointStore.persisted)
                guard self.sessionID == id else { return }
                guard self.state.phase != .ended else { return }
                self.status = "Flutter 会话已启动"
                self.syncAllBreakpoints()
            } catch {
                guard self.sessionID == id else { return }
                self.status = error.localizedDescription
                self.sessionFailure = error.localizedDescription
                self.appendOutput(error.localizedDescription + "\n")
                self.state.receive(JSONValue(["event": "terminated"]))
                await session.stop()
            }
            withExtendedLifetime(access) {}
        }
    }
    @discardableResult func stop() -> Task<Void, Never> {
        let old = cleanup
        sessionID = UUID()
        state.stopping()
        controlsBusy = false
        inspectorBusy = false
        pendingReload = false
        inspectorGeneration = UUID()
        variableTicket = UUID()
        evaluationTicket = UUID()
        let operation = operation
        let commandTask = commandTask
        operation?.cancel()
        listener?.cancel()
        breakpointTail?.cancel()
        reload?.cancel()
        commandTask?.cancel()
        flush?.cancel()
        flush = nil
        pendingOutput = ""
        let session = session
        let command = command
        let access = access
        self.session = nil
        self.command = nil
        commandRunning = false
        self.operation = nil
        listener = nil
        self.commandTask = nil
        breakpointTail = nil
        reload = nil
        frames = []
        scopes = []
        variables = []
        threads = []
        widgets = []
        selectedFrame = nil
        isolate = ""
        let cleanup = Task { [weak self] in
            async let a: Void = session?.stop() ?? ()
            async let b: Void = command?.stop() ?? ()
            _ = await (a, b)
            await operation?.value
            await commandTask?.value
            await old?.value
            withExtendedLifetime(access) {}
            if self?.session == nil { self?.state.receive(JSONValue(["event": "terminated"])) }
        }
        self.cleanup = cleanup
        return cleanup
    }
    private func receive(_ event: JSONValue) {
        if event["method"].string == "hycode/stderr" {
            appendOutput(event["params"]["message"].string ?? "")
            return
        }
        let name = event["event"].string
        state.receive(event)
        switch name {
        case "output": appendOutput(event["body"]["output"].string ?? "")
        case "stopped":
            if state.phase == .paused {
                section = .debugger
                onReveal?()
            }
            status = "已暂停 · " + (event["body"]["reason"].string ?? "断点")
            refreshStack()
        case "continued", "flutter.appStarted":
            variableTicket = UUID()
            evaluationTicket = UUID()
            status = "运行中"
            frames = []
            scopes = []
            variables = []
            selectedFrame = nil
            onBreakpointsChanged?()
        case "dart.serviceExtensionAdded":
            if let id = event["body"]["isolateId"].string, id != isolate {
                inspectorGeneration = UUID()
                widgets = []
                inspectorBusy = false
                isolate = id
            }
        case "terminated", "hycode/disconnected":
            variableTicket = UUID()
            evaluationTicket = UUID()
            pendingReload = false
            status = sessionFailure ?? ("会话已结束" + (state.exitCode.map { " · 退出码 \($0)" } ?? ""))
            controlsBusy = false
            isolate = ""
            widgets = []
            inspectorGeneration = UUID()
            frames = []
            scopes = []
            variables = []
            selectedFrame = nil
            onBreakpointsChanged?()
            let session = session
            Task { await session?.stop() }
        case "hycode/breakpoints":
            verified = [:]
            for entry in event["body"].array {
                guard let path = entry["path"].string, !breakpointStore.dirty.contains(path),
                    entry["verified"] == .bool(true), let actual = entry["actual"].int, actual > 0, actual <= 10_000_000
                else { continue }
                verified[path, default: []].insert(actual)
                if let requested = entry["requested"].int, requested != actual,
                    var values = breakpoints[path], let index = values.firstIndex(where: { $0.line == requested }),
                    !values.contains(where: { $0.line == actual })
                {
                    values[index].line = actual
                    breakpointStore.set(values, path: path)
                }
            }
            persist()
            onBreakpointsChanged?()
        default: break
        }
    }
    private func appendOutput(_ text: String) {
        pendingOutput = String((pendingOutput + text).suffix(262_144))
        guard flush == nil else { return }
        flush = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self else { return }
            self.output = String((self.output + self.pendingOutput).suffix(262_144))
            self.pendingOutput = ""
            self.flush = nil
        }
    }
    func control(_ name: String) {
        guard let session, !controlsBusy, active else { return }
        controlsBusy = true
        let id = sessionID
        let thread = state.threadID ?? threads.first?["id"].int
        Task { [weak self] in
            guard let self else { return }
            defer {
                if self.sessionID == id {
                    self.controlsBusy = false
                    self.scheduleReload()
                }
            }
            do {
                if name == "hotReload" || name == "hotRestart" {
                    guard await self.prepareRun?() == true, self.sessionID == id else { return }
                    if name == "hotRestart" {
                        self.inspectorGeneration = UUID()
                        self.widgets = []
                        self.isolate = ""
                        self.inspectorBusy = false
                    }
                    _ = try await session.request(name, JSONValue(["reason": "manual"]), timeout: 120)
                } else {
                    var target = thread
                    if name == "pause", target == nil {
                        let result = try await session.request("threads")
                        target = result["threads"].array.first?["id"].int
                    }
                    guard let target else { throw LanguageServiceFailure("没有可用的线程") }
                    _ = try await session.request(name, JSONValue(["threadId": target]))
                }
            } catch { if self.sessionID == id { self.status = error.localizedDescription } }
        }
    }
    func saved(uri: String) {
        guard launch.hotReloadOnSave, active, launch.mode == .debug, let root = runningRoot,
            URL(string: uri)?.path.hasPrefix(root.path + "/") == true
        else { return }
        pendingReload = true
        scheduleReload()
    }
    private func scheduleReload() {
        guard pendingReload, canReload else { return }
        reload?.cancel()
        reload = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, self.pendingReload, self.canReload else { return }
            self.pendingReload = false
            self.control("hotReload")
        }
    }
    func toggleBreakpoint(path: String, line: Int) {
        guard let access, path.hasPrefix(access.url.path + "/"), line > 0 else { return }
        var values = breakpoints[path] ?? []
        if let index = values.firstIndex(where: { $0.line == line }) {
            values.remove(at: index)
        } else {
            guard breakpoints.values.reduce(0, { $0 + $1.count }) < 1_000 else { return }
            values.append(FlutterBreakpoint(line: line))
        }
        breakpointStore.set(values, path: path)
        persist()
        onBreakpointsChanged?()
        syncBreakpoints(path)
    }
    func updateBreakpoint(path: String, value: FlutterBreakpoint) {
        guard value.condition.count <= 4_096, value.logMessage.count <= 4_096,
            let index = breakpoints[path]?.firstIndex(where: { $0.line == value.line })
        else { return }
        var values = breakpoints[path] ?? []
        values[index] = value
        breakpointStore.set(values, path: path)
        persist()
        onBreakpointsChanged?()
        syncBreakpoints(path)
    }
    func sourceEdited(uri: String, range: LSPRange, text: String) {
        guard let path = URL(string: uri)?.path else { return }
        breakpointStore.edit(path: path, range: range, text: text)
        verified[path] = nil
        onBreakpointsChanged?()
        // The debugger sees disk sources. Resubmit relocated lines after save;
        // unsaved editing never triggers a build/reload by itself.
    }
    func sourceClosed(uri: String) {
        guard let path = URL(string: uri)?.path else { return }
        breakpointStore.discard(path: path)
        onBreakpointsChanged?()
    }
    func sourceSaved(uri: String, snapshot: [FlutterBreakpoint], clean: Bool) {
        if let path = URL(string: uri)?.path {
            breakpointStore.saved(path: path, snapshot: snapshot, clean: clean)
            persist()
            syncBreakpoints(path)
        }
        saved(uri: uri)
    }
    private func syncAllBreakpoints() { for path in breakpoints.keys { syncBreakpoints(path) } }
    private func syncBreakpoints(_ path: String) {
        guard let session, !breakpointStore.dirty.contains(path), state.phase == .running || state.phase == .paused
        else { return }
        let previous = breakpointTail
        let id = sessionID
        let values = breakpoints[path] ?? []
        let ticket = UUID()
        breakpointTickets[path] = ticket
        breakpointTail = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.sessionID == id, self?.breakpointTickets[path] == ticket else { return }
            do {
                _ = try await session.setBreakpoints(path: path, values: values)
                guard let self, self.sessionID == id, self.breakpointTickets[path] == ticket else { return }
                self.onBreakpointsChanged?()
            } catch { if self?.sessionID == id { self?.status = error.localizedDescription } }
        }
    }
    func refreshStack() {
        guard let session, state.phase == .paused else { return }
        let id = sessionID
        let epoch = state.epoch
        Task { [weak self] in
            do {
                let result = try await session.request("threads")
                guard let self, self.sessionID == id, self.state.epoch == epoch else { return }
                self.threads = Array(result["threads"].array.prefix(200))
                let thread = self.state.threadID ?? self.threads.first?["id"].int
                guard let thread else { return }
                let stack = try await session.request(
                    "stackTrace", JSONValue(["threadId": thread, "startFrame": 0, "levels": 100]))
                guard self.sessionID == id, self.state.epoch == epoch else { return }
                self.frames = Array(stack["stackFrames"].array.prefix(100))
                if let frame = self.frames.first { self.selectFrame(frame) }
            } catch {
                if self?.sessionID == id, self?.state.epoch == epoch { self?.status = error.localizedDescription }
            }
        }
    }
    func selectFrame(_ frame: JSONValue) {
        guard let session, let frameID = frame["id"].int else { return }
        selectedFrame = frameID
        variables = []
        scopes = []
        variableTicket = UUID()
        evaluationTicket = UUID()
        let id = sessionID
        let epoch = state.epoch
        if let path = frame["source"]["path"].string, path.hasPrefix("/") {
            let position = LSPPosition(
                line: max(0, (frame["line"].int ?? 1) - 1), character: max(0, (frame["column"].int ?? 1) - 1))
            onNavigate?(
                LSPLocation(
                    uri: URL(fileURLWithPath: path).absoluteString, range: LSPRange(start: position, end: position)))
        }
        onBreakpointsChanged?()
        Task { [weak self] in
            do {
                let result = try await session.request("scopes", JSONValue(["frameId": frameID]))
                guard let self, self.sessionID == id, self.state.epoch == epoch, self.selectedFrame == frameID else {
                    return
                }
                self.scopes = Array(result["scopes"].array.prefix(100))
                if let reference = self.scopes.first?["variablesReference"].int { self.loadVariables(reference) }
            } catch {
                if self?.sessionID == id, self?.state.epoch == epoch, self?.selectedFrame == frameID {
                    self?.status = error.localizedDescription
                }
            }
        }
    }
    func loadVariables(_ reference: Int) {
        guard let session, state.phase == .paused, reference > 0 else { return }
        let id = sessionID
        let epoch = state.epoch
        let frame = selectedFrame
        let ticket = UUID()
        variableTicket = ticket
        Task { [weak self] in
            do {
                let result = try await session.request(
                    "variables", JSONValue(["variablesReference": reference, "start": 0, "count": 200]))
                guard let self, self.sessionID == id, self.state.epoch == epoch, self.selectedFrame == frame,
                    self.variableTicket == ticket
                else { return }
                self.variables = Array(result["variables"].array.prefix(200))
            } catch {
                if self?.sessionID == id, self?.state.epoch == epoch, self?.selectedFrame == frame,
                    self?.variableTicket == ticket
                {
                    self?.status = error.localizedDescription
                }
            }
        }
    }
    func evaluate() {
        guard let session, state.phase == .paused, let selectedFrame, !expression.isEmpty, expression.count <= 4_096
        else { return }
        let id = sessionID
        let epoch = state.epoch
        let expression = expression
        let ticket = UUID()
        evaluationTicket = ticket
        Task { [weak self] in
            do {
                let result = try await session.request(
                    "evaluate", JSONValue(["expression": expression, "frameId": selectedFrame, "context": "repl"]))
                guard let self, self.sessionID == id, self.state.epoch == epoch, self.selectedFrame == selectedFrame,
                    self.evaluationTicket == ticket
                else { return }
                self.evaluation = String((result["result"].string ?? "无结果").prefix(16_384))
            } catch {
                if self?.sessionID == id, self?.state.epoch == epoch, self?.selectedFrame == selectedFrame,
                    self?.evaluationTicket == ticket
                {
                    self?.evaluation = error.localizedDescription
                }
            }
        }
    }
    func refreshInspector() {
        guard let session, canInspect, !inspectorBusy else { return }
        inspectorBusy = true
        widgets = []
        let id = sessionID
        let isolate = isolate
        let group = inspectorGroup
        let generation = inspectorGeneration
        Task { [weak self] in
            defer { if self?.sessionID == id, self?.inspectorGeneration == generation { self?.inspectorBusy = false } }
            do {
                _ = try? await session.request(
                    "callService",
                    JSONValue([
                        "method": "ext.flutter.inspector.disposeGroup",
                        "params": ["isolateId": isolate, "objectGroup": group],
                    ]))
                let result = try await session.request(
                    "callService",
                    JSONValue([
                        "method": "ext.flutter.inspector.getRootWidgetSummaryTree",
                        "params": ["isolateId": isolate, "objectGroup": group],
                    ]))
                let rows = await Task.detached(priority: .utility) {
                    FlutterInspectorTree.rows(result, generation: generation)
                }.value
                guard let self, self.sessionID == id, self.isolate == isolate, self.inspectorGeneration == generation
                else { return }
                self.widgets = rows
            } catch {
                if self?.sessionID == id, self?.inspectorGeneration == generation {
                    self?.status = error.localizedDescription
                }
            }
        }
    }
    func selectWidget(_ row: FlutterInspectorTree.Row) {
        guard row.generation == inspectorGeneration else { return }
        if let source = row.source { onNavigate?(source) }
        guard let session, !row.valueID.isEmpty, !isolate.isEmpty else { return }
        let isolate = isolate
        let group = inspectorGroup
        Task {
            _ = try? await session.request(
                "callService",
                JSONValue([
                    "method": "ext.flutter.inspector.setSelectionById",
                    "params": ["isolateId": isolate, "arg": row.valueID, "objectGroup": group],
                ]))
        }
    }
}

extension FlutterWorkspaceController {
    /// Explicit tool actions only. No emulator startup or browser launch is
    /// hidden in device discovery. Build/test deliberately omit implicit Pub.
    func runCommand(_ kind: String) {
        guard !active, !commandRunning, executionAllowed?() == true,
            let sdk, let executable = sdk.flutter, let access
        else { return }
        let root = project?.root ?? access.url
        let isTest = kind == "test"
        let arguments: [String]
        switch kind {
        case "devices": arguments = ["devices", "--machine"]
        case "doctor": arguments = ["doctor", "-v"]
        case "test":
            guard project?.isFlutter == true, !testPath.hasPrefix("/"), !testPath.hasPrefix("-"),
                !testPath.split(separator: "/").contains(".."), testPath.count <= 1_024, !testPath.contains("\0")
            else { return }
            arguments =
                ["test", "--machine", "--no-pub"] + (coverage ? ["--coverage"] : [])
                + (testPath.isEmpty ? [] : [testPath])
        case "build":
            guard project?.isFlutter == true, ["macos", "ios", "apk", "appbundle", "web"].contains(buildTarget),
                (try? launch.validate()) != nil
            else { return }
            // Device selection is a run option, not a build target flag.
            var build = launch
            build.deviceID = ""
            arguments = ["build", buildTarget, "--target", build.program] + ((try? build.toolArguments()) ?? [])
        default: return
        }
        commandRunning = true
        section = .initialSection(for: kind)
        sessionTitle = kind == "test" ? "Flutter Test" : "Flutter \(kind)"
        let oldSession = session
        let oldOperation = operation
        let previousCleanup = cleanup
        listener?.cancel()
        listener = nil
        session = nil
        operation = nil
        sessionID = UUID()
        sessionFailure = nil
        output = ""
        pendingOutput = ""
        tests = FlutterTestResults()
        status = "Flutter \(kind)…"
        onReveal?()
        let id = sessionID
        let command = DeveloperToolTask()
        self.command = command
        commandTask = Task { [weak self, access] in
            guard let self else { return }
            defer {
                if self.sessionID == id {
                    self.commandRunning = false
                    self.command = nil
                    self.commandTask = nil
                }
                withExtendedLifetime(access) {}
            }
            await oldSession?.stop()
            await oldOperation?.value
            await previousCleanup?.value
            guard self.sessionID == id, !Task.isCancelled else { return }
            if ["test", "build"].contains(kind), await self.prepareRun?() != true {
                if self.sessionID == id { self.status = "已取消：保存未完成" }
                return
            }
            guard self.sessionID == id, !Task.isCancelled else { return }
            do {
                let result = try await command.run(
                    executable: executable, arguments: arguments, directory: root,
                    standardOutput: { [weak self] text in
                        guard isTest else { return }
                        await self?.testOutput(text, id: id)
                    }
                ) { [weak self] text in
                    await self?.commandOutput(text, id: id)
                }
                guard self.sessionID == id else { return }
                self.status = "Flutter \(kind) · 退出码 \(result.exitCode)" + (result.truncated ? " · 输出已截断" : "")
                if kind == "devices", result.exitCode == 0 {
                    guard !result.truncated else { throw LanguageServiceFailure("设备 JSON 超出限制") }
                    self.devices = try FlutterDevice.parse(result.stdout)
                    if self.launch.deviceID.isEmpty, let first = self.devices.first { self.launch.deviceID = first.id }
                }
            } catch {
                if self.sessionID == id { self.status = error.localizedDescription }
            }
        }
    }
    private func commandOutput(_ text: String, id: UUID) {
        guard sessionID == id else { return }
        appendOutput(text)
    }
    private func testOutput(_ text: String, id: UUID) {
        guard sessionID == id else { return }
        tests.append(text)
    }
}
