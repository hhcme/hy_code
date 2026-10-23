import HyCodeWorkspace
import SwiftUI

struct FileInformationView: View {
    let entry: WorkspaceEntry?
    let rootURL: URL?
    var prominent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: prominent ? 22 : 12) {
                if let entry {
                    HStack(spacing: 12) {
                        Image(systemName: entry.symbol)
                            .font(.system(size: prominent ? 26 : 16))
                            .foregroundStyle(Color(nsColor: entry.symbolColor))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.relativePath.isEmpty ? rootURL?.lastPathComponent ?? entry.name : entry.name)
                                .font(.system(size: prominent ? 18 : 13, weight: .semibold))
                            if prominent {
                                Text("文件信息").font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                            }
                        }
                        Spacer()
                        if prominent {
                            Label("只读", systemImage: "lock").font(.system(size: 11))
                                .foregroundStyle(WorkbenchColors.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(WorkbenchColors.panel, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    WorkbenchSeparator()
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                        infoRow("类型", value: entry.kindLabel)
                        infoRow("位置", value: entry.relativePath.isEmpty ? "项目根目录" : entry.relativePath)
                        infoRow("完整路径", value: absolutePath(entry))
                        infoRow("大小", value: entry.sizeLabel)
                        infoRow("修改时间", value: entry.modifiedLabel)
                        if entry.kind == .symlink { infoRow("链接策略", value: "显示链接，不跟随目标") }
                    }
                } else {
                    Label("选择一个文件或目录查看信息", systemImage: "info.circle")
                        .foregroundStyle(WorkbenchColors.secondary)
                }
            }
            .padding(prominent ? 24 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkbenchScrollStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: 13)).foregroundStyle(WorkbenchColors.text)
        .background(WorkbenchColors.canvas)
    }

    private func absolutePath(_ entry: WorkspaceEntry) -> String {
        guard let rootURL else { return entry.relativePath }
        return entry.url(relativeTo: rootURL).path
    }

    private func infoRow(_ title: String, value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(WorkbenchColors.secondary).frame(width: 76, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(prominent ? nil : 3)
        }
    }
}
