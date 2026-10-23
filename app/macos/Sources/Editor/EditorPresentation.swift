import AppKit
import HyCodeWorkspace

/// View-only line/syntax state. Temporary layout attributes never change text,
/// the native undo history or the Rust revision. Requests are scoped to this view
/// and document revision. Scrolling joins one worker; edits and teardown cancel.
@MainActor final class EditorPresentation: NSObject {
    weak var document: EditorDocument?
    private weak var textView: NSTextView?
    private weak var scroll: NSScrollView?
    let gutter: EditorLineRuler
    private var task: Task<Void, Never>?
    private var viewport = SyntaxViewportState()
    private let fragmentWorker = SyntaxFragmentWorker()
    private var enabled = true
    private var dark: Bool?
    init(document: EditorDocument, scroll: NSScrollView, textView: NSTextView, lines: TextLineIndex) {
        self.document = document
        self.scroll = scroll
        self.textView = textView
        gutter = EditorLineRuler(scroll: scroll, textView: textView, lines: lines)
        super.init()
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        schedule()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func cancel() {
        document?.semantic?.dismissHover()
        task?.cancel()
        task = nil
        viewport.cancel()
    }
    func configure(lineNumbers: Bool, syntaxHighlight: Bool) {
        if scroll?.rulersVisible != lineNumbers { scroll?.rulersVisible = lineNumbers }
        if enabled != syntaxHighlight {
            enabled = syntaxHighlight
            clearColors()
            if enabled { schedule() } else { cancel() }
            document?.syntaxNotice = enabled ? nil : "已关闭语法高亮"
        }
    }
    func willReplace(_ change: TextLineChange) {
        clearColors()
        gutter.lines.apply(change)
        gutter.updateThickness()
        gutter.needsDisplay = true
    }
    func replacePage(lines: TextLineIndex) {
        clearColors()
        gutter.lines = lines
        gutter.updateThickness()
        gutter.needsDisplay = true
    }
    func selectionChanged() { gutter.needsDisplay = true }
    @objc private func scrolled(_ notification: Notification) {
        document?.semantic?.dismissHover()
        gutter.needsDisplay = true
        schedule(delay: 16)
    }
    func appearanceChanged() {
        let isDark = textView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard dark != isDark else { return }
        document?.semantic?.dismissHover()
        dark = isDark
        gutter.needsDisplay = true
        clearColors()
        schedule()
    }
    func schedule(delay: Int = 0) {
        guard enabled, scroll?.window != nil, let ticket = viewport.beginUpdates() else { return }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
            await self?.updateHighlights(ticket: ticket)
        }
    }
    private func updateHighlights(ticket: UUID) async {
        defer {
            if viewport.accepts(ticket) {
                viewport.finish(ticket)
                task = nil
            }
        }
        while !Task.isCancelled && viewport.accepts(ticket) {
            guard let document, let textView,
                textView.window != nil, !document.composing, !document.closing,
                let chars = visibleRange(in: textView), let source = textView.textStorage?.mutableString
            else { return }
            guard !viewport.covers(chars),
                let range = SyntaxViewportState.requestRange(for: chars, source: source)
            else { return }
            let revision = document.edits.revision
            do {
                let snapshot = try await highlight(document: document, range: range, visible: chars, revision: revision)
                guard !Task.isCancelled, viewport.accepts(ticket), document.edits.revision == revision,
                    !document.composing
                else { return }
                apply(snapshot)
                document.syntaxLanguage = snapshot.language
                document.syntaxNotice = snapshot.status == "windowed" ? "大文件按可见片段高亮" : nil
            } catch {
                guard !Task.isCancelled, viewport.accepts(ticket) else { return }
                document.syntaxNotice = error.localizedDescription
                guard let latest = visibleRange(in: textView), viewport.needsUpdate(after: chars, latest: latest)
                else { return }
            }
            // Keep a completed result even if scrolling advanced meanwhile. The
            // next iteration reads the latest viewport, never an event backlog.
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        }
    }
    private func visibleRange(in textView: NSTextView) -> NSRange? {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        var rect = textView.visibleRect
        rect.origin.x -= textView.textContainerOrigin.x
        rect.origin.y -= textView.textContainerOrigin.y
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        return layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }
    private func highlight(document: EditorDocument, range: NSRange, visible: NSRange, revision: UInt64) async throws
        -> SyntaxHighlight
    {
        if document.largeFile != nil {
            do { return try await highlightFragment(range: range, path: document.path) } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard range != visible else { throw error }
                return try await highlightFragment(range: visible, path: document.path)
            }
        }
        do { return try await document.syntax(range: range, revision: revision) } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Dense tokens may exhaust the read-ahead budget; the visible area
            // still gets its own attempt without clearing any earlier colors.
            guard range != visible else { throw error }
            return try await document.syntax(range: visible, revision: revision)
        }
    }
    private func highlightFragment(range: NSRange, path: String) async throws -> SyntaxHighlight {
        guard let source = textView?.textStorage?.mutableString, range.location <= source.length,
            range.length <= source.length - range.location
        else {
            throw CancellationError()
        }
        let text = source.substring(with: range)
        return try await fragmentWorker.highlight(text: text, path: path, start: range.location)
    }
    private func clearColors() {
        cancel()
        for range in viewport.reset() { removeColors(in: range) }
    }
    private func removeColors(in range: NSRange) {
        guard let textView, let layout = textView.layoutManager else { return }
        let length = textView.textStorage?.length ?? 0
        if range.location <= length {
            layout.removeTemporaryAttribute(
                .foregroundColor,
                forCharacterRange: NSRange(
                    location: range.location, length: min(range.length, length - range.location)))
        }
    }
    private func apply(_ snapshot: SyntaxHighlight) {
        guard let textView, textView.window != nil, let layout = textView.layoutManager else { return }
        let length = textView.textStorage?.length ?? 0
        guard snapshot.start >= 0, snapshot.length >= 0, snapshot.start <= length,
            snapshot.length <= length - snapshot.start
        else { return }
        let painted = NSRange(location: snapshot.start, length: snapshot.length)
        for range in viewport.record(painted) { removeColors(in: range) }
        removeColors(in: painted)
        for span in snapshot.spans {
            guard span.start >= painted.location, span.length > 0, span.start <= NSMaxRange(painted),
                span.length <= NSMaxRange(painted) - span.start
            else { continue }
            layout.addTemporaryAttribute(
                .foregroundColor, value: SyntaxPalette.color(span.style, dark: dark ?? true),
                forCharacterRange: span.range)
        }
    }
}

private enum SyntaxPalette {
    static func color(_ capture: String, dark: Bool) -> NSColor {
        let name = capture.split(separator: ".").first.map(String.init) ?? capture
        let hex: UInt32
        switch name {
        case "comment": hex = dark ? 0x7f8993 : 0x71806b
        case "keyword", "conditional", "repeat", "exception", "include": hex = dark ? 0xcf8e6d : 0x8b3a85
        case "string", "character": hex = dark ? 0x6aab73 : 0x397b40
        case "number", "float", "boolean", "constant": hex = dark ? 0x2aacb8 : 0x176b91
        case "function", "method": hex = dark ? 0x56a8f5 : 0x1759a6
        case "type", "constructor": hex = dark ? 0xc4b6e6 : 0x6f42a6
        case "property", "attribute", "tag": hex = dark ? 0xc77dbb : 0x8b427d
        default: return WorkbenchColors.nativeText
        }
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
