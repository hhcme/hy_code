import AppKit
import HyCodeWorkspace

/// View interaction owns no source text. One cancellable worker serves the
/// latest complete symbol; parsed docs and confirmed definitions are cached
/// only for the same workspace semantic context.
@MainActor final class DartHoverController: NSObject {
    private weak var feature: EditorLanguageFeatures?
    private var state = DartHoverState()
    private let presenter = DartHoverPresenter()
    private var worker: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var dismissalTicket = UUID()
    private var command = false
    private var navigationRange: NSRange?
    private weak var observedWindow: NSWindow?
    var linkChanged: ((NSRange?) -> Void)?
    private struct Presentation: Equatable {
        let range: NSRange
        let content: DartHoverContent
        let errors: String
        let navigable: Bool
    }
    private var presented: Presentation?
    init(feature: EditorLanguageFeatures) {
        self.feature = feature
        super.init()
        presenter.entered = { [weak self] in self?.cancelDismissal() }
        presenter.exited = { [weak self] in self?.pointerExitedEditor() }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else { return }
        NotificationCenter.default.removeObserver(self)
        observedWindow = window
        if let window {
            for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowChanged), name: name, object: window)
            }
        }
    }
    @objc private func windowChanged(_ note: Notification) { dismiss() }
    func invalidate() {
        observe(nil)
        state.reset(context: feature?.controller?.semanticRevision ?? 0)
        worker?.cancel()
        cancelDismissal()
        hideVisuals()
    }
    func dismiss() {
        observe(nil)
        state.move(to: nil)
        worker?.cancel()
        cancelDismissal()
        hideVisuals()
    }
    private func hideVisuals() {
        presenter.hide()
        presented = nil
        setLink(nil)
    }
    private func cancelDismissal() {
        dismissalTicket = UUID()
        dismissal?.cancel()
        dismissal = nil
    }
    func pointerExitedEditor() {
        state.move(to: nil)
        worker?.cancel()
        setLink(nil)
        guard dismissal == nil else { return }
        let ticket = UUID()
        dismissalTicket = ticket
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard let self, self.dismissalTicket == ticket else { return }
            self.dismissal = nil
            if !self.presenter.containsPointer { self.dismiss() }
        }
    }
    func move(at offset: Int?, command: Bool) {
        guard let feature, let document = feature.document, !document.closed, !document.composing,
            let view = document.editor?.textView, let source = view.textStorage?.mutableString,
            let offset, let range = feature.hoverTarget(at: offset, in: source)
        else {
            if presented != nil { pointerExitedEditor() } else { dismiss() }
            return
        }
        cancelDismissal()
        if state.context != feature.controller?.semanticRevision { invalidate() }
        observe(view.window)
        let expedite = command && !self.command && state.entry(for: range)?.content == nil
        self.command = command
        guard state.move(to: range, expedite: expedite) else { return }
        worker?.cancel()
        if presented?.range != range { hideVisuals() }
        if let cached = state.entry(for: range) {
            present(cached, range: range)
            if cached.content != nil && cached.definition != nil { return }
        }
        startWorker()
    }
    private enum Response: Sendable {
        case content(DartHoverContent)
        case definition(DartHoverDefinition)
        case failed
    }
    private func startWorker() {
        if let range = state.target, let cached = state.entry(for: range),
            cached.content != nil && cached.definition != nil
        {
            return
        }
        guard let feature, let controller = feature.controller, let request = state.begin() else { return }
        let revision = feature.version
        let position = LSPPosition.at(request.range.location, in: feature.lines)
        let delay = command ? 0 : 140
        worker = Task(priority: .utility) { [weak self, weak feature, weak controller] in
            guard let self else { return }
            defer {
                let next = self.state.finish(request)
                self.worker = nil
                if next { self.startWorker() }
            }
            guard let feature, let controller else { return }
            do {
                try await Task.sleep(for: .milliseconds(delay))
                try Task.checkCancellation()
            } catch { return }
            guard self.state.isCurrent(request), feature.version == revision,
                controller.semanticRevision == request.context
            else { return }
            var entry = self.state.entry(for: request.range) ?? DartHoverEntry()
            await withTaskGroup(of: Response.self) { group in
                if entry.content == nil {
                    group.addTask { [weak feature, weak controller] in
                        guard let feature, let controller else { return .failed }
                        do {
                            let result = try await controller.query(
                                "textDocument/hover", feature: feature, position: position)
                            return .content(DartHoverContent(contents: result["contents"]))
                        } catch { return .failed }
                    }
                }
                if entry.definition == nil {
                    group.addTask { [weak feature, weak controller] in
                        guard let feature, let controller else { return .failed }
                        do {
                            let result = try await controller.query(
                                "textDocument/definition", feature: feature, position: position)
                            let targets = try LSPLocation.locations(result).filter {
                                guard $0.uri.utf8.count <= 8_192, let url = URL(string: $0.uri) else { return false }
                                return url.isFileURL && (url.host == nil || url.host == "localhost")
                            }
                            return .definition(DartHoverDefinition(targets))
                        } catch { return .failed }
                    }
                }
                for await response in group {
                    guard !Task.isCancelled, feature.version == revision,
                        controller.semanticRevision == request.context
                    else {
                        group.cancelAll()
                        return
                    }
                    switch response {
                    case .content(let content): entry.content = content
                    case .definition(let definition): entry.definition = definition
                    case .failed: continue
                    }
                    self.state.store(entry, for: request)
                    if self.state.isCurrent(request) { self.present(entry, range: request.range) }
                }
            }
        }
    }
    private func present(_ entry: DartHoverEntry, range: NSRange) {
        guard state.target == range, let feature, let view = feature.document?.editor?.textView,
            view.window?.isKeyWindow == true, feature.document?.composing == false
        else { return }
        let navigable = entry.definition?.targets.isEmpty == false
        setLink(navigable ? range : nil)
        guard let content = entry.content else { return }
        let errors = feature.diagnosticMessages(at: range.location)
        guard !content.isEmpty || !errors.isEmpty else { return }
        let next = Presentation(range: range, content: content, errors: errors, navigable: navigable)
        guard presented != next else { return }
        presented = next
        presenter.show(
            content: content, errors: errors, range: range, in: view, canNavigate: navigable,
            definition: { [weak feature] in feature?.navigate("textDocument/definition", at: range.location) },
            references: { [weak feature] in feature?.navigate("textDocument/references", at: range.location) })
    }
    func cachedDefinition(at offset: Int) -> [LSPLocation]? {
        guard state.context == feature?.controller?.semanticRevision,
            let source = feature?.document?.editor?.textView.textStorage?.mutableString,
            let range = feature?.hoverTarget(at: offset, in: source),
            let value = state.entry(for: range)?.definition, value.complete
        else { return nil }
        return value.targets
    }
    private func setLink(_ range: NSRange?) {
        guard navigationRange != range else { return }
        if let old = navigationRange, let view = feature?.document?.editor?.textView,
            NSMaxRange(old) <= (view.textStorage?.length ?? 0)
        {
            view.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: old)
            view.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: old)
            feature?.restoreDiagnosticUnderline(in: old)
        }
        navigationRange = range
        restoreLink()
        linkChanged?(range)
    }
    func restoreLink() {
        guard let range = navigationRange, let view = feature?.document?.editor?.textView,
            NSMaxRange(range) <= (view.textStorage?.length ?? 0)
        else { return }
        view.layoutManager?.addTemporaryAttributes(
            [
                .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: WorkbenchColors.nativeAccent,
            ], forCharacterRange: range)
    }
}
