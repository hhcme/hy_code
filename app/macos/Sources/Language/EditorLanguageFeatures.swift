import AppKit
import HyCodeWorkspace
import SwiftUI

@MainActor final class EditorLanguageFeatures: NSObject {
    weak var document: EditorDocument?
    private(set) weak var controller: (any EditorLanguageController)?
    let uri: String
    private(set) var lines: TextLineIndex
    var version: Int { Int(document?.edits.revision ?? 0) }
    private var pending: (LSPRange, String)?
    let semanticMenu = WorkbenchContextMenu()
    let informationPopup = WorkbenchInformationPopup()
    private var underlines: [NSRange] = []
    private var diagnostics: [LSPDiagnostic] = []
    private var snippetSession = LSPSnippetSession(ranges: [])
    private(set) lazy var hoverInteraction = DartHoverController(feature: self)
    init(document: EditorDocument, controller: any EditorLanguageController, content: TextDocumentContent) {
        self.document = document
        self.controller = controller
        uri = document.sourceURL.absoluteString
        lines = content.protocolLineIndex
        super.init()
        controller.opened(self, text: content.text)
    }
    func reopen() {
        semanticMenu.hide()
        informationPopup.hide()
        hoverInteraction.invalidate()
        guard let text = document?.editor?.textView.string else { return }
        clearDiagnostics()
        controller?.opened(self, text: text)
    }
    func willReplace(change: TextLineChange, protocolChange: LSPDocumentChange?) {
        if let protocolChange {
            snippetSession.replace(protocolChange.range, count: protocolChange.text.utf16.count)
        } else {
            snippetSession = LSPSnippetSession(ranges: [])
        }
        semanticMenu.hide()
        informationPopup.hide()
        hoverInteraction.invalidate()
        clearDiagnostics()
        pending = protocolChange.map {
            (LSPRange(start: .at($0.range.location, in: lines), end: .at(NSMaxRange($0.range), in: lines)), $0.text)
        }
        if let pending { controller?.flutter?.sourceEdited(uri: uri, range: pending.0, text: pending.1) }
        lines.apply(change)
    }
    func didReplace() {
        guard let pending else { return }
        self.pending = nil
        controller?.changed(uri: uri, range: pending.0, text: pending.1, version: version)
    }
    func close() {
        semanticMenu.hide()
        informationPopup.hide()
        hoverInteraction.invalidate()
        controller?.flutter?.sourceClosed(uri: uri)
        controller?.closed(uri: uri)
    }
    func breakpointSnapshot() -> [FlutterBreakpoint] {
        controller?.flutter?.breakpoints[document?.sourceURL.path ?? ""] ?? []
    }
    func saved(breakpoints: [FlutterBreakpoint]) {
        controller?.saved(uri: uri)
        controller?.flutter?.sourceSaved(uri: uri, snapshot: breakpoints, clean: document?.isDirty == false)
    }
    func setDiagnostics(_ diagnostics: [LSPDiagnostic]) {
        clearDiagnostics()
        self.diagnostics = diagnostics
        guard document?.composing == false else { return }
        guard let view = document?.editor?.textView, let source = view.textStorage?.mutableString,
            let layout = view.layoutManager
        else { return }
        for item in diagnostics {
            guard let range = item.range.range(in: lines, source: source), range.length > 0 else { continue }
            layout.addTemporaryAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: item.severity == 1 ? NSColor.systemRed : NSColor.systemOrange,
                ], forCharacterRange: range)
            underlines.append(range)
        }
        hoverInteraction.restoreLink()
    }
    func diagnosticMessages(at offset: Int) -> String {
        guard let source = document?.editor?.textView.textStorage?.mutableString else { return "" }
        return String(
            diagnostics.filter { item in
                guard let range = item.range.range(in: lines, source: source) else { return false }
                return NSLocationInRange(offset, range)
            }.map(\.message).joined(separator: "\n").prefix(2_000))
    }
    func diagnosticContext(line: Int) -> [JSONValue] {
        diagnostics.filter { $0.range.start.line <= line && $0.range.end.line >= line }.map(\.raw)
    }
    func restoreDiagnosticUnderline(in restored: NSRange) {
        guard let view = document?.editor?.textView, let source = view.textStorage?.mutableString else { return }
        for item in diagnostics {
            guard let range = item.range.range(in: lines, source: source) else { continue }
            let intersection = NSIntersectionRange(range, restored)
            if intersection.length > 0 {
                view.layoutManager?.addTemporaryAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                        .underlineColor: item.severity == 1 ? NSColor.systemRed : NSColor.systemOrange,
                    ], forCharacterRange: intersection)
            }
        }
    }
    func refreshDiagnostics() { setDiagnostics(diagnostics) }
    private func clearDiagnostics() {
        guard let view = document?.editor?.textView else { return }
        for range in underlines {
            view.layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: range)
            view.layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
        }
        underlines.removeAll()
        diagnostics.removeAll()
        hoverInteraction.restoreLink()
    }
    func dismissHover() { hoverInteraction.dismiss() }
    func hoverTarget(at offset: Int, in source: NSString) -> NSRange? {
        if document?.sourceURL.pathExtension.lowercased() == "dart",
            let range = DartDirectiveTarget.range(at: offset, in: source, lines: lines)
        {
            return range
        }
        return DartHoverTarget.range(at: offset, in: source)
    }
    func advanceSnippet(backward: Bool) -> Bool {
        guard document?.composing == false, let view = document?.editor?.textView,
            let selection = snippetSession.advance(backward: backward, selection: view.selectedRange())
        else { return false }
        view.setSelectedRange(selection)
        view.scrollRangeToVisible(selection)
        return true
    }
    @objc func definition() { navigate("textDocument/definition") }
    @objc func references() { navigate("textDocument/references") }
    @objc func structure() { controller?.showSymbols(self) }
    func navigate(_ method: String, at offset: Int? = nil) {
        let cached =
            (method == "textDocument/definition")
            ? hoverInteraction.cachedDefinition(at: offset ?? document?.editor?.textView.selectedRange().location ?? 0)
            : nil
        dismissHover()
        guard let view = document?.editor?.textView, let controller else { return }
        if let cached, !cached.isEmpty {
            controller.showLocations(cached, jumpIfSingle: true)
            return
        }
        let position = LSPPosition.at(offset ?? view.selectedRange().location, in: lines)
        let revision = version
        Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await controller.query(method, feature: self, position: position)
                guard self.version == revision else { return }
                controller.showLocations(
                    try LSPLocation.locations(result), jumpIfSingle: method != "textDocument/references")
            } catch { controller.report(error) }
        }
    }
    @objc func format() {
        guard let controller, document?.readOnly == false else { return }
        let revision = version
        Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await controller.query("textDocument/formatting", feature: self)
                if result == .null { return }
                try await self.apply(try result.decode([LSPTextEdit].self), revision: revision)
            } catch { controller.report(error) }
        }
    }
    func complete() {
        guard let view = document?.editor?.textView, let controller, document?.readOnly == false else { return }
        let selected = view.selectedRange()
        let revision = version
        let partial = view.rangeForUserCompletion
        Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await controller.query(
                    "textDocument/completion", feature: self, position: .at(selected.location, in: self.lines))
                guard self.version == revision, view.window != nil, view.selectedRange() == selected else { return }
                let values = result["items"].array.isEmpty ? result.array : result["items"].array
                var items: [WorkbenchContextCommand] = []
                for value in values.prefix(100) {
                    guard let label = value["label"].string else { continue }
                    let action = { [weak self] in
                        guard let self, self.version == revision else { return }
                        Task {
                            do {
                                let value = try await controller.resolveCompletion(value, feature: self)
                                guard self.version == revision, view.selectedRange() == selected else { return }
                                let fallback = LSPRange(
                                    start: .at(
                                        partial.location == NSNotFound ? selected.location : partial.location,
                                        in: self.lines),
                                    end: .at(
                                        partial.location == NSNotFound ? NSMaxRange(selected) : NSMaxRange(partial),
                                        in: self.lines))
                                let editRange =
                                    value["textEdit"]["range"] != .null
                                    ? value["textEdit"]["range"] : value["textEdit"]["insert"]
                                let range = (try? editRange.decode(LSPRange.self)) ?? fallback
                                let text = value["textEdit"]["newText"].string ?? value["insertText"].string ?? label
                                var edits = (try? value["additionalTextEdits"].decode([LSPTextEdit].self)) ?? []
                                let expanded = value["insertTextFormat"].int == 2 ? try LSPSnippet.expand(text) : nil
                                let primary = LSPTextEdit(range: range, newText: expanded?.text ?? text)
                                edits.append(primary)
                                try await self.apply(
                                    edits, revision: revision, primary: primary, stops: expanded?.stops ?? [])
                            } catch { controller.report(error) }
                        }
                    }
                    items.append(
                        WorkbenchContextCommand(title: label, help: value["detail"].string ?? "", action: action))
                }
                guard !items.isEmpty else { return }
                let rect = view.firstRect(forCharacterRange: selected, actualRange: nil)
                semanticMenu.show(items, at: rect.origin, in: view)

            } catch { controller.report(error) }
        }
    }
    private func apply(_ edits: [LSPTextEdit], revision: Int, primary: LSPTextEdit? = nil, stops: [NSRange] = [])
        async throws
    {
        guard !edits.isEmpty, let document, !document.readOnly, !document.composing,
            let view = document.editor?.textView, version == revision
        else { return }
        let text = view.string
        let previousOffset = view.selectedRange().location
        let result = try await Task.detached(priority: .utility) {
            let replacement = try LSPTextEdits.apply(edits, to: text)
            let offset =
                try primary.map {
                    try LSPTextEdits.completionOffset(primary: $0, additional: Array(edits.dropLast()), text: text)
                } ?? previousOffset
            return (replacement, min(max(0, offset), replacement.utf16.count))
        }.value
        guard version == revision, !document.composing, view.isEditable else { return }
        view.insertText(result.0, replacementRange: NSRange(location: 0, length: view.textStorage?.length ?? 0))
        guard version != revision else { return }
        let base = result.1 - (primary?.newText.utf16.count ?? 0)
        let absolute = stops.map { NSRange(location: max(0, base + $0.location), length: $0.length) }
        snippetSession = LSPSnippetSession(ranges: absolute)
        view.setSelectedRange(snippetSession.current ?? NSRange(location: result.1, length: 0))
        view.scrollRangeToVisible(view.selectedRange())
    }
    func reveal(_ range: LSPRange) {
        guard let view = document?.editor?.textView, let source = view.textStorage?.mutableString,
            let selection = range.range(in: lines, source: source)
        else { return }
        view.setSelectedRange(selection)
        view.scrollRangeToVisible(selection)
        view.window?.makeFirstResponder(view)
    }
}
