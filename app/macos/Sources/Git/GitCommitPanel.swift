import AppKit
import HyCodeWorkspace
import SwiftUI

struct GitCommitPanel: View {
    @Bindable var controller: GitWorkspaceController
    let headerHeight: CGFloat
    let hide: () -> Void
    @State private var visible: [GitStatusEntry] = []
    @State private var trackedValues: [GitStatusEntry] = []
    @State private var preparedRows: [GitChangeListRow] = []
    @State private var preparedKey = ""
    @State private var expansionRevision = 0
    @State private var collapsed: Set<String> = ["untracked"]
    @State private var filtering = false
    @State private var changesExpanded = true
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                WorkbenchSectionTab(title: "提交", active: !controller.stagedMode) { controller.stagedMode = false }
                WorkbenchSectionTab(title: "暂存区", active: controller.stagedMode) { controller.stagedMode = true }
                Spacer(minLength: 0)
                WorkbenchIconButton(title: "隐藏提交面板", symbol: "minus", size: 24, action: hide)
            }.padding(.horizontal, 8).frame(height: headerHeight)
            WorkbenchSeparator()
            if controller.ready {
                GitPaneSplit(name: "commit", vertical: false, initial: 0.70) {
                    changeList
                } second: {
                    messagePanel
                }
            } else {
                GitEmptyState(controller: controller)
            }
        }.workbenchContentStyle()
            .onChange(of: controller.selectedChange) { _, selected in
                guard let selected, let entry = controller.changes.first(where: { $0.path == selected.path }) else {
                    return
                }
                var changed = false
                if entry.untracked {
                    changed = collapsed.remove("untracked") != nil
                } else {
                    if !changesExpanded { changesExpanded = true }
                    let directory = (entry.path as NSString).deletingLastPathComponent
                    changed = collapsed.remove("directory\0" + directory) != nil
                }
                if changed { expansionRevision += 1 }
            }
            .task(id: projectionKey) {
                let key = projectionKey
                let entries = controller.changes
                let filter = controller.fileFilter
                let grouping = controller.directoryGrouping
                let staged = controller.stagedMode
                let collapsed = collapsed
                let expanded = changesExpanded
                let result = await Task.detached(priority: .utility) {
                    let values = entries.filter { filter.isEmpty || $0.path.localizedCaseInsensitiveContains(filter) }
                    let rows = GitChangeListRow.make(
                        entries: values, stagedMode: staged, grouping: grouping,
                        collapsed: collapsed, expanded: expanded)
                    return (values, values.filter { !$0.untracked }, rows)
                }.value
                guard !Task.isCancelled else { return }
                visible = result.0
                trackedValues = result.1
                preparedRows = result.2
                preparedKey = key
            }
    }
    private var projectionKey: String {
        "\(controller.snapshot?.capturedAt.timeIntervalSince1970 ?? 0)|\(controller.fileFilter)|\(controller.directoryGrouping)|\(controller.stagedMode)|\(changesExpanded)|\(expansionRevision)"
    }
    private var filtered: [GitStatusEntry] { preparedKey == projectionKey ? visible : [] }
    private var tracked: [GitStatusEntry] { preparedKey == projectionKey ? trackedValues : [] }
    private var changeList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                WorkbenchIconButton(title: "刷新 Git", symbol: "arrow.clockwise", size: 24, action: controller.refresh)
                    .disabled(controller.writing)
                WorkbenchIconButton(
                    title: "按目录分组", symbol: controller.directoryGrouping ? "list.bullet" : "folder", size: 24
                ) { controller.directoryGrouping.toggle() }
                WorkbenchIconButton(title: "筛选文件路径", symbol: "magnifyingglass", size: 24) { filtering.toggle() }
                Spacer(minLength: 0)
                Text(
                    controller.selectedCount == 0
                        ? "\(controller.changes.count) 个文件"
                        : "已选 \(controller.selectedCount) / \(controller.changes.count)"
                )
                .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                if controller.loading || !controller.selecting.isEmpty { ProgressView().controlSize(.mini) }
            }.padding(.horizontal, 8).frame(height: GitStyle.toolbarHeight)
            if filtering || !controller.fileFilter.isEmpty {
                GitSearchField(prompt: "筛选文件路径", text: $controller.fileFilter).padding(.horizontal, 10).padding(
                    .bottom, 6)
            }
            if !controller.stagedMode {
                HStack(spacing: 5) {
                    WorkbenchIconButton(
                        title: changesExpanded ? "折叠更改" : "展开更改",
                        symbol: changesExpanded ? "chevron.down" : "chevron.right", size: 16
                    ) { changesExpanded.toggle() }
                    let all = !tracked.isEmpty && tracked.allSatisfy { controller.selectionState($0.path) == .on }
                    GitSelectionCheckbox(
                        state: all
                            ? .on
                            : tracked.contains(where: { controller.selectionState($0.path) != .off }) ? .mixed : .off,
                        title: "选择筛选结果"
                    ) { controller.selectVisible(tracked, selected: !all) }
                    .frame(width: 18, height: 18).disabled(controller.writing)
                    Text(controller.fileFilter.isEmpty ? "更改 \(tracked.count) 个文件" : "筛选结果 \(tracked.count) 个文件")
                    Spacer()
                }.font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary).padding(.horizontal, 8).frame(
                    height: 26)
            }
            GitChangeListView(
                rows: preparedRows,
                selected: controller.stagedMode
                    ? controller.selectedChangeID
                    : controller.selectedChange.map { "work\0" + $0.path },
                selectionState: { controller.selectionState($0) }, selecting: controller.selecting,
                stagedMode: controller.stagedMode, writing: controller.writing,
                loading: preparedKey != projectionKey,
                projectName: controller.snapshot?.repository.root.lastPathComponent ?? "项目根目录",
                show: { row in
                    guard let entry = row.entry else { return }
                    controller.show(
                        entry,
                        comparison: controller.stagedMode
                            ? row.staged ? .staged : entry.untracked ? .working : .unstaged : .working)
                },
                openSource: controller.openSource,
                choose: { entry in controller.choose(entry, selected: controller.selectionState(entry.path) != .on) },
                stage: { row in
                    guard let entry = row.entry else { return }
                    controller.fileAction(row.staged ? .unstage : .stage, entry: entry)
                },
                toggleGroup: { id in
                    if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
                    expansionRevision += 1
                }, menu: menu
            ).frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
                if preparedKey != projectionKey {
                    ProgressView().controlSize(.small).allowsHitTesting(false)
                } else if filtered.isEmpty {
                    Text(controller.changes.isEmpty ? "工作树没有更改" : "没有匹配的文件")
                        .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    private func menu(_ entry: GitStatusEntry) -> [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(title: "查看工作区差异") { controller.show(entry, comparison: .working) },
            WorkbenchMenuItem(title: "查看已暂存差异", enabled: entry.staged) { controller.show(entry, comparison: .staged) },
            WorkbenchMenuItem(title: "打开源文件") { controller.openSource(entry.path) },
            WorkbenchMenuItem(title: "文件历史") {
                controller.query.path = entry.path
                controller.loadHistory()
            },
            .separator,
            WorkbenchMenuItem(
                title: "暂存已保存的版本",
                enabled: !controller.writing && !entry.conflicted && !entry.submodule
                    && (entry.unstaged || entry.untracked)
            ) { controller.fileAction(.stage, entry: entry) },
            WorkbenchMenuItem(title: "取消暂存（保留工作版本）", enabled: entry.staged && !controller.writing) {
                controller.fileAction(.unstage, entry: entry)
            },
            .separator,
            WorkbenchMenuItem(title: "丢弃未暂存更改…", enabled: entry.unstaged && !entry.untracked && !controller.writing) {
                confirmDiscard(entry, action: .discardUnstaged)
            },
            WorkbenchMenuItem(
                title: "恢复到 HEAD（暂存与工作版本）…",
                enabled: !entry.untracked && controller.snapshot?.head != nil && !controller.writing
            ) { confirmDiscard(entry, action: .restoreHead) },
        ]
    }
    private func confirmDiscard(_ entry: GitStatusEntry, action: GitFileAction) {
        controller.captureForAction(entry) { selection, snapshot in
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            WorkbenchPrompt.present(
                in: window, title: action == .restoreHead ? "恢复所选文件到 HEAD？" : "丢弃未暂存更改？",
                detail: entry.path + "\n" + (action == .restoreHead ? "将同时恢复该文件的暂存与工作版本。" : "将工作版本恢复到当前暂存区，已暂存内容保持。")
                    + "此操作不能通过普通文本撤销恢复。", accept: "确认恢复"
            ) { response, _ in
                if response == .accept { controller.fileAction(action, selection: selection, snapshot: snapshot) }
            }
        }
    }
    private var messagePanel: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("修正", isOn: Binding(get: { controller.amend }, set: controller.setAmend)).disabled(
                            controller.snapshot?.head == nil || controller.writing
                        )
                        .help("修正当前分支的上次提交；不会自动强推")
                        Text("上次提交").foregroundStyle(WorkbenchColors.secondary).font(.system(size: 12))
                        Spacer(minLength: 0)
                        Image(systemName: controller.stagedMode ? "tray" : "checkmark.square").foregroundStyle(
                            WorkbenchColors.secondary
                        )
                        .help(controller.stagedMode ? "提交来源为真实暂存区；未暂存内容保留" : "勾选只选择本次提交，不改变暂存区")
                    }.frame(height: 24)
                    if controller.amend {
                        Text("会创建新提交替换当前分支末次提交；已推送历史需另行处理，不自动强推。")
                            .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(
                                horizontal: false, vertical: true)
                    }
                    ZStack(alignment: .topLeading) {
                        if controller.message.isEmpty {
                            Text("提交消息").foregroundStyle(WorkbenchColors.secondary).padding(7).allowsHitTesting(false)
                        }
                        GitMessageField(
                            text: $controller.message, composing: $controller.messageComposing,
                            enabled: !controller.writing
                        )
                        .id(controller.snapshot?.repository.id ?? "no-repository")
                    }.background(WorkbenchColors.field, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4).strokeBorder(WorkbenchColors.tabBorder, lineWidth: 0.5)
                        )
                        .frame(
                            height: max(
                                56,
                                geometry.size.height - 92 - (controller.amend ? 42 : 0)
                                    - (controller.feedbackError != nil || controller.writing || controller.notice != nil
                                        ? 42 : 0))
                        )
                        .accessibilityLabel("Git 提交消息，Enter 换行")
                    GitOperationFeedback(controller: controller)
                    HStack(spacing: 7) {
                        Button(controller.amend ? "修正提交" : "提交") { controller.commit(push: false) }.buttonStyle(
                            WorkbenchActionButtonStyle(primary: true)
                        ).disabled(!controller.canCommit)
                        Button("提交并推送…") { controller.commit(push: true) }.disabled(!controller.canCommit)
                        Spacer(minLength: 0)
                        WorkbenchIconButton(title: "仓库身份与远端…", symbol: "gearshape", size: 24) {
                            controller.dialog = .settings
                        }
                    }
                }.padding(10).frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
            }.background(WorkbenchScrollStyle())
        }
    }
}

private struct GitSelectionCheckbox: NSViewRepresentable {
    let state: NSControl.StateValue
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.choose))
        button.allowsMixedState = true
        button.setAccessibilityLabel(title)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.state = state
        button.isEnabled = enabled
        context.coordinator.action = action
    }
    final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func choose() { action() }
    }
}

struct GitEmptyState: View {
    @Bindable var controller: GitWorkspaceController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.loading {
                ProgressView("正在读取 Git…")
            } else {
                Label(
                    controller.notRepository ? "当前项目没有可访问的 Git 仓库" : "Git 尚未就绪",
                    systemImage: "point.3.connected.trianglepath.dotted")
                Text(controller.feedbackError ?? "打开已有 Git 仓库根目录后，可查看更改和提交历史。初始化与克隆尚未接入。")
                    .foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                if controller.needsGitAccess { Button("授权 Git 管理目录…", action: controller.authorizeGitDirectory) }
                if controller.available { Button("重试") { controller.retry() } }
            }
            Spacer()
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GitOperationFeedback: View {
    @Bindable var controller: GitWorkspaceController
    var body: some View {
        if controller.writing {
            HStack {
                ProgressView().controlSize(.mini)
                Text(controller.operation)
                Spacer(minLength: 2)
                Button("停止", action: controller.cancel)
            }
        } else if let error = controller.feedbackError {
            HStack(alignment: .top, spacing: 5) {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).help(error).textSelection(
                    .enabled)
                if controller.error != nil {
                    WorkbenchIconButton(title: "关闭操作提示", symbol: "xmark", size: 18) { controller.error = nil }
                }
            }
        } else if let notice = controller.notice {
            Text(notice).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary).lineLimit(2).help(notice)
                .textSelection(.enabled)
        }
    }
}
