import HyCodeWorkspace
import SwiftUI

struct GitDialogContent: View {
    let kind: GitToolDialog
    @Bindable var controller: GitWorkspaceController
    @State private var search = ""
    @State private var branchName = ""
    @State private var authorName = ""
    @State private var authorEmail = ""
    @State private var remoteName = "origin"
    @State private var remoteURL = ""
    @State private var removing: String?
    var body: some View {
        VStack(spacing: 0) {
            WorkbenchDialogHeader(
                title: kind == .branch ? "Git 分支" : kind == .settings ? "仓库身份与远端" : "预览推送",
                symbol: "arrow.triangle.branch")
            WorkbenchSeparator()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if kind == .branch { branches } else if kind == .settings { settings } else { push }
                    GitOperationFeedback(controller: controller)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(WorkbenchScrollStyle())
            WorkbenchSeparator()
            HStack {
                if kind == .push {
                    Text("推送来源固定为预览中的提交对象").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                }
                Spacer()
                Button("关闭") { controller.dialog = nil }.keyboardShortcut(.cancelAction).disabled(controller.writing)
                if kind == .push {
                    Button("推送", action: controller.push).buttonStyle(WorkbenchActionButtonStyle(primary: true))
                        .disabled(
                            controller.writing || controller.pushPreviewLoading || controller.pushPreview == nil
                                || controller.pushPreview?.targetBranch != controller.pushTarget
                                || controller.pushPreview?.remote != controller.selectedRemote)
                }
            }.padding(12)
        }.workbenchContentStyle().frame(width: 580, height: kind == .settings ? 570 : 440)
    }
    private var branches: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前：" + controller.branchTitle).fontWeight(.semibold)
            HStack {
                TextField("新分支名称", text: $branchName)
                Button("创建并切换") { controller.createBranch(branchName) }.disabled(
                    controller.writing || branchName.isEmpty || controller.snapshot?.head == nil)
            }
            WorkbenchSeparator(visible: true)
            TextField("搜索本地或远端分支", text: $search)
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(
                    controller.references.filter {
                        !$0.tag && (search.isEmpty || $0.shortName.localizedCaseInsensitiveContains(search))
                    }
                ) { reference in
                    HStack {
                        Label(reference.shortName, systemImage: reference.remote ? "cloud" : "arrow.triangle.branch")
                        if reference.current { Text("当前").foregroundStyle(WorkbenchColors.accent) }
                        Spacer()
                        Button(reference.remote ? "建立跟踪并切换" : "切换") { controller.switchBranch(reference) }.disabled(
                            controller.writing || reference.current)
                    }.padding(.vertical, 3)
                }
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前仓库：" + (controller.snapshot?.repository.root.path ?? "")).font(.system(size: 11)).foregroundStyle(
                WorkbenchColors.secondary
            ).textSelection(.enabled)
            Text("提交身份（仅当前仓库）").fontWeight(.semibold)
            TextField("作者姓名", text: $authorName)
            TextField("作者邮箱", text: $authorEmail)
            Button("保存仓库身份") { controller.setIdentity(name: authorName, email: authorEmail) }.disabled(
                controller.writing || authorName.isEmpty || authorEmail.isEmpty)
            WorkbenchSeparator(visible: true)
            Text("远端").fontWeight(.semibold)
            if let issue = controller.remoteIssue {
                Text(issue).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(
                    horizontal: false, vertical: true)
            }
            ForEach(controller.remotes) { remote in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(remote.name)
                        Text(remote.fetchURL).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("编辑") {
                        remoteName = remote.name
                        remoteURL = remote.fetchURL
                    }
                    Button("删除…") { removing = remote.name }.disabled(controller.writing)
                }
            }
            if let removing {
                HStack {
                    Text("删除远端 \(removing)？")
                    Button("取消") { self.removing = nil }
                    Button("确认删除") {
                        controller.removeRemote(removing)
                        self.removing = nil
                    }
                }
            }
            HStack {
                TextField("远端名", text: $remoteName).frame(width: 110)
                TextField("SSH / HTTPS / 本地仓库地址", text: $remoteURL)
            }
            Button("保存远端") { controller.setRemote(name: remoteName, url: remoteURL) }.disabled(
                controller.writing || remoteName.isEmpty || remoteURL.isEmpty)
            Text(
                "此版本独立读取仓库配置；不修改系统 Git 配置或系统钥匙串。SSH 使用已解锁的 agent 和已有 known_hosts，不读取私钥或弹出认证；HTTPS 仅支持无需交互凭据的操作。带项目 hooks、签名或内容过滤器的写入会明确停止，使用专用 Git 工具完成。"
            ).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary).fixedSize(
                horizontal: false, vertical: true)
        }
    }
    private var push: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WorkbenchMenuButton(
                    title: "选择推送远端",
                    items: controller.remotes.map { remote in
                        WorkbenchMenuItem(title: remote.name, checked: controller.selectedRemote == remote.name) {
                            controller.selectedRemote = remote.name
                            controller.updatePushPreview()
                        }
                    }
                ) { Text(controller.selectedRemote + " ▾").frame(minWidth: 100, minHeight: 28) }
                TextField("目标分支", text: $controller.pushTarget).onSubmit { controller.updatePushPreview() }
                Button("更新预览", action: controller.updatePushPreview).disabled(controller.writing)
            }
            if let remote = controller.remotes.first(where: { $0.name == controller.selectedRemote }) {
                Text(remote.pushURL).font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary).textSelection(
                    .enabled)
            }
            if controller.pushPreviewLoading { ProgressView("正在读取待推送提交…") }
            if let plan = controller.pushPreview {
                Text("\(plan.localBranch) → \(plan.remote)/\(plan.targetBranch)").fontWeight(.semibold)
                Text(plan.head).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                if plan.setUpstream {
                    Text("成功后为未配置上游的本地分支设置此目标").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                }
                Text("以下为本地已知引用的待推送记录；未自动获取远端，最多显示 200 条。远端有新变化时由 Git 拒绝非快进推送。").font(.system(size: 11))
                    .foregroundStyle(WorkbenchColors.secondary)
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.commits) { commit in
                        HStack {
                            Text(String(commit.object.prefix(8))).font(.system(size: 11, design: .monospaced))
                            Text(commit.subject).lineLimit(2)
                        }
                    }
                }
            }
        }
    }
}

struct GitBranchButton: View {
    @Bindable var store: WorkbenchStore
    var body: some View {
        WorkbenchMenuButton(
            title: "Git 分支与操作",
            items: [
                WorkbenchMenuItem(title: "提交…") { store.revealGitCommit() },
                WorkbenchMenuItem(title: "显示 Git 日志") { store.revealGitLog() },
                WorkbenchMenuItem(title: "分支搜索 / 创建 / 切换…", enabled: store.git.ready && !store.git.writing) {
                    store.git.dialog = .branch
                },
                .separator,
                WorkbenchMenuItem(
                    title: "获取远端分支", enabled: store.git.ready && !store.git.writing, action: store.git.fetch),
                WorkbenchMenuItem(
                    title: "仅快进拉取", enabled: store.git.ready && !store.git.writing, action: store.git.pull),
                WorkbenchMenuItem(
                    title: "预览并推送…", enabled: store.git.ready && !store.git.writing, action: store.git.requestPush),
                WorkbenchMenuItem(title: "仓库身份与远端…", enabled: store.git.ready) { store.git.dialog = .settings },
            ]
        ) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                Text(store.git.branchTitle).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 13)).frame(maxWidth: 200).padding(.horizontal, 5).frame(height: 28)
        }.disabled(!store.git.available)
    }
}
