import HyCodeWorkspace
import SwiftUI

struct WorkspaceProblemsSummary: View {
    let model: WorkspaceProblemsController
    let analysis: ProjectAnalysisController
    let dart: DartWorkspaceController
    let show: (ProblemCategory?) -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button {
                show(.error)
            } label: {
                Label("\(model.snapshot.errors)", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }.help("项目错误")
            Button {
                show(.warning)
            } label: {
                Label("\(model.snapshot.warnings)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(
                    .orange)
            }.help("项目警告")
            Button {
                show(.suggestion)
            } label: {
                Label("\(model.snapshot.suggestions)", systemImage: "lightbulb").foregroundStyle(.secondary)
            }.help("项目信息与建议")
            if analysis.running || dart.analyzing { Text("分析中…").foregroundStyle(WorkbenchColors.secondary) }
            if model.limited || analysis.limited || analysis.blockedVue > 0 || analysis.unreadable > 0
                || analysis.watchUnavailable || analysis.skipped > 0
            {
                Image(systemName: "ellipsis.circle").help("部分检查范围不可用，查看问题面板")
            }
        }.buttonStyle(WorkbenchStatusButtonStyle()).help(analysis.state).fixedSize()
    }
}

struct WorkspaceProblemsPanel: View {
    @Bindable var model: WorkspaceProblemsController
    let analysis: ProjectAnalysisController
    let dart: DartWorkspaceController
    let controller: any EditorLanguageController
    let navigate: (LSPLocation) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                filter("全部", category: nil)
                filter("错误 \(model.snapshot.errors)", category: .error)
                filter("警告 \(model.snapshot.warnings)", category: .warning)
                filter("建议 \(model.snapshot.suggestions)", category: .suggestion)
                Spacer(minLength: 0)
                WorkbenchIconButton(title: "重新检查", symbol: "arrow.clockwise", action: analysis.rescan)
            }.padding(.horizontal, 8).frame(height: 34)
            WorkbenchSeparator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !controller.locations.isEmpty {
                        HStack {
                            Text("导航结果 · \(controller.locations.count)")
                            Spacer()
                            Button("清除", action: controller.clearLocations)
                        }
                        ForEach(controller.locations) { target in
                            Button {
                                navigate(target)
                            } label: {
                                Label(
                                    "\(URL(string: target.uri)?.lastPathComponent ?? target.uri):\(target.range.start.line + 1)",
                                    systemImage: "arrow.turn.down.right"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading).padding(5)
                            }
                        }
                        WorkbenchSeparator()
                    }
                    Text(analysis.state).foregroundStyle(WorkbenchColors.secondary)
                    Text(dart.status).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                    if controller is WebWorkspaceController {
                        Text(controller.status).font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                    }
                    if model.limited || analysis.limited || analysis.skipped > 0 || analysis.blockedVue > 0
                        || analysis.unreadable > 0 || analysis.watchUnavailable
                    {
                        Text("当前结果有范围/数量限制，不能视为全项目检查通过。").foregroundStyle(.orange)
                    }
                    if model.snapshot.groups.isEmpty {
                        Text(analysis.running ? "正在接收项目诊断…" : "当前筛选下没有收到问题")
                            .foregroundStyle(WorkbenchColors.secondary).padding(.vertical, 10)
                    }
                    ForEach(model.snapshot.groups) { group in
                        Text(group.path + " · \(group.rows.count)").fontWeight(.semibold).padding(.top, 8)
                            .textSelection(.enabled)
                        ForEach(group.rows) { item in
                            Button {
                                navigate(item.target)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(
                                        systemName: item.category == .error
                                            ? "xmark.circle.fill"
                                            : item.category == .warning ? "exclamationmark.triangle.fill" : "lightbulb"
                                    )
                                    .foregroundStyle(
                                        item.category == .error
                                            ? Color.red
                                            : item.category == .warning ? Color.orange : WorkbenchColors.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.message).lineLimit(3)
                                        Text(
                                            "\(item.target.range.start.line + 1):\(item.target.range.start.character + 1) · "
                                                + item.source
                                        )
                                        .font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                            }.help(item.message)
                        }
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(WorkbenchScrollStyle())
            }
        }.font(.system(size: 13)).foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
            .buttonStyle(WorkbenchButtonStyle())
    }
    private func filter(_ title: String, category: ProblemCategory?) -> some View {
        WorkbenchSectionTab(title: title, active: model.category == category) { model.category = category }
    }
}
