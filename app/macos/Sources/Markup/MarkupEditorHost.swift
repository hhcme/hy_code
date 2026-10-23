import AppKit
import HyCodeWorkspace
import SwiftUI
import WebKit

/// The native divider changes only NSView frames while dragging. Persist once
/// tracking finishes; no observable geometry is written on each mouse event.
@MainActor final class MarkupSplitView: NSSplitView, NSSplitViewDelegate {
    weak var preview: MarkupPreviewController?
    private var fraction = MarkupScrollMapping.splitRatio(
        UserDefaults.standard.double(forKey: "markup.splitRatio").nonzeroOrHalf)
    private var resizing = false
    private let placeholder = NSHostingView(rootView: MarkupPlaceholder(message: "正在生成预览…"))
    override var dividerThickness: CGFloat { subviews.count == 2 ? 5 : 0 }
    override init(frame: NSRect) {
        super.init(frame: frame)
        isVertical = true
        dividerStyle = .thin
        delegate = self
    }
    required init?(coder: NSCoder) { nil }
    override func drawDivider(in rect: NSRect) {
        WorkbenchColors.nativeChrome.setFill()
        rect.fill()
    }
    func configure(editor: NSView, browser: NSView?, mode: MarkupPreviewMode) {
        let ready = preview?.hasPage == true && preview?.error == nil
        placeholder.rootView = MarkupPlaceholder(message: preview?.error ?? "正在生成预览…")
        let right = ready ? (browser ?? placeholder) : placeholder
        let wanted = mode == .source ? [editor] : mode == .preview ? [right] : [editor, right]
        if subviews.count != wanted.count || !zip(subviews, wanted).allSatisfy({ $0 === $1 }) {
            for view in subviews { view.removeFromSuperview() }
            for view in wanted { addArrangedSubview(view) }
            layoutPanes()
        }
    }
    func detach() { for view in subviews { view.removeFromSuperview() } }
    override func resizeSubviews(withOldSize oldSize: NSSize) { layoutPanes() }
    private func layoutPanes() {
        guard !resizing else { return }
        resizing = true
        defer { resizing = false }
        if subviews.count == 1 { subviews[0].frame = bounds }
        if subviews.count == 2 {
            let width = max(0, bounds.width - dividerThickness)
            let first = (width * fraction).rounded()
            subviews[0].frame = NSRect(x: 0, y: 0, width: first, height: bounds.height)
            subviews[1].frame = NSRect(
                x: first + dividerThickness, y: 0, width: max(0, width - first), height: bounds.height)
        }
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !resizing, subviews.count == 2, bounds.width > dividerThickness else { return }
        fraction = MarkupScrollMapping.splitRatio(subviews[0].frame.width / (bounds.width - dividerThickness))
    }
    func splitView(
        _ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        min(max(bounds.width * 0.2, proposedPosition), bounds.width * 0.8)
    }
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        UserDefaults.standard.set(fraction, forKey: "markup.splitRatio")
    }
}
extension Double { fileprivate var nonzeroOrHalf: Double { self == 0 ? 0.5 : self } }

struct MarkupEditorHost: NSViewRepresentable {
    let editor: NativeTextEditor
    let preview: MarkupPreviewController
    let browser: WKWebView?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("editor.lineNumbers") private var lineNumbers = true
    @AppStorage("editor.syntaxHighlight") private var syntaxHighlight = true
    func makeNSView(context: Context) -> MarkupSplitView {
        let view = MarkupSplitView()
        view.preview = preview
        configure(view)
        return view
    }
    func updateNSView(_ view: MarkupSplitView, context: Context) { configure(view) }
    private func configure(_ view: MarkupSplitView) {
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        if editor.scroll.appearance?.name != appearance?.name {
            editor.scroll.appearance = appearance
            editor.scroll.effectiveAppearance.performAsCurrentDrawingAppearance { editor.applyAppearance() }
        }
        editor.presentation?.configure(lineNumbers: lineNumbers, syntaxHighlight: syntaxHighlight)
        view.configure(editor: editor.scroll, browser: browser, mode: preview.mode)
    }
    static func dismantleNSView(_ view: MarkupSplitView, coordinator: ()) {
        view.detach()
    }
}

struct MarkupPreviewToolbar: View {
    @Bindable var preview: MarkupPreviewController
    var body: some View {
        HStack(spacing: 5) {
            ForEach(MarkupPreviewMode.allCases, id: \.self) { mode in
                Button(mode.title) { preview.mode = mode }
                    .buttonStyle(WorkbenchActionButtonStyle(primary: preview.mode == mode))
            }
            Spacer(minLength: 8)
            if preview.rendering { ProgressView().controlSize(.mini) }
            if let error = preview.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1).help(error)
            } else if preview.resourceFailures > 0 {
                Text("\(preview.resourceFailures) 个资源未载入").font(.system(size: 11)).foregroundStyle(
                    WorkbenchColors.secondary
                )
                .help("预览只读取项目内 CSS 与受限图片；外部资源、字体、脚本及超限资源不会载入")
            }
            Toggle("滚动联动", isOn: $preview.linkedScrolling).toggleStyle(.checkbox)
                .font(.system(size: 11)).disabled(preview.mode != .split || !preview.supportsLinkedScrolling)
            Button {
                preview.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(WorkbenchActionButtonStyle()).help("重新载入预览与项目资源")
        }.padding(.horizontal, 10).frame(height: 34).background(WorkbenchColors.chrome)
    }
}

private struct MarkupPlaceholder: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext").font(.system(size: 24))
            Text(message).font(.system(size: 12)).textSelection(.enabled)
                .multilineTextAlignment(.center)
        }.foregroundStyle(WorkbenchColors.secondary).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(WorkbenchColors.panel)
    }
}
