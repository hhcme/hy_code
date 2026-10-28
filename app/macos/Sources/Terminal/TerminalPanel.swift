import HyCodeWorkspace
import SwiftUI

struct TerminalPanel: View {
    @Bindable var controller: TerminalWorkspaceController
    let visible: Bool
    let headerHeight: CGFloat
    let hide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Text("终端").font(.system(size: 12, weight: .semibold)).padding(.leading, 10)
                Spacer(minLength: 0)
                WorkbenchIconButton(title: "新建终端", symbol: "plus", size: 24) { controller.newTab() }
                    .disabled(!controller.canCreate)
                WorkbenchMenuButton(title: "终端操作", items: menu) {
                    Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 24, height: 24)
                }
                WorkbenchIconButton(title: "终端设置", symbol: "gearshape", size: 24) { controller.showingSettings = true }
                WorkbenchIconButton(title: "收起终端", symbol: "minus", size: 24, action: hide)
            }.padding(.trailing, 5).frame(height: headerHeight).background(WorkbenchColors.chrome)
            WorkbenchSeparator()
            if !controller.tabs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(controller.tabs) { tab in
                            HStack(spacing: 1) {
                                Button {
                                    controller.selectTab(tab.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "terminal").font(.system(size: 11))
                                        Text(tab.title).font(.system(size: 12)).lineLimit(1)
                                    }.padding(.leading, 8).padding(.trailing, 5).frame(height: 26)
                                }.buttonStyle(
                                    WorkbenchButtonStyle(active: tab.id == controller.activeTabID, neutral: true))
                                WorkbenchIconButton(title: "关闭 \(tab.title)", symbol: "xmark", size: 22) {
                                    controller.closeTab(tab)
                                }
                            }
                            .padding(.trailing, 3)
                            .background(
                                tab.id == controller.activeTabID ? WorkbenchColors.tab : .clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                            .help(controller.tabDetail(tab))
                            .workbenchContextMenu([
                                WorkbenchMenuItem(title: "重命名…", action: { controller.rename(tab) }),
                                WorkbenchMenuItem(title: "关闭标签", action: { controller.closeTab(tab) }),
                            ])
                        }
                    }.padding(.horizontal, 6).padding(.vertical, 3)
                }.scrollIndicators(.hidden).fixedSize(horizontal: false, vertical: true)
                WorkbenchSeparator()
            }
            if let tab = controller.activeTab {
                splitContent(tab.layout)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "terminal").font(.system(size: 28, weight: .light)).foregroundStyle(
                        WorkbenchColors.secondary)
                    Text("在项目中运行命令").font(.system(size: 13, weight: .medium))
                    Text("新建本地 Shell 会话，支持多标签与分屏。")
                        .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                    Button("新建终端") { controller.newTab() }.buttonStyle(WorkbenchActionButtonStyle(primary: true))
                        .disabled(!controller.canCreate)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = controller.error {
                HStack {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer(minLength: 0)
                    WorkbenchIconButton(title: "关闭提示", symbol: "xmark", size: 20) { controller.error = nil }
                }.padding(.horizontal, 8).padding(.vertical, 3).background(WorkbenchColors.chrome)
            }
        }
        .foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
        .sheet(isPresented: $controller.showingSettings) { TerminalSettingsView(controller: controller) }
        .onChange(of: visible) { _, shown in if shown { controller.focus() } }
    }
    private var menu: [WorkbenchMenuItem] {
        [
            WorkbenchMenuItem(
                title: "向右分屏", enabled: controller.canCreate && controller.activeTab != nil,
                action: { controller.split(.horizontal) }),
            WorkbenchMenuItem(
                title: "向下分屏", enabled: controller.canCreate && controller.activeTab != nil,
                action: { controller.split(.vertical) }),
            .separator,
            WorkbenchMenuItem(
                title: "查找输出", enabled: controller.activeSession != nil,
                action: { controller.activeSession?.searching = true }),
            WorkbenchMenuItem(
                title: "清除滚动历史", enabled: controller.activeSession != nil,
                action: { controller.activeSession?.view.clearScrollback() }),
            WorkbenchMenuItem(
                title: "重命名标签…", enabled: controller.activeTab != nil,
                action: { if let tab = controller.activeTab { controller.rename(tab) } }),
            WorkbenchMenuItem(
                title: "关闭当前分屏", enabled: controller.activeTab != nil,
                action: { if let pane = controller.activeTab?.activePane { controller.closePane(pane) } }),
        ]
    }
    private func splitContent(_ layout: TerminalSplitLayout) -> AnyView {
        switch layout {
        case .pane(let id):
            if let session = controller.sessions[id] {
                return AnyView(
                    TerminalPaneView(
                        session: session, active: controller.activeTab?.activePane == id, visible: visible,
                        close: { controller.closePane(id) }
                    ).id(ObjectIdentifier(session)))
            }
            return AnyView(Color.clear)
        case .split(let axis, let first, let second):
            if axis == .horizontal {
                return AnyView(
                    HSplitView {
                        splitContent(first).frame(minWidth: 140)
                        splitContent(second).frame(minWidth: 140)
                    })
            }
            return AnyView(
                VSplitView {
                    splitContent(first).frame(minHeight: 90)
                    splitContent(second).frame(minHeight: 90)
                })
        }
    }
}

private struct TerminalPaneView: View {
    @Bindable var session: TerminalPaneSession
    let active: Bool
    let visible: Bool
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if session.searching {
                HStack(spacing: 5) {
                    TextField("查找终端输出", text: $session.query).textFieldStyle(WorkbenchTextFieldStyle()).focused(
                        $searchFocused
                    ).onSubmit { session.search() }
                    if !session.searchFound {
                        Text("未找到").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                    }
                    WorkbenchIconButton(title: "上一个", symbol: "chevron.up", size: 22) { session.search(next: false) }
                    WorkbenchIconButton(title: "下一个", symbol: "chevron.down", size: 22) { session.search() }
                    WorkbenchIconButton(title: "关闭查找", symbol: "xmark", size: 22) {
                        session.searching = false
                        session.requestFocus()
                    }
                }.padding(5).background(WorkbenchColors.chrome).onAppear { searchFocused = true }
            }
            TerminalNativeHost(session: session, visible: visible).frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { TerminalCompletionOverlay(session: session) }
                .padding(.leading, 8).padding(.trailing, 4).padding(.top, 5).padding(.bottom, 4)
                .overlay(alignment: .bottomTrailing) {
                    if !session.live {
                        Text(session.status).font(.system(size: 10)).foregroundStyle(WorkbenchColors.secondary)
                            .padding(6).allowsHitTesting(false)
                    }
                }
            if let issue = session.issue {
                HStack {
                    Text(issue).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                    Spacer(minLength: 0)
                    WorkbenchIconButton(title: "关闭提示", symbol: "xmark", size: 18) { session.issue = nil }
                }.padding(6).background(WorkbenchColors.chrome)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalSettingsView: View {
    @Bindable var controller: TerminalWorkspaceController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkbenchDialogHeader(title: "终端设置", symbol: "terminal")
            VStack(alignment: .leading, spacing: 12) {
                Text("Shell 可执行文件").fontWeight(.medium)
                TextField("留空使用系统 Shell，例如 /bin/zsh", text: $controller.shellPath)
                Toggle("作为登录 Shell 启动", isOn: $controller.loginShell)
                Toggle("输入时显示命令候选", isOn: $controller.commandCompletion)
                Text("新 zsh 会话支持命令、常用子命令/参数和项目路径候选。Tab 插入，↑↓ 选择，Esc 收起；其他 Shell 保留自身补全。")
                    .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                Text("Shell 设置用于新会话，启动时读取该 Shell 的用户配置。")
                    .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                HStack {
                    Text("字号")
                    Slider(value: $controller.fontSize, in: 10...24, step: 1)
                    Text("\(Int(controller.fontSize))").monospacedDigit().frame(width: 24)
                }
                Text("每个分屏保留最近 2000 行；最多 8 个会话、每标签 4 个分屏。终端输出不保存到项目或磁盘日志。")
                    .font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                HStack {
                    Spacer()
                    Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }.padding([.horizontal, .bottom], 16)
        }.frame(width: 470).workbenchContentStyle()
    }
}
