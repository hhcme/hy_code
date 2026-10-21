import HyCodeWorkspace
import SwiftUI

/// Recent history has one owner in WorkbenchStore. Displaying this page performs
/// no directory reads or bookmark resolution; only a project click opens it.
struct WorkbenchWelcomeView: View {
    @Bindable var store: WorkbenchStore

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                Group {
                    if !store.recentProjects.records.isEmpty, geometry.size.width >= 720 {
                        HStack(alignment: .top, spacing: 36) {
                            actions.frame(width: 260)
                            recentProjects.frame(minWidth: 280, maxWidth: .infinity)
                        }
                        .frame(maxWidth: 820)
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            actions
                            if !store.recentProjects.records.isEmpty { recentProjects }
                        }
                        .frame(maxWidth: 520)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height))
                .background(WorkbenchScrollStyle())
            }
        }
        .foregroundStyle(WorkbenchColors.text)
        .background(WorkbenchColors.canvas)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                HyCodeBrandIcon(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text("HyCode").font(.system(size: 30, weight: .semibold))
                    Text("打开项目，继续工作").font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                }
            }
            Button(action: store.chooseProject) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                    Text("打开项目目录")
                    Spacer(minLength: 8)
                    key("⌘O")
                }
                .padding(.horizontal, 12).frame(height: 38)
            }
            .buttonStyle(WorkbenchButtonStyle(active: true)).frame(width: 260)
            VStack(spacing: 2) {
                ForEach([WorkbenchTool.project, .information, .openTabs, .workspace]) { tool in
                    Button {
                        store.docking.toggle(tool)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tool.symbol).frame(width: 18)
                            Text(tool.title)
                            Spacer(minLength: 8)
                            if let shortcut = tool.shortcut { key("⌘\(shortcut)") }
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                    }
                    .buttonStyle(WorkbenchButtonStyle())
                }
                Button {
                    store.includeHidden.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.includeHidden ? "eye" : "eye.slash").frame(width: 18)
                        Text("显示隐藏文件")
                        Spacer(minLength: 8)
                        key("⇧⌘.")
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                }
                .buttonStyle(WorkbenchButtonStyle(active: store.includeHidden))
            }
            .font(.system(size: 12)).frame(width: 260)
        }
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近项目").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WorkbenchColors.secondary).padding(.horizontal, 12).padding(.bottom, 4)
            LazyVStack(spacing: 2) {
                ForEach(store.recentProjects.records) { project in
                    WorkbenchProjectRow(project: project) { store.switchProject(project) }
                }
            }
        }
    }
    private func key(_ value: String) -> some View {
        Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(WorkbenchColors.secondary)
    }
}
