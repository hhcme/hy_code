import AppKit
import HyCodeWorkspace
import Observation
import WebKit

@MainActor @Observable final class MarkupPreviewController: NSObject, WKNavigationDelegate {
    weak var document: EditorDocument?
    let format: MarkupFormat
    var mode = MarkupPreviewMode(rawValue: UserDefaults.standard.string(forKey: "markup.mode") ?? "split") ?? .split {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "markup.mode")
            configureBridge()
        }
    }
    var linkedScrolling = UserDefaults.standard.object(forKey: "markup.linkedScroll") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(linkedScrolling, forKey: "markup.linkedScroll")
            configureBridge()
        }
    }
    var supportsLinkedScrolling: Bool { document?.largeFile == nil }
    private(set) var hasPage = false
    private(set) var rendering = false
    private(set) var error: String?
    private(set) var resourceFailures = 0
    private(set) var browser: WKWebView?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var resources: MarkupResourceHandler?
    @ObservationIgnored private var renderCancellation: DocumentSaveCancellation?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loadToken = UUID().uuidString
    @ObservationIgnored private var dirty = true
    @ObservationIgnored private var active = false
    @ObservationIgnored private var dark = true
    @ObservationIgnored private var loadingNavigation: WKNavigation?
    @ObservationIgnored private var scrollObservation: NSObjectProtocol?
    @ObservationIgnored private var suppressNativeUntil = Date.distantPast
    @ObservationIgnored private var pendingScroll: (line: Int, fraction: Double)?
    @ObservationIgnored private var scrollInFlight = false
    @ObservationIgnored private var pageURL: URL?
    @ObservationIgnored private var previewPosition: (line: Int?, fraction: Double) = (nil, 0)
    init(document: EditorDocument, format: MarkupFormat) {
        self.document = document
        self.format = format
        super.init()
    }
    func activate(dark: Bool) {
        active = true
        let changed = self.dark != dark
        self.dark = dark
        guard mode != .source, let document else {
            suspend()
            return
        }
        if browser == nil, preparation == nil {
            rendering = true
            let ticket = generation
            preparation = Task { [weak self] in
                do {
                    let rules = try await MarkupNetworkPolicy.rules()
                    guard let self, !Task.isCancelled, self.generation == ticket, self.active,
                        self.mode != .source
                    else { return }
                    self.preparation = nil
                    self.rendering = false
                    self.makeBrowser(document: document, rules: rules)
                    self.schedule()
                } catch {
                    guard let self, !Task.isCancelled, self.generation == ticket else { return }
                    self.preparation = nil
                    self.rendering = false
                    self.error = MarkupPreviewFailure.preparation(error)
                }
            }
        }
        if changed { dirty = true }
        schedule()
    }
    private func makeBrowser(document: EditorDocument, rules: WKContentRuleList) {
        do {
            let path = document.readOnly ? document.sourceURL.lastPathComponent : document.path
            let policy = try MarkupResourcePolicy(path: path)
            let resources = MarkupResourceHandler(access: document.workspaceAccess, policy: policy)
            resources.failed = { [weak self] in self?.resourceFailures += 1 }
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(rules)
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.setURLSchemeHandler(resources, forURLScheme: "hycode-preview")
            let relay = MarkupMessageRelay()
            relay.owner = self
            configuration.userContentController.add(
                relay, contentWorld: MarkupPreviewBridge.world, name: MarkupPreviewBridge.name)
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: MarkupPreviewBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true,
                    in: MarkupPreviewBridge.world))
            let browser = WKWebView(frame: .zero, configuration: configuration)
            browser.navigationDelegate = self
            browser.allowsBackForwardNavigationGestures = false
            browser.setAccessibilityLabel("\(format == .markdown ? "Markdown" : "HTML") 只读预览")
            self.resources = resources
            self.browser = browser
            if let scroll = document.editor?.scroll {
                scrollObservation = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.sourceScrolled() }
                }
            }
            dirty = true
        } catch { self.error = error.localizedDescription }
    }
    func edited() {
        renderCancellation?.cancel()
        dirty = true
        schedule()
    }
    func refresh() {
        dirty = true
        if browser == nil { activate(dark: dark) } else { schedule() }
    }
    private func schedule() {
        guard active, browser != nil, worker == nil, dirty, let document, !document.composing, !document.closing,
            !document.closed
        else { return }
        let ticket = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == ticket {
                    self.worker = nil
                    self.rendering = false
                    self.schedule()
                }
            }
            while self.active && self.dirty && !Task.isCancelled {
                var attemptedRevision: UInt64?
                do {
                    try await Task.sleep(for: .milliseconds(document.largeFile == nil ? 180 : 1_000))
                    guard self.generation == ticket, !document.composing, !document.closing else { return }
                    let revision = document.edits.revision
                    attemptedRevision = revision
                    self.dirty = false
                    self.rendering = true
                    let cancellation = DocumentSaveCancellation()
                    self.renderCancellation = cancellation
                    let content = try await document.markup(
                        revision: revision, markdown: self.format == .markdown, cancellation: cancellation)
                    guard !Task.isCancelled, self.generation == ticket, self.active, !document.composing else { return }
                    guard document.edits.revision == revision else {
                        self.dirty = true
                        continue
                    }
                    let dark = self.dark
                    let page = try await Task.detached(priority: .utility) {
                        try Task.checkCancellation()
                        return MarkupPage.document(content, dark: dark)
                    }.value
                    guard !Task.isCancelled, self.generation == ticket, document.edits.revision == revision,
                        self.dark == dark
                    else {
                        self.dirty = true
                        continue
                    }
                    let path = document.readOnly ? document.sourceURL.lastPathComponent : document.path
                    let policy = try MarkupResourcePolicy(path: path)
                    self.resources?.reset(policy)
                    self.resourceFailures = 0
                    self.loadToken = UUID().uuidString
                    self.pendingScroll = nil
                    self.scrollInFlight = false
                    self.pageURL = policy.baseURL
                    self.loadingNavigation = self.browser?.loadHTMLString(page, baseURL: policy.baseURL)
                    self.error = nil
                } catch is CancellationError {
                    if !Task.isCancelled, self.generation == ticket, self.dirty { continue }
                    return
                } catch {
                    guard self.generation == ticket else { return }
                    if self.dirty || attemptedRevision.map({ $0 != document.edits.revision }) == true {
                        self.dirty = true
                        continue
                    }
                    self.error = error.localizedDescription
                    self.dirty = false
                }
            }
        }
    }
    func deactivate() {
        active = false
        suspend()
    }
    private func suspend() {
        generation = UUID()
        renderCancellation?.cancel()
        renderCancellation = nil
        worker?.cancel()
        worker = nil
        preparation?.cancel()
        preparation = nil
        rendering = false
        resources?.cancel()
        browser?.stopLoading()
        browser?.navigationDelegate = nil
        browser?.configuration.userContentController.removeScriptMessageHandler(
            forName: MarkupPreviewBridge.name, contentWorld: MarkupPreviewBridge.world)
        browser = nil
        hasPage = false
        resources = nil
        loadingNavigation = nil
        pendingScroll = nil
        scrollInFlight = false
        pageURL = nil
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation) }
        scrollObservation = nil
        dirty = true
    }
    private func configureBridge() {
        browser?.callAsyncJavaScript(
            "globalThis.hycodePreviewConfigure(token, active)",
            arguments: ["token": loadToken, "active": mode != .source], in: nil,
            in: MarkupPreviewBridge.world, completionHandler: nil)
    }
    private func sourceScrolled() {
        guard active, supportsLinkedScrolling, mode == .split, linkedScrolling, Date() >= suppressNativeUntil,
            loadingNavigation == nil,
            let editor = document?.editor
        else { return }
        pendingScroll = editor.previewScrollPosition()
        if let pendingScroll { previewPosition = (pendingScroll.line, pendingScroll.fraction) }
        sendScroll()
    }
    private func sendScroll() {
        guard active, !scrollInFlight, let top = pendingScroll, let browser else { return }
        pendingScroll = nil
        scrollInFlight = true
        let token = loadToken
        browser.callAsyncJavaScript(
            "globalThis.hycodePreviewScroll(line, fraction, markdown)",
            arguments: ["line": top.line, "fraction": top.fraction, "markdown": format == .markdown], in: nil,
            in: MarkupPreviewBridge.world
        ) { [weak self] _ in
            guard let self, self.loadToken == token else { return }
            self.scrollInFlight = false
            self.sendScroll()
        }
    }
    func received(_ message: WKScriptMessage) {
        guard active, message.name == MarkupPreviewBridge.name, message.frameInfo.isMainFrame,
            let body = message.body as? [String: Any], body["token"] as? String == loadToken,
            let fraction = body["fraction"] as? Double, fraction.isFinite, let editor = document?.editor
        else { return }
        let line =
            format == .markdown
            ? MarkupScrollMapping.line(body["line"] as? Double, count: editor.presentation?.gutter.lines.count ?? 1)
            : nil
        previewPosition = (line, MarkupScrollMapping.fraction(fraction))
        guard supportsLinkedScrolling, linkedScrolling, mode == .split else { return }
        suppressNativeUntil = Date().addingTimeInterval(0.3)
        editor.scrollPreview(to: line, fraction: MarkupScrollMapping.fraction(fraction))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active, webView === browser, navigation === loadingNavigation else { return }
        loadingNavigation = nil
        hasPage = true
        configureBridge()
        if linkedScrolling, mode == .split {
            sourceScrolled()
        } else {
            pendingScroll = (previewPosition.line ?? -1, previewPosition.fraction)
            sendScroll()
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard active, webView === browser, navigation === loadingNavigation else { return }
        loadingNavigation = nil
        self.error = error.localizedDescription
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard active, webView === browser else { return }
        error = "预览进程已退出，可重新载入"
    }
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        // Initial loadHTMLString and same-document anchors only. No browser,
        // downloads, file URLs, forms, remote navigation or child frames.
        let url = navigationAction.request.url
        let initial =
            loadingNavigation != nil && navigationAction.navigationType == .other
            && navigationAction.targetFrame?.isMainFrame == true
            && (url?.absoluteString == "about:blank" || url == pageURL)
        let anchor =
            navigationAction.navigationType == .linkActivated && url?.fragment != nil
            && url?.deletingLastPathComponent() == webView.url?.deletingLastPathComponent()
            && url?.path == webView.url?.path
        decisionHandler(initial || anchor ? .allow : .cancel)
    }
}
