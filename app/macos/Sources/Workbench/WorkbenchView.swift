import HyCodeWorkspace
import SwiftUI

struct WorkbenchView: View {
    @Bindable var store: WorkbenchStore
    @Binding var appearance: WorkbenchAppearance
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchHeader(store: store, appearance: $appearance)
            HStack(spacing: 0) {
                toolRail(leading: true)
                WorkbenchCanvas(
                    docking: store.docking, workspaceSession: store.sessionID, editor: AnyView(editorPanel),
                    tools: Dictionary(uniqueKeysWithValues: WorkbenchTool.allCases.map { ($0, AnyView(toolPanel($0))) })
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                toolRail(leading: false)
            }
            .padding(.horizontal, WorkbenchMetrics.shellInset)
            statusBar
        }
        .font(.system(size: 13))
        .controlSize(.small)
        .background(WorkbenchColors.chrome)
        .background(WorkbenchWindowChrome())
        .background(EditorWindowCloseGuard(store: store))
        .sheet(item: Binding(get: { store.flutter.dialog }, set: { store.flutter.dialog = $0 })) { dialog in
            switch dialog {
            case .configuration: FlutterRunConfigurationEditor(controller: store.flutter)
            case .breakpoints: FlutterBreakpointsEditor(controller: store.flutter)
            }
        }
        .sheet(
            item: Binding(
                get: { store.editing.editPreview }, set: { if $0 == nil { store.editing.cancelLanguagePreview() } })
        ) { preview in
            LanguageEditPreviewView(editing: store.editing, preview: preview)
        }
        .ignoresSafeArea(.container, edges: .all)
    }

    private func toolRail(leading: Bool) -> some View {
        WorkbenchToolRail(
            leading: leading, docking: store.docking, session: store.dockingSession,
            toggle: { store.docking.toggle($0) }, move: { store.docking.move($0, to: $1, at: $2) }
        )
        .frame(width: WorkbenchMetrics.stripeWidth).frame(maxHeight: .infinity)
    }

    @ViewBuilder private func toolPanel(_ tool: WorkbenchTool) -> some View {
        switch tool {
        case .project: projectPanel
        case .information: informationPanel
        case .openTabs: openTabsPanel
        case .workspace: workspacePanel
        case .analysis:
            VStack(spacing: 0) {
                toolPanelHeader(.analysis)
                WorkbenchSeparator()
                LanguageAnalysisPanel(store: store)
            }
        case .problems:
            VStack(spacing: 0) {
                toolPanelHeader(.problems)
                WorkbenchSeparator()
                WorkspaceProblemsPanel(
                    model: store.problems, analysis: store.web.projectAnalysis, dart: store.dart, native: store.native,
                    controller: store.languageController, navigate: store.navigateSemantic)
            }
        case .structure:
            VStack(spacing: 0) {
                toolPanelHeader(.structure)
                WorkbenchSeparator()
                DartStructurePanel(
                    controller: store.activeDocument?.semantic?.controller ?? store.languageController,
                    document: store.activeDocument)
            }
        case .debug:
            FlutterDebugPanel(controller: store.flutter, headerHeight: panelHeaderHeight(.debug)) {
                store.docking.hide(.debug)
            }
        case .codex:
            CodexPanel(controller: store.codex, headerHeight: panelHeaderHeight(.codex)) {
                store.docking.hide(.codex)
            }
        default:
            VStack(spacing: 0) {
                toolPanelHeader(tool)
                WorkbenchSeparator()
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WorkbenchColors.panel)
        }
    }

    private var projectPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                WorkbenchMenuButton(title: "项目菜单", items: projectMenu) {
                    HStack(spacing: 5) {
                        Text("项目").font(.system(size: WorkbenchMetrics.uiFontSize, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }
                    .frame(height: 26)
                }
                .fixedSize()
                Spacer()
                WorkbenchIconButton(title: "刷新目录 ⌘R", symbol: "arrow.clockwise", size: 24, action: store.refresh)
                    .disabled(store.rootURL == nil)
                WorkbenchIconButton(
                    title: "收起所有目录", symbol: "chevron.up.chevron.down", size: 24,
                    action: store.collapseDirectories
                ).disabled(store.rootURL == nil)
                WorkbenchMenuButton(title: "项目选项", items: projectMenu) {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                WorkbenchIconButton(title: "隐藏文件列表 ⌘1", symbol: "minus", size: 24) {
                    store.docking.hide(.project)
                }
            }
            .padding(.leading, 12).padding(.trailing, 6)
            .frame(height: panelHeaderHeight(.project))
            if store.rootURL == nil {
                VStack(alignment: .leading, spacing: 14) {
                    Text("还没有打开的项目").foregroundStyle(WorkbenchColors.secondary)
                    Button(action: store.chooseProject) {
                        Label("打开目录…", systemImage: "folder.badge.plus")
                            .padding(.horizontal, 8).frame(height: 28)
                    }
                    .buttonStyle(WorkbenchButtonStyle())
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NativeProjectTree(
                    store: store, revision: store.treeRevision, visible: store.docking.isVisible(.project),
                    selectedPath: store.location?.path
                )
                .id(store.sessionID)
                // Match the left gutter to the right outer inset + reserved
                // vertical scrollbar. Keep the bottom lane inside the island.
                .padding(.leading, WorkbenchMetrics.treeOuterInset + WorkbenchMetrics.scrollerWidth)
                .padding(.trailing, WorkbenchMetrics.treeOuterInset)
                .padding(.top, WorkbenchMetrics.treeTopInset)
                .padding(.bottom, WorkbenchMetrics.scrollerWidth)
            }
        }
        .foregroundStyle(WorkbenchColors.text)
        .background(WorkbenchColors.panel)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabs
            if !store.tabs.tabs.isEmpty {
                WorkbenchMenuButton(
                    title: "已打开的标签",
                    items: store.tabs.tabs.map { tab in
                        WorkbenchMenuItem(title: tab.location.path.isEmpty ? store.projectName : tab.location.path) {
                            store.activateTab(tab.id)
                        }
                    }
                ) {
                    Image(systemName: "chevron.down").font(.system(size: 10)).frame(width: 26, height: 26)
                }
                WorkbenchMenuButton(title: "标签选项", items: tabMenu) {
                    Image(systemName: "ellipsis").frame(width: 26, height: 26)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: WorkbenchMetrics.tabHeight)
        .foregroundStyle(WorkbenchColors.secondary)
        .background(WorkbenchColors.canvas)
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    if store.rootURL == nil {
                        Label("欢迎", systemImage: "square.grid.2x2")
                            .font(.system(size: WorkbenchMetrics.uiFontSize)).padding(.horizontal, 12).frame(height: 28)
                            .foregroundStyle(WorkbenchColors.text)
                            .background(WorkbenchColors.tab, in: RoundedRectangle(cornerRadius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5).strokeBorder(
                                    WorkbenchColors.tabBorder, lineWidth: 1 / displayScale)
                            }
                            .padding(.horizontal, 4).frame(height: WorkbenchMetrics.tabHeight)
                    }
                    ForEach(store.tabs.tabs) { tab in
                        WorkbenchTab(
                            tab: tab, projectName: store.projectName, active: store.tabs.activeID == tab.id,
                            activate: { store.activateTab(tab.id) }, pin: { store.pinTab(tab.id) },
                            close: { store.closeTab(tab.id) },
                            dirty: store.editing.documents[tab.location.path]?.isDirty ?? false
                        )
                        .id(tab.id)
                    }
                }
            }
            .onChange(of: store.tabs.activeID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            if !store.tabs.tabs.isEmpty {
                tabBar
                WorkbenchSeparator()
            }
            content.frame(minHeight: 180, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        if store.rootURL == nil {
            welcome
        } else if let tab = store.tabs.active, case .file(let entry) = tab.location {
            if let image = store.editing.images[entry.relativePath] {
                ImagePreviewPanel(document: image).id(image.id)
            } else if let video = store.editing.videos[entry.relativePath] {
                VideoPreviewPanel(document: video).id(video.id)
            } else if let document = store.editing.documents[entry.relativePath] {
                EditorPanel(document: document, reload: store.reloadActiveDocument)
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).background(WorkbenchColors.canvas)
        }
    }

    private var informationPanel: some View {
        VStack(spacing: 0) {
            toolPanelHeader(.information)
            WorkbenchSeparator()
            FileInformationView(entry: store.informationEntry, rootURL: store.rootURL)
        }
    }

    private var openTabsPanel: some View {
        VStack(spacing: 0) {
            toolPanelHeader(.openTabs)
            WorkbenchSeparator()
            if store.tabs.tabs.isEmpty {
                panelEmpty("还没有打开的标签", symbol: "rectangle.stack")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.tabs.tabs) { tab in
                            HStack(spacing: 6) {
                                Button {
                                    store.activateTab(tab.id)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: tab.location.isDirectory ? "folder" : "doc")
                                            .foregroundStyle(WorkbenchColors.secondary)
                                        Text(tab.location.path.isEmpty ? store.projectName : tab.location.path)
                                            .lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, 10).frame(maxWidth: .infinity).frame(height: 28)
                                }
                                .buttonStyle(WorkbenchButtonStyle(active: store.tabs.activeID == tab.id))
                                WorkbenchIconButton(title: "关闭标签", symbol: "xmark", size: 22) { store.closeTab(tab.id) }
                            }
                            .padding(.trailing, 6)
                        }
                    }
                    .background(WorkbenchScrollStyle())
                }
            }
        }
        .font(.system(size: WorkbenchMetrics.uiFontSize))
        .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }

    private var workspacePanel: some View {
        VStack(spacing: 0) {
            toolPanelHeader(.workspace)
            WorkbenchSeparator()
            if let root = store.rootURL {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(store.projectName, systemImage: "folder").fontWeight(.medium)
                        Text(root.path).foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                        HStack(spacing: 18) {
                            Text("已打开 \(store.tabs.tabs.count) 个标签")
                            Text("已读取 \(store.snapshots.count) 个目录")
                        }
                        .foregroundStyle(WorkbenchColors.secondary)
                        Label("文本编辑", systemImage: "doc.text").foregroundStyle(WorkbenchColors.secondary)
                    }
                    .font(.system(size: WorkbenchMetrics.uiFontSize)).padding(12).frame(
                        maxWidth: .infinity, alignment: .leading
                    )
                    .background(WorkbenchScrollStyle())
                }
            } else {
                panelEmpty("打开项目后查看目录与标签概览", symbol: "folder")
            }
        }
        .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }

    private func panelHeaderHeight(_ tool: WorkbenchTool) -> CGFloat {
        store.docking.corner(of: tool)?.isTop == false ? WorkbenchMetrics.panelHeaderHeight : WorkbenchMetrics.tabHeight
    }

    private func toolPanelHeader(_ tool: WorkbenchTool) -> some View {
        HStack {
            Text(tool.title).font(.system(size: WorkbenchMetrics.uiFontSize, weight: .semibold))
            Spacer(minLength: 4)
            WorkbenchIconButton(title: "隐藏\(tool.title)", symbol: "minus", size: 24) { store.docking.hide(tool) }
        }
        .padding(.leading, 12).padding(.trailing, 6).frame(height: panelHeaderHeight(tool))
        .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }

    private func panelEmpty(_ title: String, symbol: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: WorkbenchMetrics.uiFontSize)).foregroundStyle(WorkbenchColors.secondary).padding(12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectMenu: [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(title: "显示隐藏文件", checked: store.includeHidden) { store.includeHidden.toggle() },
            WorkbenchMenuItem(title: "打开项目目录…", action: store.chooseProject),
            WorkbenchMenuItem(title: "刷新目录", enabled: store.rootURL != nil, action: store.refresh),
        ]
    }

    private var tabMenu: [WorkbenchMenuItem] {
        guard let tab = store.tabs.active else { return [] }
        var items: [WorkbenchMenuItem] = []
        if tab.isPreview { items.append(WorkbenchMenuItem(title: "固定标签") { store.pinTab(tab.id) }) }
        items.append(WorkbenchMenuItem(title: "关闭标签") { store.closeTab(tab.id) })
        return items
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if store.rootURL != nil {
                WorkspaceProblemsSummary(
                    model: store.problems, analysis: store.web.projectAnalysis, dart: store.dart, native: store.native,
                    show: store.showProblems)
                WorkbenchSeparator(vertical: true).frame(height: 12)
            }
            if store.rootURL != nil {
                breadcrumbs
            } else {
                Text("HyCode").fontWeight(.medium)
                Spacer()
            }
            if store.isLoading {
                Text("正在读取目录…").fixedSize()
            } else if let count = store.currentSnapshot?.entries.count {
                Text("\(count) 项").fixedSize()
            }
            if store.includeHidden { Text("包含隐藏文件").fixedSize() }
            WorkbenchSeparator(vertical: true).frame(height: 12)
            if let document = store.activeDocument {
                Text(document.status).fixedSize()
                Text(document.encoding == "utf8" ? "UTF-8" : "UTF-16")
                Text(document.lineEnding)
                if !document.syntaxLanguage.isEmpty {
                    Text(document.syntaxLanguage).help(document.syntaxNotice ?? "语法高亮")
                }
            } else if let video = store.activeVideo {
                Text(video.status).fixedSize()
                if let metadata = video.metadata {
                    Text(ByteCountFormatter.string(fromByteCount: metadata.bytes, countStyle: .file))
                }
            } else if let image = store.activeImage {
                Text(image.status).fixedSize()
                if !image.format.isEmpty { Text(image.format) }
                if image.byteCount > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file))
                }
            } else {
                Label("文本编辑", systemImage: "doc.text").fixedSize()
            }
            WorkbenchSeparator(vertical: true).frame(height: 12)
            WorkbenchResourceStatus(store: store).frame(maxWidth: 190)
        }
        .font(.system(size: WorkbenchMetrics.statusFontSize)).foregroundStyle(WorkbenchColors.secondary)
        .padding(.horizontal, 12).frame(height: WorkbenchMetrics.statusHeight)
        .background(WorkbenchColors.chrome)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                Image(systemName: "folder").foregroundStyle(Color(nsColor: WorkbenchColors.nativeFolder))
                breadcrumb(store.projectName) { store.navigate(.directory(""), preview: true) }
                let parts = (store.location?.path ?? "").split(separator: "/").map(String.init)
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(WorkbenchColors.muted)
                    if index == parts.count - 1, store.location?.isDirectory == false {
                        Text(part).foregroundStyle(WorkbenchColors.text)
                    } else {
                        breadcrumb(part) {
                            store.navigate(.directory(parts.prefix(index + 1).joined(separator: "/")), preview: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breadcrumb(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).padding(.horizontal, 3).frame(height: 20) }
            .buttonStyle(WorkbenchButtonStyle())
    }

    private var welcome: some View { WorkbenchWelcomeView(store: store) }
}
