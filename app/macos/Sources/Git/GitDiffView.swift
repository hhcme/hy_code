import AppKit
import HyCodeWorkspace
import SwiftUI

struct GitDiffView: View {
    @Bindable var controller: GitWorkspaceController
    @Bindable var state: GitReviewState
    @AppStorage("git.diff.unified") private var unified = false
    @State private var difference = -1
    @State private var targetRow: Int?
    @State private var projectedLeft: GitTextComparison.Side?
    @State private var projectedRight: GitTextComparison.Side?
    @State private var projectionID: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                WorkbenchIconButton(title: "上一个文件", symbol: "arrow.left", size: 24) {
                    controller.adjacent(state.location, direction: -1)
                }
                .disabled(state.fileIndex == 0)
                Text("\(state.fileIndex + 1) / \(max(1, state.paths.count)) 个文件").font(.system(size: 12))
                    .foregroundStyle(WorkbenchColors.accent)
                WorkbenchIconButton(title: "下一个文件", symbol: "arrow.right", size: 24) {
                    controller.adjacent(state.location, direction: 1)
                }
                .disabled(state.fileIndex + 1 >= state.paths.count)
                WorkbenchIconButton(title: "上一处差异", symbol: "arrow.up", size: 24) { move(-1) }.disabled(difference <= 0)
                WorkbenchIconButton(title: "下一处差异", symbol: "arrow.down", size: 24) { move(1) }
                    .disabled(
                        (state.diff?.differenceRows.count ?? 0) == 0
                            || difference + 1 >= (state.diff?.differenceRows.count ?? 0))
                Spacer(minLength: 0)
                if state.loading || state.bufferLoading { ProgressView().controlSize(.mini) }
                Text("\(state.diff?.differenceRows.count ?? 0) 处差异").font(.system(size: 11)).foregroundStyle(
                    WorkbenchColors.secondary)
                WorkbenchIconButton(
                    title: unified ? "切换左右对比（工作区可编辑）" : "切换统一差异（只读）",
                    symbol: unified ? "rectangle.split.2x1" : "rectangle", size: 24
                ) { unified.toggle() }
                WorkbenchIconButton(title: "打开当前工作区源文件", symbol: "pencil", size: 24) {
                    controller.openSource(state.location.path)
                }
                WorkbenchIconButton(title: "刷新差异", symbol: "arrow.clockwise", size: 24) {
                    controller.loadDiff(state.location)
                }
            }.padding(.horizontal, 8).frame(height: GitStyle.toolbarHeight)
            WorkbenchSeparator()
            if let document = state.document, document.isDirty || document.error != nil || document.inputError != nil {
                HStack(spacing: 8) {
                    Text(document.error ?? document.inputError ?? "未保存 · 差异随编辑更新，保存后才能选入提交")
                        .lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("保存并重新审查") { controller.saveAndRefresh([state.location.path]) }
                }.font(.system(size: 11)).padding(8).background(WorkbenchColors.chrome)
            }
            if unified && state.document != nil {
                HStack {
                    Text("统一差异为只读投影")
                    Button("左右对比中编辑") { unified = false }
                    Spacer()
                }.font(.system(size: 11)).padding(6).background(WorkbenchColors.chrome)
            }
            if let document = state.document, !document.loading, !document.isDirty,
                !state.bufferLoading, !state.loading, state.bufferRevision != nil, !state.permitsSelection
            {
                HStack {
                    Text("编辑器内容与已保存版本不同，尚不能选入提交")
                    Spacer()
                    Button("重新载入已保存版本…") { controller.reloadDocument(state.location.path) }
                }.font(.system(size: 11)).padding(8).background(WorkbenchColors.chrome)
            }
            if let error = state.document?.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(10)
            }
            if let error = state.error ?? state.bufferError {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(10)
            }
            if let reason = state.readonlyReason {
                Text(reason).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary).padding(8)
            }
            if let diff = state.diff {
                if let message = diff.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary).padding(8)
                }
                if let left = leftSource(diff), let right = rightSource(diff) {
                    GitNativeDiff(
                        diff: diff, left: left, right: right, unified: unified, targetRow: targetRow,
                        document: unified ? nil : state.document,
                        aligned: state.document == nil || state.bufferRevision == state.document?.edits.revision,
                        selection: selection, actions: actions
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("正在准备文本比较…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if state.loading {
                ProgressView("正在生成差异…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }.workbenchContentStyle()
            .onChange(of: state.location) { _, _ in
                difference = -1
                targetRow = nil
            }
            .task(id: projectionKey) {
                guard let diff = state.diff, unified || diff.text == nil else { return }
                let unified = self.unified
                let key = projectionKey
                let result = await Task.detached(priority: .utility) {
                    let rows = unified ? diff.unifiedRows : diff.rows
                    return (
                        GitTextComparison.projection(rows, left: true, unified: unified),
                        GitTextComparison.projection(rows, left: false, unified: false)
                    )
                }.value
                guard !Task.isCancelled else { return }
                projectedLeft = result.0
                projectedRight = result.1
                projectionID = key
            }
            .task(id: bufferKey) { controller.previewBuffer(state) }
    }
    private var projectionKey: String { (state.diff?.id.uuidString ?? "none") + (unified ? "unified" : "split") }
    private var bufferKey: String {
        [
            state.ticket.uuidString, state.document?.id.uuidString ?? "none",
            String(state.document?.edits.revision ?? 0),
            String(state.document?.loading ?? true), String(state.document?.composing ?? false), String(state.loading),
        ].joined(separator: ":")
    }
    private func leftSource(_ diff: GitDiff) -> GitTextComparison.Side? {
        if !unified, let text = diff.text { return text.left }
        return projectionID == projectionKey ? projectedLeft : nil
    }
    private func rightSource(_ diff: GitDiff) -> GitTextComparison.Side? {
        if !unified, let text = diff.text { return text.right }
        return projectionID == projectionKey ? projectedRight : nil
    }
    private var selection: GitDiffSelection? {
        guard state.location.comparison == .working, !controller.stagedMode,
            let entry = controller.changes.first(where: { $0.path == state.location.path })
        else { return nil }
        return GitDiffSelection(
            state: controller.selectionState(entry.path),
            enabled: !controller.writing && !state.loading && !entry.conflicted && !entry.submodule
                && !controller.selecting.contains(entry.path) && !controller.dirtyPaths().contains(entry.path),
            choose: { controller.choose(entry, selected: $0) })
    }
    private var actions: GitHunkActions {
        let path = state.location.path
        let reviewID = state.diff?.id
        let savedID = state.savedDiff?.id
        let ticket = state.ticket
        let busy = controller.writing || state.loading || state.bufferLoading || controller.selecting.contains(path)
        let selectable = state.location.comparison == .working && !controller.stagedMode
        let saved = state.savedDiff?.selection
        let blockSelectionEnabled =
            selectable && !busy && state.permitsSelection && saved != nil
            && saved?.bothLayersChanged != true
        let canRestore =
            !busy && state.document?.editor?.textView.isEditable == true
            && state.bufferRevision == state.document?.edits.revision && state.document?.composing != true
            && state.document?.closing != true
        let reason: String
        if state.document?.isDirty == true || !state.permitsSelection {
            reason = "保存并重新审查后，选择要提交的差异块"
        } else if saved?.bothLayersChanged == true {
            reason = "文件同时有暂存与未暂存改动，请在暂存区模式处理"
        } else {
            reason = "选择本次要提交的差异块，其余修改继续保留"
        }
        return GitHunkActions(
            showsSelection: selectable, selectionEnabled: blockSelectionEnabled,
            selectionHelp: reason, restoreEnabled: canRestore,
            restoreHelp: canRestore ? "将此处还原为左侧版本，可撤销" : "工作区正文准备完成后可还原此处",
            isSelected: { controller.blockIsSelected(state, id: $0) },
            choose: {
                controller.chooseBlock(
                    state, id: $0, selected: $1, reviewID: reviewID, savedID: savedID, ticket: ticket)
            },
            restore: { controller.restoreBlock(state, id: $0, reviewID: reviewID, ticket: ticket) })
    }
    private func move(_ delta: Int) {
        guard let rows = state.diff?.differenceRows, !rows.isEmpty else { return }
        difference = min(rows.count - 1, max(0, difference + delta))
        targetRow = rows[difference]
    }
}

struct GitDiffSelection {
    let state: NSControl.StateValue
    let enabled: Bool
    let choose: @MainActor (Bool) -> Void
}

private struct GitNativeDiff: NSViewRepresentable {
    let diff: GitDiff
    let left: GitTextComparison.Side
    let right: GitTextComparison.Side
    let unified: Bool
    let targetRow: Int?
    let document: EditorDocument?
    let aligned: Bool
    let selection: GitDiffSelection?
    let actions: GitHunkActions
    @Environment(\.colorScheme) private var scheme
    @AppStorage("editor.lineNumbers") private var numbers = true
    @AppStorage("editor.syntaxHighlight") private var syntax = true
    func makeNSView(context: Context) -> GitDiffHost { GitDiffHost() }
    func updateNSView(_ view: GitDiffHost, context: Context) {
        view.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        view.split.configure(
            diff, left: left, right: right, unified: unified, target: targetRow,
            document: document, aligned: aligned, selection: selection, actions: actions, numbers: numbers,
            syntax: syntax)
    }
    static func dismantleNSView(_ view: GitDiffHost, coordinator: ()) { view.split.detach() }
}
