import AppKit
import Observation
import SwiftUI

@MainActor enum WorkbenchPromptResponse { case accept, alternate, cancel }

/// Business dialogs are sheets with the same fields/buttons as the workbench.
/// They are created only for explicit user actions. No modal run loop, global
/// event monitor, or second text/document owner is introduced.
@MainActor private final class WorkbenchPromptController: NSObject {
    private let panel: PromptPanel
    private let model: PromptModel
    private var finished = false
    private let completion: (WorkbenchPromptResponse, String) -> Void
    init(
        parent: NSWindow, title: String, detail: String, initialValue: String?, accept: String,
        alternate: String?, completion: @escaping (WorkbenchPromptResponse, String) -> Void
    ) {
        self.completion = completion
        model = PromptModel(
            title: title, detail: detail, text: initialValue ?? "", hasInput: initialValue != nil,
            accept: accept, alternate: alternate)
        panel = PromptPanel(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = parent.effectiveAppearance
        let dark = parent.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let host = NSHostingView(
            rootView: PromptContent(model: model).environment(\.colorScheme, dark ? .dark : .light))
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        host.setAccessibilityLabel(title)
        panel.contentView = host
        panel.setContentSize(CGSize(width: 520, height: max(160, min(600, host.fittingSize.height))))
        model.choose = { [weak self] in self?.finish($0) }
        NotificationCenter.default.addObserver(
            self, selector: #selector(parentClosed),
            name: NSWindow.willCloseNotification, object: parent)
        // The completion retains the controller for precisely this sheet's
        // lifetime. Ending/closing the sheet releases it after cleanup.
        parent.beginSheet(panel) { [self] response in
            guard !finished else { return }
            finished = true
            NotificationCenter.default.removeObserver(self)
            panel.orderOut(nil)
            panel.contentView = nil
            completion(
                response == .OK ? .accept : response == .alertSecondButtonReturn ? .alternate : .cancel, model.text)
        }
    }
    @objc private func parentClosed(_ note: Notification) { finish(.cancel) }
    private func finish(_ response: WorkbenchPromptResponse) {
        guard !finished, !model.submitted, let parent = panel.sheetParent else { return }
        model.submitted = true
        let code: NSApplication.ModalResponse =
            response == .accept ? .OK : response == .alternate ? .alertSecondButtonReturn : .cancel
        parent.endSheet(panel, returnCode: code)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
@MainActor enum WorkbenchPrompt {
    static func present(
        in parent: NSWindow, title: String, detail: String, initialValue: String? = nil,
        accept: String, alternate: String? = nil,
        completion: @escaping (WorkbenchPromptResponse, String) -> Void
    ) {
        guard parent.attachedSheet == nil else {
            completion(.cancel, initialValue ?? "")
            return
        }
        _ = WorkbenchPromptController(
            parent: parent, title: title, detail: detail, initialValue: initialValue,
            accept: accept, alternate: alternate, completion: completion)
    }
}
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor @Observable private final class PromptModel {
    let title: String
    let detail: String
    var text: String
    var submitted = false
    let hasInput: Bool
    let accept: String
    let alternate: String?
    var choose: (WorkbenchPromptResponse) -> Void = { _ in }
    init(title: String, detail: String, text: String, hasInput: Bool, accept: String, alternate: String?) {
        self.title = title
        self.detail = detail
        self.text = text
        self.hasInput = hasInput
        self.accept = accept
        self.alternate = alternate
    }
}
private struct PromptContent: View {
    @Bindable var model: PromptModel
    @FocusState private var inputFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            WorkbenchDialogHeader(title: model.title, symbol: model.hasInput ? "pencil" : "doc.badge.arrow.up")
            WorkbenchSeparator(visible: true)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.detail).fixedSize(horizontal: false, vertical: true).foregroundStyle(
                    WorkbenchColors.secondary)
                if model.hasInput { TextField("新名称", text: $model.text).focused($inputFocused) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            WorkbenchSeparator(visible: true)
            HStack(spacing: 8) {
                if let alternate = model.alternate {
                    Button(alternate) { model.choose(.alternate) }.foregroundStyle(.red)
                }
                Spacer(minLength: 12)
                Button("取消") { model.choose(.cancel) }.keyboardShortcut(.cancelAction)
                Button(model.accept) { model.choose(.accept) }.buttonStyle(WorkbenchActionButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction).disabled(model.hasInput && model.text.isEmpty)
            }.padding(12).background(WorkbenchColors.chrome)
        }.disabled(model.submitted).workbenchContentStyle().frame(width: 520).clipShape(
            RoundedRectangle(cornerRadius: 10)
        )
        .onAppear { inputFocused = model.hasInput }
    }
}
