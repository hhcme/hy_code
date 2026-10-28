import AppKit
import HyCodeWorkspace
import SwiftUI

struct CodexChangeReview: Identifiable {
    let id = UUID()
    let files: [CodexFileChange]
    var selectedPath: String?
    var reportedFileCount: Int?
}

/// Captured protocol diffs only. Opening this view never reads/reverts a file,
/// starts a process, or treats a model-supplied path as workspace permission.
struct CodexChangeReviewView: View {
    let review: CodexChangeReview
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String?
    @State private var lines: [String] = []
    @State private var omitted = false
    private var file: CodexFileChange? {
        review.files.first { $0.path == (selected ?? review.selectedPath) } ?? review.files.first
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("更改").font(.system(size: 14, weight: .semibold))
                Text("\(review.reportedFileCount ?? review.files.count) 个文件").font(.system(size: 11)).foregroundStyle(
                    CodexAppearance.secondary)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider().overlay(CodexAppearance.border)
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(review.files.enumerated()), id: \.offset) { _, item in
                            Button {
                                selected = item.path
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text((item.path as NSString).lastPathComponent).font(.system(size: 11)).lineLimit(1)
                                    HStack(spacing: 5) {
                                        Text("+\(item.added)").foregroundStyle(CodexAppearance.green)
                                        Text("-\(item.removed)").foregroundStyle(CodexAppearance.red)
                                    }.font(.system(size: 10, design: .monospaced))
                                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        file?.path == item.path ? CodexAppearance.border : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(CodexQuietButtonStyle()).help(item.path)
                        }
                    }.padding(8)
                }.frame(width: 170)
                Rectangle().fill(CodexAppearance.border).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    if let file {
                        HStack {
                            Text(file.path).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(file.diff, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").padding(5)
                            }
                            .buttonStyle(CodexQuietButtonStyle()).help("复制完整差异")
                        }.padding(12)
                        Divider().overlay(CodexAppearance.border)
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                    Text(verbatim: line.isEmpty ? " " : line).font(
                                        .system(size: 11, design: .monospaced)
                                    )
                                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                                    .foregroundStyle(
                                        line.hasPrefix("+")
                                            ? CodexAppearance.green
                                            : line.hasPrefix("-") ? CodexAppearance.red : CodexAppearance.text
                                    )
                                    .padding(.horizontal, 12).padding(.vertical, 2)
                                }
                            }.padding(.vertical, 8)
                        }
                        if omitted {
                            Text("仅显示前 4096 行；复制可取得完整的已记录差异。")
                                .font(.system(size: 10)).foregroundStyle(CodexAppearance.secondary).padding(10)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(
                (review.reportedFileCount ?? 0) > review.files.count
                    ? "这是 Agent 报告的差异快照；仅列出前 \(review.files.count) 个文件。" : "这是 Agent 报告的差异快照。"
            )
            .font(.system(size: 10)).foregroundStyle(CodexAppearance.secondary).padding(10)
        }.frame(width: 680, height: 520).foregroundStyle(CodexAppearance.text).background(CodexAppearance.background)
            .task(id: file) {
                let text = file?.diff ?? ""
                let task = Task.detached(priority: .utility) { Array(text.components(separatedBy: "\n").prefix(4097)) }
                let result = await withTaskCancellationHandler(
                    operation: { await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled else { return }
                omitted = result.count > 4096
                lines = Array(result.prefix(4096))
            }
    }
}
