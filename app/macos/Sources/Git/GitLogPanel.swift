import AppKit
import HyCodeWorkspace
import SwiftUI

struct GitLogPanel: View {
    @Bindable var controller: GitWorkspaceController
    let headerHeight: CGFloat
    let hide: () -> Void
    @State private var branchFilter = ""
    @State private var filters = false
    @State private var compactDetails = false
    @State private var collapsedBranches: Set<String> = ["标签"]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("Git").fontWeight(.semibold).padding(.trailing, 4)
                WorkbenchSectionTab(title: "日志", active: !controller.showingConsole) {
                    controller.showingConsole = false
                }
                WorkbenchSectionTab(title: "控制台", active: controller.showingConsole) {
                    controller.showingConsole = true
                }
                Spacer(minLength: 0)
                GitRemoteActions(controller: controller)
                WorkbenchIconButton(title: "刷新 Git", symbol: "arrow.clockwise", size: 24, action: controller.refresh)
                    .disabled(controller.writing)
                WorkbenchIconButton(title: "隐藏 Git", symbol: "minus", size: 24, action: hide)
            }.padding(.horizontal, 10).frame(height: headerHeight)
            WorkbenchSeparator()
            if !controller.ready {
                GitEmptyState(controller: controller)
            } else if controller.showingConsole {
                console
            } else {
                GeometryReader { geometry in
                    if geometry.size.width >= 760 {
                        GitPaneSplit(name: "log-sidebar", vertical: true, initial: 0.23) {
                            branches
                        } second: {
                            GitPaneSplit(name: "log-detail", vertical: true, initial: 0.58) {
                                history
                            } second: {
                                details
                            }
                        }
                    } else {
                        VStack(spacing: 0) {
                            HStack {
                                WorkbenchSectionTab(title: "提交", active: !compactDetails) { compactDetails = false }
                                WorkbenchSectionTab(title: "详情", active: compactDetails) { compactDetails = true }
                                Spacer()
                            }.padding(.horizontal, 8).frame(height: 32)
                            if compactDetails { details } else { history }
                        }
                    }
                }
            }
        }.workbenchContentStyle()
    }
    private var branches: some View {
        VStack(alignment: .leading, spacing: 6) {
            GitSearchField(prompt: "分支或标签", text: $branchFilter).padding(.horizontal, 8).padding(.top, 4)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Button {
                        controller.query.reference = nil
                        controller.query.allReferences = false
                        controller.loadHistory()
                    } label: {
                        Label("HEAD（当前分支）", systemImage: "arrow.turn.down.right")
                            .frame(maxWidth: .infinity, minHeight: GitStyle.rowHeight, alignment: .leading)
                    }.buttonStyle(
                        WorkbenchButtonStyle(
                            active: controller.query.reference == nil && !controller.query.allReferences, neutral: true)
                    )
                    Button {
                        controller.query.allReferences = true
                        controller.query.reference = nil
                        controller.loadHistory()
                    } label: {
                        Label("全部引用", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity, minHeight: GitStyle.rowHeight, alignment: .leading)
                    }.buttonStyle(WorkbenchButtonStyle(active: controller.query.allReferences, neutral: true))
                    branchGroup("本地", values: matching.filter { !$0.remote && !$0.tag })
                    branchGroup("远程", values: matching.filter(\.remote))
                    branchGroup("标签", values: matching.filter(\.tag))
                }.padding(10)
            }.background(WorkbenchScrollStyle())
        }
    }
    private var matching: [GitReference] {
        controller.references.filter {
            branchFilter.isEmpty || $0.shortName.localizedCaseInsensitiveContains(branchFilter)
        }
    }
    private func branchGroup(_ title: String, values: [GitReference]) -> some View {
        DisclosureGroup(title, isExpanded: expansion(title)) {
            if title == "远程" {
                let groups = Dictionary(grouping: values) { String($0.shortName.split(separator: "/").first ?? "") }
                ForEach(groups.keys.sorted(), id: \.self) { name in
                    DisclosureGroup(isExpanded: expansion("remote:" + name)) {
                        branchRows(groups[name] ?? [])
                    } label: {
                        Label(name, systemImage: "folder")
                    }
                }
            } else {
                branchRows(values)
            }
        }.tint(WorkbenchColors.secondary).padding(.top, 4)
    }
    private func expansion(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedBranches.contains(key) },
            set: {
                if $0 { collapsedBranches.remove(key) } else { collapsedBranches.insert(key) }
            })
    }
    private func branchRows(_ values: [GitReference]) -> some View {
        Group {
            ForEach(values) { reference in
                Button {
                    controller.query.reference = reference.name
                    controller.query.allReferences = false
                    controller.loadHistory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: reference.tag ? "tag" : reference.remote ? "cloud" : "arrow.triangle.branch")
                        Text(
                            reference.remote
                                ? reference.shortName.split(separator: "/").dropFirst().joined(separator: "/")
                                : reference.shortName
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        if reference.current { Image(systemName: "checkmark").foregroundStyle(WorkbenchColors.accent) }
                    }.frame(maxWidth: .infinity, minHeight: GitStyle.rowHeight, alignment: .leading).padding(
                        .horizontal, 5)
                }.buttonStyle(WorkbenchButtonStyle(active: controller.query.reference == reference.name, neutral: true))
                    .workbenchContextMenu([
                        WorkbenchMenuItem(title: "查看日志") {
                            controller.query.reference = reference.name
                            controller.query.allReferences = false
                            controller.loadHistory()
                        },
                        WorkbenchMenuItem(title: "与当前 HEAD 比较文件", enabled: controller.snapshot?.head != nil) {
                            controller.compareToHead(reference.object)
                        },
                        WorkbenchMenuItem(
                            title: reference.remote ? "建立跟踪分支并切换" : "切换到此分支",
                            enabled: !reference.current && !reference.tag && !controller.writing
                        ) { controller.switchBranch(reference) },
                        WorkbenchMenuItem(
                            title: "安全删除已合并分支…",
                            enabled: !reference.current && !reference.remote && !reference.tag && !controller.writing
                        ) { confirmDelete(reference) },
                    ])
            }
        }
    }
    private func confirmDelete(_ reference: GitReference) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        WorkbenchPrompt.present(
            in: window, title: "安全删除本地分支？", detail: reference.shortName + "\n仅删除 Git 确认已合并且未被工作树使用的分支。", accept: "删除分支"
        ) { response, _ in if response == .accept { controller.deleteBranch(reference) } }
    }
    private var history: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                GitSearchField(prompt: "文本或哈希", text: $controller.query.text) { controller.loadHistory() }
                GitBranchFilter(controller: controller)
                WorkbenchIconButton(title: "作者、日期和路径筛选", symbol: "line.3.horizontal.decrease", size: 24) {
                    filters.toggle()
                }
                WorkbenchIconButton(title: "应用日志筛选", symbol: "arrow.turn.down.left", size: 24) {
                    controller.loadHistory()
                }
                .disabled(controller.writing)
                WorkbenchIconButton(title: "按哈希定位（清除其他筛选）", symbol: "scope", size: 24, action: controller.locateHash)
                    .disabled(controller.query.text.count < 4)
                if controller.historyLoading { ProgressView().controlSize(.mini) }
            }.padding(.horizontal, 8).frame(height: GitStyle.toolbarHeight)
            if filters {
                VStack(spacing: 5) {
                    HStack {
                        TextField("作者", text: $controller.query.author)
                        TextField("仓库相对路径", text: $controller.query.path)
                    }
                    HStack {
                        dateFilter("起始", value: $controller.query.since)
                        dateFilter("结束", value: $controller.query.until)
                        Button("清除") {
                            controller.query.author = ""
                            controller.query.path = ""
                            controller.query.since = nil
                            controller.query.until = nil
                            controller.loadHistory()
                        }
                    }
                }.textFieldStyle(WorkbenchTextFieldStyle()).padding(.horizontal, 8).padding(.bottom, 5)
            }
            WorkbenchSeparator()
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(controller.commits.enumerated()), id: \.element.id) { index, commit in
                        Button {
                            controller.selectCommit(commit)
                        } label: {
                            HStack(spacing: 7) {
                                GitCommitGraph(row: index < controller.graph.count ? controller.graph[index] : nil)
                                    .frame(width: CGFloat(controller.graphColumns) * 11 + 10, height: 25)
                                Text(commit.subject).lineLimit(1).frame(
                                    minWidth: 180, maxWidth: .infinity, alignment: .leading)
                                if !commit.decorations.isEmpty {
                                    Text(commit.decorations).font(.system(size: 10)).foregroundStyle(
                                        WorkbenchColors.accent
                                    ).lineLimit(1).frame(maxWidth: 160)
                                }
                                Text(commit.author).lineLimit(1).frame(width: 65, alignment: .trailing).foregroundStyle(
                                    WorkbenchColors.secondary)
                                Text(commit.committedAt, style: .relative).font(.system(size: 11)).frame(
                                    width: 85, alignment: .trailing
                                ).foregroundStyle(WorkbenchColors.secondary)
                            }.padding(.trailing, 8).frame(minHeight: 25)
                        }.buttonStyle(
                            WorkbenchButtonStyle(
                                active: controller.selectedCommit?.object == commit.object, neutral: true)
                        ).help(commit.object + "\n" + commit.message)
                            .workbenchContextMenu([
                                WorkbenchMenuItem(title: "查看提交详情") { controller.selectCommit(commit) },
                                WorkbenchMenuItem(title: "与当前 HEAD 比较文件", enabled: controller.snapshot?.head != nil) {
                                    controller.compareToHead(commit.object)
                                },
                                WorkbenchMenuItem(title: "设为比较左侧") { controller.comparisonLeft = commit },
                                WorkbenchMenuItem(title: "与已选左侧比较文件", enabled: controller.comparisonLeft != nil) {
                                    if let left = controller.comparisonLeft { controller.compare(left, commit) }
                                },
                            ])
                    }
                    if controller.commits.isEmpty && !controller.historyLoading {
                        Text("没有符合条件的提交").foregroundStyle(WorkbenchColors.secondary).padding(16)
                    }
                    if controller.canLoadMore {
                        Button("加载更早的提交") { controller.loadHistory(more: true) }.padding(10).disabled(
                            controller.historyLoading)
                    }
                    if controller.commits.count >= 2000 {
                        Text("已保留 2,000 条，请用分支、作者、日期或路径缩小范围").font(.system(size: 11)).padding(10)
                    }
                }.padding(.vertical, 4)
            }.background(WorkbenchScrollStyle())
            if controller.feedbackError != nil || controller.writing || controller.notice != nil {
                GitOperationFeedback(controller: controller).padding(8)
            }
        }
    }
    private func dateFilter(_ label: String, value: Binding<Date?>) -> some View {
        HStack(spacing: 3) {
            Toggle(
                label,
                isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? Date() : nil })
            ).fixedSize()
            if value.wrappedValue != nil {
                DatePicker(
                    label, selection: Binding(get: { value.wrappedValue ?? Date() }, set: { value.wrappedValue = $0 }),
                    displayedComponents: .date
                ).labelsHidden()
            }
        }.font(.system(size: 11))
    }
    private var details: some View {
        VStack(spacing: 0) {
            if let commit = controller.selectedCommit {
                HStack {
                    Text("提交 \(commit.object.prefix(8))").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    if commit.parents.count > 1 {
                        WorkbenchMenuButton(
                            title: "选择比较的父提交",
                            items: commit.parents.map { parent in
                                WorkbenchMenuItem(
                                    title: String(parent.prefix(8)), checked: controller.selectedParent == parent
                                ) {
                                    controller.selectedParent = parent
                                    controller.loadCommitFiles()
                                }
                            }
                        ) { Label("父提交", systemImage: "chevron.down").font(.system(size: 11)) }
                    }
                }.padding(8)
                if case .objects(let left, let right)? = controller.objectComparison {
                    Text("\(left.prefix(8)) → \(right.prefix(8)) · 两个固定版本").font(.system(size: 11)).foregroundStyle(
                        WorkbenchColors.accent
                    ).padding(.horizontal, 8)
                }
            }
            GitPaneSplit(name: "commit-detail", vertical: false, initial: 0.62) {
                if controller.selectedCommit != nil {
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if controller.detailsLoading { ProgressView().controlSize(.mini).padding(8) }
                            ForEach(controller.commitFiles) { file in
                                Button {
                                    controller.showHistoryFile(file)
                                } label: {
                                    HStack {
                                        Text(file.status).foregroundStyle(WorkbenchColors.accent)
                                        Text(file.path).fixedSize(horizontal: true, vertical: false)
                                    }.padding(.horizontal, 8).frame(minHeight: 25)
                                }.buttonStyle(WorkbenchButtonStyle())
                            }
                        }.padding(.vertical, 4)
                    }.background(WorkbenchScrollStyle())
                } else {
                    Text("选择要查看更改的提交").font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } second: {
                if let commit = controller.selectedCommit {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(commit.message).fontWeight(.medium)
                            Text(commit.object).font(.system(size: 10, design: .monospaced))
                            Text("作者：\(commit.author) <\(commit.email)>")
                            Text(commit.authoredAt, format: .dateTime.year().month().day().hour().minute())
                            Text("提交者：\(commit.committer) <\(commit.committerEmail)>")
                            Text(commit.committedAt, format: .dateTime.year().month().day().hour().minute())
                            Text("父提交：" + (commit.parents.isEmpty ? "根提交" : commit.parents.joined(separator: "\n")))
                                .font(.system(size: 10, design: .monospaced))
                        }.font(.system(size: 11)).textSelection(.enabled).frame(
                            maxWidth: .infinity, alignment: .leading
                        ).padding(10)
                    }.background(WorkbenchScrollStyle())
                } else {
                    Text("提交详细信息").font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
    private var console: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(controller.console) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.date, style: .time)
                            Text(entry.title).fontWeight(.semibold)
                        }.foregroundStyle(entry.failed ? .orange : WorkbenchColors.text)
                        Text(entry.detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if controller.console.isEmpty {
                    Text("尚无 Git 写入操作。日志仅显示 HyCode 发起的操作。").foregroundStyle(WorkbenchColors.secondary)
                }
            }.padding(12)
        }.background(WorkbenchScrollStyle())
    }
}

private struct GitCommitGraph: View {
    let row: GitGraphRow?
    var body: some View {
        Canvas { context, size in
            guard let row else { return }
            let step: CGFloat = 11
            for edge in row.edges {
                var path = Path()
                path.move(to: CGPoint(x: 7 + CGFloat(edge.from) * step, y: 0))
                path.addLine(to: CGPoint(x: 7 + CGFloat(edge.from) * step, y: size.height / 2))
                path.addLine(to: CGPoint(x: 7 + CGFloat(edge.to) * step, y: size.height))
                context.stroke(path, with: .color(GitStyle.graph), lineWidth: 1.5)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: 4 + CGFloat(row.column) * step, y: size.height / 2 - 3, width: 6, height: 6)),
                with: .color(GitStyle.graph))
        }.accessibilityLabel("提交关系图，第 \((row?.column ?? 0) + 1) 列")
    }
}

struct GitBranchFilter: View {
    @Bindable var controller: GitWorkspaceController
    var body: some View {
        WorkbenchMenuButton(
            title: "日志分支筛选",
            items: [
                WorkbenchMenuItem(
                    title: "当前分支", checked: controller.query.reference == nil && !controller.query.allReferences
                ) {
                    controller.query.reference = nil
                    controller.query.allReferences = false
                    controller.loadHistory()
                },
                WorkbenchMenuItem(title: "全部引用", checked: controller.query.allReferences) {
                    controller.query.reference = nil
                    controller.query.allReferences = true
                    controller.loadHistory()
                },
                .separator,
            ]
                + controller.references.prefix(100).map { reference in
                    WorkbenchMenuItem(title: reference.shortName, checked: controller.query.reference == reference.name)
                    {
                        controller.query.reference = reference.name
                        controller.query.allReferences = false
                        controller.loadHistory()
                    }
                }
        ) {
            Text(
                controller.query.allReferences
                    ? "全部引用 ▾"
                    : (controller.query.reference ?? controller.branchTitle).replacingOccurrences(
                        of: "refs/heads/", with: "") + " ▾"
            ).lineLimit(1).frame(maxWidth: 150).padding(.horizontal, 4).frame(height: 26)
        }
    }
}

struct GitRemoteActions: View {
    @Bindable var controller: GitWorkspaceController
    var body: some View {
        HStack(spacing: 1) {
            if let issue = controller.remoteIssue {
                WorkbenchIconButton(title: "远端配置需要处理", symbol: "exclamationmark.triangle", size: 24) {
                    controller.dialog = .settings
                }
                .help(issue)
            }
            WorkbenchIconButton(
                title: "获取远端分支（不修改工作版本）", symbol: "arrow.down.circle", size: 24, action: controller.fetch)
            WorkbenchIconButton(title: "仅快进拉取", symbol: "arrow.down", size: 24, action: controller.pull)
            WorkbenchIconButton(title: "预览并推送…", symbol: "arrow.up", size: 24, action: controller.requestPush)
        }.disabled(!controller.ready || controller.writing)
    }
}
