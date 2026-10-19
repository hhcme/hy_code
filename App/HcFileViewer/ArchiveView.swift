import SwiftUI
import HcCore
import HcLibrary

/// 压缩包浏览页：调用 Rust core 列出条目。骨架阶段只读目录，后续扩展按需提取。
struct ArchiveView: View {
    let item: RecentItem
    let fileURL: URL

    @State private var entries: [ArchiveEntry]?
    @State private var errorMessage: String?

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 360)
            .navigationTitle(item.name)
            .task { loadEntries() }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView(
                "无法读取压缩包",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if let entries {
            List(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.isDir ? "folder.fill" : "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(entry.name)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer()
                    if !entry.isDir {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        } else {
            ProgressView("正在读取目录")
        }
    }

    private func loadEntries() {
        do {
            entries = try ZipReader.open(path: fileURL.path).entries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
