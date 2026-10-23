import AppKit
import HyCodeWorkspace
import SwiftUI

private struct DartHoverCard: View {
    let content: DartHoverContent
    let errors: String
    let width: CGFloat
    let expanded: Bool
    let more: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !content.signature.isEmpty {
                signature(content.signature).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            } else if !content.type.isEmpty {
                inline(content.type).lineLimit(2)
            }
            if !content.declaration.isEmpty || !content.documentation.isEmpty || !errors.isEmpty {
                Rectangle().fill(WorkbenchColors.tabBorder).frame(height: 1)
            }
            if expanded {
                ScrollView { details }.frame(height: 260).background(WorkbenchScrollStyle())
            } else {
                details
            }
        }
        .font(.system(size: 13)).foregroundStyle(WorkbenchColors.text)
        .padding(.trailing, 18).padding(12).frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .workbenchPopupSurface()
        .overlay(alignment: .bottomTrailing) {
            Button(action: more) {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 14, height: 16)
            }
            .buttonStyle(WorkbenchButtonStyle()).foregroundStyle(WorkbenchColors.secondary).padding(10)
            .help("跳转定义：中键 / ⌘点击 / ⌘B；查找引用：⇧⌘B")
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if expanded, content.signature.count > 160 {
                signature(content.signature).font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !content.declaration.isEmpty {
                inline(content.declaration).foregroundStyle(WorkbenchColors.secondary).lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !content.documentation.isEmpty {
                inline(content.documentation).lineLimit(expanded ? nil : 6).fixedSize(horizontal: false, vertical: true)
            }
            if !errors.isEmpty {
                Text(errors).foregroundStyle(.orange).lineLimit(expanded ? nil : 3).fixedSize(
                    horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func inline(_ text: String) -> Text {
        var value =
            (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        // Documentation is displayed locally. A Markdown URL is never an
        // executable/open-web action in this compact card.
        for run in value.runs {
            value[run.range].link = nil
            if run.inlinePresentationIntent?.contains(.code) == true {
                value[run.range].font = .system(size: 11.5, design: .monospaced)
                value[run.range].backgroundColor = WorkbenchColors.tabBorder.opacity(0.55)
            }
        }
        return Text(value)
    }
    private func signature(_ text: String) -> Text {
        guard
            let regex = try? NSRegularExpression(
                pattern:
                    #"\b(?:new|deprecated|void|dynamic|final|const|required|static|factory|abstract|covariant|late)\b|\b[A-Z][A-Za-z0-9_]*\b|"[^"\n]*"|'[^'\n]*'|\b[0-9]+\b"#
            )
        else { return Text(text) }
        let source = text as NSString
        var result = Text("")
        var offset = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result =
                result + Text(source.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            let token = source.substring(with: match.range)
            let color: Color =
                token.first?.isUppercase == true
                ? WorkbenchColors.accent
                : token.hasPrefix("\"") || token.hasPrefix("'") || token.first?.isNumber == true
                    ? Color(nsColor: WorkbenchColors.nativeCode) : .orange
            result = result + Text(token).foregroundColor(color)
            offset = NSMaxRange(match.range)
        }
        return result + Text(source.substring(from: offset))
    }
}

@MainActor private final class HoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor private final class HoverHost: NSHostingView<DartHoverCard> {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(next)
        area = next
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}
/// A compact child panel with intrinsic height and an optional expanded document
/// scroller. No arrow, opening animation or focus request. Constructed only by
/// the running editor, never by a test host; the feature owns its lifetime.
@MainActor final class DartHoverPresenter {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var panel: HoverPanel?
    private var menuOpen = false
    private let menu = WorkbenchContextMenu()
    private weak var editor: NSTextView?
    private var anchor = NSRect.zero
    private var expanded = false
    private var expansion: (() -> Void)?
    var containsPointer: Bool {
        guard let panel, panel.isVisible else { return false }
        let point = panel.mouseLocationOutsideOfEventStream
        return menuOpen || NSRect(origin: .zero, size: panel.frame.size).contains(point)
            || DartHoverPlacement.isInBridge(panel.convertPoint(toScreen: point), anchor: anchor, panel: panel.frame)
    }
    func hide() {
        menu.hide()
        editor = nil
        expanded = false
        expansion = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
    }
    func show(
        content: DartHoverContent, errors: String, range: NSRange, in view: NSTextView,
        canNavigate: Bool, definition: @escaping () -> Void, references: @escaping () -> Void
    ) {
        guard let parent = view.window else { return }
        editor = view
        let panel =
            self.panel
            ?? HoverPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = parent.level
        panel.appearance = view.effectiveAppearance
        let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium)
        let anchor = view.firstRect(forCharacterRange: range, actualRange: nil)
        self.anchor = anchor
        let screens = NSScreen.screens.map(\.visibleFrame)
        let fallback = parent.screen?.visibleFrame ?? parent.frame
        let screen = DartHoverPlacement.screen(for: anchor, screens: screens, fallback: fallback)
        let longest =
            content.signature.components(separatedBy: "\n").map {
                ($0 as NSString).size(withAttributes: [.font: font]).width
            }.max() ?? 0
        let width = min(max(1, screen.width - 16), min(520, max(300, ceil(longest) + 44)))
        // Compact text wraps and has line limits, so even a short response can
        // overflow. Always make its expanded form reachable from the menu.
        if !content.isEmpty || !errors.isEmpty {
            expansion = { [weak self, weak view] in
                guard let self, let view else { return }
                self.expanded.toggle()
                self.show(
                    content: content, errors: errors, range: range, in: view, canNavigate: canNavigate,
                    definition: definition, references: references)
            }
        } else {
            expansion = nil
        }
        let card = DartHoverCard(content: content, errors: errors, width: width, expanded: expanded) { [weak self] in
            self?.showMenu(canNavigate: canNavigate, definition: definition, references: references)
        }
        let host = HoverHost(rootView: card)
        host.sizingOptions = [.intrinsicContentSize]
        host.entered = { [weak self] in self?.entered?() }
        host.exited = { [weak self] in self?.exited?() }
        panel.contentView = host
        let height = min(400, max(40, ceil(host.fittingSize.height)))
        panel.setFrame(
            DartHoverPlacement.frame(
                anchor: anchor, size: NSSize(width: width, height: height), screens: screens, fallback: fallback),
            display: false)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }
    private func showMenu(canNavigate: Bool, definition: @escaping () -> Void, references: @escaping () -> Void) {
        guard let host = panel?.contentView, let window = host.window, let editor else { return }
        menuOpen = true
        menu.onClose = { [weak self] in
            self?.menuOpen = false
            self?.exited?()
        }
        var items: [WorkbenchContextCommand] = [
            .init(
                title: "跳转定义", symbol: "arrow.turn.down.right", shortcut: "⌘B", enabled: canNavigate, action: definition
            ),
            .init(title: "查找引用", symbol: "magnifyingglass", shortcut: "⇧⌘B", action: references),
        ]
        if let expansion {
            items += [.separator, .init(title: expanded ? "收起说明" : "展开说明", action: expansion)]
        }
        let y = host.isFlipped ? host.bounds.maxY - 20 : host.bounds.minY + 20
        let point = window.convertPoint(toScreen: host.convert(NSPoint(x: host.bounds.maxX - 20, y: y), to: nil))
        menu.show(items, at: point, in: editor)
    }
}
