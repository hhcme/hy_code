import HyCodeWorkspace
import SwiftUI

struct WorkbenchProjectSwitcher: View {
    @Bindable var store: WorkbenchStore
    @State private var presented = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    private var current: RecentProject? { store.currentProject }
    private var recent: [RecentProject] { store.recentProjects.records.filter { $0.path != current?.path } }
    private var title: String { current?.name ?? "打开项目" }
    private var listHeight: CGFloat {
        var height: CGFloat = 16
        if current != nil { height += 28 + 56 }
        if !recent.isEmpty {
            if current != nil { height += 16 + 1 / displayScale }
            height += 28 + CGFloat(recent.count) * 56
        } else if current == nil {
            height += 40
        }
        return min(440, height)
    }

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 6) {
                WorkbenchProjectBadge(project: current, size: 20)
                Text(title).font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 160)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(WorkbenchColors.secondary)
            }
            .padding(.horizontal, 6).frame(height: 30)
        }
        .buttonStyle(WorkbenchButtonStyle(active: presented)).fixedSize()
        .help(current?.path ?? "尚未打开项目，选择项目目录")
        .accessibilityLabel(current.map { "当前项目：\($0.name)，\($0.path)" } ?? "尚未打开项目，打开项目")
        .popover(isPresented: $presented, arrowEdge: .top) {
            popup
        }
    }

    private var popup: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                actionRow("新建项目…", symbol: "plus", enabled: false) {}
                    .help("暂不支持新建项目")
                actionRow("打开…", symbol: "folder") {
                    presented = false
                    Task { @MainActor in
                        await Task.yield()
                        store.chooseProject()
                    }
                }
                actionRow("克隆仓库…", symbol: "arrow.triangle.branch", enabled: false) {}
                    .help("暂不支持克隆仓库")
            }
            .padding(6)
            WorkbenchSeparator().padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let current {
                        section("打开的项目")
                        projectRow(current, active: true)
                    }
                    if !recent.isEmpty {
                        if current != nil { WorkbenchSeparator().padding(.vertical, 8) }
                        section("最近的项目")
                        ForEach(recent) { projectRow($0, active: false) }
                    } else if current == nil {
                        Text("还没有最近项目").foregroundStyle(WorkbenchColors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 40)
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(WorkbenchScrollStyle())
            }
            .frame(height: listHeight)
            if current != nil {
                WorkbenchSeparator()
                Button {
                    presented = false
                    store.closeProject()
                } label: {
                    Label("关闭当前项目", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 32)
                }
                .buttonStyle(WorkbenchButtonStyle()).padding(6)
            }
        }
        .font(.system(size: 13)).foregroundStyle(WorkbenchColors.text)
        .frame(width: 520)
        .background(WorkbenchColors.chrome).preferredColorScheme(colorScheme)
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkbenchColors.secondary)
            .padding(.horizontal, 12).frame(height: 28)
    }
    private func actionRow(_ title: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 26)
        }
        .buttonStyle(WorkbenchButtonStyle()).disabled(!enabled)
    }
    private func projectRow(_ project: RecentProject, active: Bool) -> some View {
        WorkbenchProjectRow(project: project, active: active) {
            presented = false
            if !active { store.switchProject(project) }
        }
    }
}
