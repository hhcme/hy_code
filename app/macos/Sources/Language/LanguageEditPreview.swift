import AppKit
import HyCodeWorkspace
import SwiftUI

struct LanguageEditPreview: Identifiable, Sendable {
    struct File: Identifiable, Sendable {
        let path: String
        let documentID: UUID
        let revision: UInt64
        let before: String
        let after: String
        let diff: String
        var id: String { path }
    }
    let id: UUID
    let title: String
    let files: [File]
    let preloaded: [String: UUID]
}

extension EditorWorkspace {
    func previewLanguageEdit(_ edit: JSONValue, feature: EditorLanguageFeatures, revision: Int, title: String) {
        guard !isClosing, packageToolRoot == nil, !preparingLanguageEdit, editPreview == nil,
            let source = feature.document, !source.closed, feature.version == revision
        else { return }
        preparingLanguageEdit = true
        editRequest = UUID()
        let ticket = editRequest
        let root = source.workspaceRoot
        let controller = feature.controller
        let workspaceRevision = controller?.editRevision
        let service = edit["hycodeService"].string.flatMap(WebLanguage.Service.init(rawValue:))
        Task { [weak self, weak feature] in
            var preloaded: [String: UUID] = [:]
            do {
                let changes = try await Task.detached(priority: .utility) {
                    try LSPWorkspaceEdits.parse(edit, root: root)
                }.value
                guard
                    !changes.contains(where: {
                        ImagePreviewFormat.matches($0.path) || VideoPreviewFormat.matches($0.path)
                    })
                else {
                    throw LanguageServiceFailure("图片/视频只读预览不接受语义文本修改")
                }
                guard let self, self.editRequest == ticket, feature?.version == revision,
                    controller?.editRevision == workspaceRevision
                else {
                    throw CancellationError()
                }
                for file in changes where self.documents[file.path] == nil {
                    self.open(path: file.path, access: source.workspaceAccess, onEdit: {})
                    if let document = self.documents[file.path] { preloaded[file.path] = document.id }
                }
                for file in changes { await self.documents[file.path]?.finishPendingOperations() }
                guard self.editRequest == ticket, !self.isClosing, self.packageToolRoot == nil,
                    feature?.version == revision, controller?.editRevision == workspaceRevision
                else { throw CancellationError() }
                var snapshots: [(LSPWorkspaceFileEdit, UUID, UInt64, String)] = []
                var bytes = 0
                for file in changes {
                    guard let document = self.documents[file.path], !document.closed, !document.readOnly,
                        !document.toolManaged, document.largeFile == nil, !document.composing,
                        document.loadError == nil,
                        let view = document.editor?.textView, view.isEditable,
                        !document.isDirty
                            || document.semantic.map({ controller?.isSynchronized($0, service: service) == true })
                                == true,
                        file.version == nil || file.version == Int(document.edits.revision)
                    else {
                        throw LanguageServiceFailure("文件正在编辑、只读或版本已改变，请重新请求")
                    }
                    let text = view.string
                    bytes += text.utf8.count
                    guard bytes <= 8 * 1024 * 1024 else { throw LanguageServiceFailure("预览文本超过 8 MiB") }
                    snapshots.append((file, document.id, document.edits.revision, text))
                }
                let files = try await Task.detached(priority: .utility) {
                    try snapshots.map { file, id, revision, text in
                        let result = try LSPTextEdits.apply(file.edits, to: text)
                        guard result.utf8.count <= 8 * 1024 * 1024 else { throw LanguageServiceFailure("编辑结果超过文档上限") }
                        return LanguageEditPreview.File(
                            path: file.path, documentID: id, revision: revision, before: text, after: result,
                            diff: try LSPWorkspaceEdits.preview(file.edits, text: text))
                    }
                }.value
                guard self.editRequest == ticket, feature?.version == revision,
                    controller?.editRevision == workspaceRevision
                else { throw CancellationError() }
                self.editPreview = LanguageEditPreview(id: ticket, title: title, files: files, preloaded: preloaded)
            } catch {
                if self?.editRequest == ticket {
                    self?.discardPreloaded(preloaded)
                    feature?.controller?.report(error)
                }
            }
            if self?.editRequest == ticket { self?.preparingLanguageEdit = false }
        }
    }
    private func discardPreloaded(_ items: [String: UUID]) {
        for (path, id) in items {
            if let document = documents[path], document.id == id, !document.isDirty, isDocumentVisible?(path) != true {
                remove(path)
            }
        }
    }
    func cancelLanguagePreview() {
        guard let preview = editPreview else { return }
        editPreview = nil
        editRequest = UUID()
        discardPreloaded(preview.preloaded)
    }
    func applyLanguagePreview() throws {
        guard let preview = editPreview, editRequest == preview.id, !isClosing, packageToolRoot == nil else {
            throw LanguageServiceFailure("工作区已改变，请重新请求")
        }
        var targets: [(LanguageEditPreview.File, EditorDocument, NSTextView)] = []
        for file in preview.files {
            guard let document = documents[file.path], document.id == file.documentID,
                document.edits.revision == file.revision, !document.closed, !document.composing,
                !document.toolManaged, !document.readOnly, document.largeFile == nil,
                let view = document.editor?.textView, view.isEditable,
                document.permitsEdit(
                    range: NSRange(location: 0, length: file.before.utf16.count), replacement: file.after,
                    removed: file.before, currentLength: file.before.utf16.count)
            else {
                throw LanguageServiceFailure("预览后文件有变化或不能编辑，未应用；请重新请求")
            }
            targets.append((file, document, view))
        }
        // No suspension between final validation and native user edits. Every
        // document still uses its sole text/undo owner and normal save checks.
        var applied: [(LanguageEditPreview.File, NSTextView)] = []
        for (file, _, view) in targets where file.before != file.after {
            view.insertText(file.after, replacementRange: NSRange(location: 0, length: file.before.utf16.count))
            if view.string != file.after {
                for (old, target) in applied.reversed() {
                    target.insertText(
                        old.before, replacementRange: NSRange(location: 0, length: target.string.utf16.count))
                }
                throw LanguageServiceFailure("原生编辑拒绝修改，已恢复先前缓冲；请检查文件状态")
            }
            view.undoManager?.setActionName(preview.title)
            applied.append((file, view))
        }
        onLanguageFilesApplied?(preview.files.map(\.path))
        editPreview = nil
        editRequest = UUID()
    }
}

struct LanguageEditPreviewView: View {
    @Bindable var editing: EditorWorkspace
    let preview: LanguageEditPreview
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkbenchDialogHeader(
                title: preview.title + " · \(preview.files.count) 个文件", symbol: "doc.text.magnifyingglass")
            WorkbenchSeparator()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(preview.files) { file in
                        DisclosureGroup(file.path) {
                            Text(file.diff).textSelection(.enabled).font(.system(size: 12, design: .monospaced))
                        }.padding(8)
                    }
                    if !error.isEmpty { Text(error).foregroundStyle(.orange) }
                }.padding(12).background(WorkbenchScrollStyle())
            }.frame(height: 340)
            WorkbenchSeparator()
            HStack {
                Text("应用后沿用自动保存设置；每个文件可撤销").font(.system(size: 12)).foregroundStyle(WorkbenchColors.secondary)
                Spacer()
                Button("取消", action: editing.cancelLanguagePreview).keyboardShortcut(.cancelAction)
                Button("应用") {
                    do { try editing.applyLanguagePreview() } catch { self.error = error.localizedDescription }
                }.buttonStyle(WorkbenchActionButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }.padding(12)
        }.frame(width: 700).workbenchContentStyle()
    }
}
