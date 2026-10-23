import AppKit
import HyCodeWorkspace
import Observation
import SwiftUI

struct WorkbenchProjectSwitcher: View {
    @Bindable var store: WorkbenchStore
    @State private var presented = false
    @State private var model: ProjectPopupModel?
    private var current: RecentProject? { store.currentProject }
    private var title: String { current?.name ?? "打开项目" }
    var body: some View {
        Button {
            guard !presented else {
                presented = false
                return
            }
            model = ProjectPopupModel(store: store) { presented = false }
            presented = true
        } label: {
            HStack(spacing: 6) {
                WorkbenchProjectBadge(project: current, size: 20)
                Text(title).font(.system(size: WorkbenchMetrics.uiFontSize, weight: .medium))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 160)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(WorkbenchColors.secondary)
            }.padding(.horizontal, 5).frame(height: 30)
        }.buttonStyle(WorkbenchButtonStyle(active: presented, neutral: true)).fixedSize()
            .help(current?.path ?? "尚未打开项目，选择项目目录")
            .accessibilityLabel(current.map { "当前项目：\($0.name)，\($0.path)" } ?? "尚未打开项目，打开项目")
            .workbenchPopup(
                isPresented: $presented,
                size: CGSize(width: WorkbenchMetrics.projectPopupWidth, height: model?.height ?? 180),
                keyDown: { model?.keyDown($0) ?? false },
                content: { if let model { ProjectPopupContent(model: model) } })
    }
}
@MainActor @Observable private final class ProjectPopupModel {
    let store: WorkbenchStore
    let current: RecentProject?
    let recent: [RecentProject]
    var selection: ContextMenuSelection
    let close: () -> Void
    var projects: [RecentProject] { (current.map { [$0] } ?? []) + recent }
    var height: CGFloat {
        var list: CGFloat = 16
        if current != nil { list += 80 }
        if !recent.isEmpty {
            list += 28 + CGFloat(recent.count) * WorkbenchMetrics.projectPopupRowHeight + (current == nil ? 0 : 17)
        } else if current == nil {
            list += 40
        }
        return 97 + min(440, list) + (current == nil ? 0 : 41)
    }
    init(store: WorkbenchStore, close: @escaping () -> Void) {
        self.store = store
        current = store.currentProject
        recent = store.recentProjects.records.filter { $0.path != store.currentProject?.path }
        self.close = close
        selection = ContextMenuSelection(
            enabled: [false, true, false]
                + Array(repeating: true, count: recent.count + (current == nil ? 0 : 2)))
    }
    func choose(_ index: Int) {
        guard selection.enabled.indices.contains(index), selection.enabled[index] else { return }
        close()
        if index == 1 {
            Task { @MainActor in
                await Task.yield()
                store.chooseProject()
            }
        } else if projects.indices.contains(index - 3) {
            let project = projects[index - 3]
            if project.path != store.currentProject?.path { store.switchProject(project) }
        } else if current?.path == store.currentProject?.path {
            store.closeProject()
        }
    }
    func keyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 125: selection.move(forward: true)
        case 126: selection.move(forward: false)
        case 48: selection.move(forward: !event.modifierFlags.contains(.shift))
        case 115: selection.edge(last: false)
        case 119: selection.edge(last: true)
        case 36, 76: if let index = selection.index { choose(index) }
        default: return false
        }
        return true
    }
}
private struct ProjectPopupContent: View {
    @Bindable var model: ProjectPopupModel
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                actionRow("新建项目…", symbol: "plus", index: 0, enabled: false).help("暂不支持新建项目")
                actionRow("打开…", symbol: "folder", index: 1)
                actionRow("克隆仓库…", symbol: "arrow.triangle.branch", index: 2, enabled: false)
                    .help("暂不支持克隆仓库")
            }.padding(6)
            WorkbenchSeparator(visible: true).padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let current = model.current {
                            section("打开的项目")
                            projectRow(current, index: 3, active: true)
                        }
                        if !model.recent.isEmpty {
                            if model.current != nil { WorkbenchSeparator(visible: true).padding(.vertical, 8) }
                            section("最近的项目")
                            ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, project in
                                projectRow(project, index: 3 + (model.current == nil ? 0 : 1) + index, active: false)
                            }
                        } else if model.current == nil {
                            Text("还没有最近项目").foregroundStyle(WorkbenchColors.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(
                                    height: 40)
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading).background(WorkbenchScrollStyle())
                }.onChange(of: model.selection.index) { _, index in if let index { proxy.scrollTo(index) } }
            }.frame(maxHeight: .infinity)
            if model.current != nil {
                WorkbenchSeparator(visible: true)
                actionRow("关闭当前项目", symbol: "xmark.circle", index: 3 + model.projects.count).padding(6)
            }
        }.font(.system(size: 13)).foregroundStyle(WorkbenchColors.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(WorkbenchColors.chrome)
    }
    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(WorkbenchColors.secondary)
            .padding(.horizontal, 12).frame(height: 28)
    }
    private func actionRow(_ title: String, symbol: String, index: Int, enabled: Bool = true) -> some View {
        Button {
            model.choose(index)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 15)).frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: 28)
        }.buttonStyle(WorkbenchButtonStyle(active: model.selection.index == index)).disabled(!enabled)
            .onHover { if $0 { model.selection.select(index) } }
    }
    private func projectRow(_ project: RecentProject, index: Int, active: Bool) -> some View {
        WorkbenchProjectRow(project: project, active: active, highlighted: model.selection.index == index) {
            model.choose(index)
        }.onHover { if $0 { model.selection.select(index) } }.id(index)
    }
}
