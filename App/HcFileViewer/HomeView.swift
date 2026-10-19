import SwiftUI
import HcLibrary
import UniformTypeIdentifiers

/// 首页：最近打开列表 + 入库入口。功能保持克制，入口只留一个“打开文件”。
struct HomeView: View {
    @StateObject private var store = LibraryStore()

    @State private var isImporting = false
    @State private var selectedItem: RecentItem?
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("最近打开")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isImporting = true
                        } label: {
                            Label("打开文件", systemImage: "folder.badge.plus")
                        }
                        .keyboardShortcut("o", modifiers: .command)
                    }
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: false
                ) { result in
                    handleImport(result)
                }
                .sheet(item: $selectedItem) { item in
                    ArchiveView(item: item, fileURL: store.url(for: item))
                }
                .alert(
                    "导入失败",
                    isPresented: Binding(
                        get: { importErrorMessage != nil },
                        set: { if !$0 { importErrorMessage = nil } }
                    ),
                    presenting: importErrorMessage
                ) { _ in
                    Button("好", role: .cancel) {}
                } message: { message in
                    Text(message)
                }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if store.recents.isEmpty {
            ContentUnavailableView(
                "还没有文件",
                systemImage: "tray",
                description: Text("打开的文件会复制到应用内文件库")
            )
        } else {
            List(store.recents) { item in
                RecentRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedItem = item }
            }
            .listStyle(.inset)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedItem = try store.importFile(at: url)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct RecentRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.addedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
