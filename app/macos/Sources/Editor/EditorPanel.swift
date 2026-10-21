import HyCodeWorkspace
import SwiftUI

struct EditorPanel: View {
    @Bindable var document: EditorDocument
    let reload: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if let error = document.error ?? document.inputError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 12)).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("重试保存") { Task { await document.save() } }
                    Button("重新载入…", action: reload)
                }
                .buttonStyle(WorkbenchButtonStyle())
                .padding(10).background(WorkbenchColors.chrome)
                WorkbenchSeparator()
            }
            if document.loading {
                ProgressView("正在打开文件…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = document.loadError {
                VStack(alignment: .leading, spacing: 12) {
                    Label("暂时无法编辑此文件", systemImage: "doc.badge.ellipsis").font(.headline)
                    Text(error).foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                    Button("重新读取", action: reload).buttonStyle(WorkbenchButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let editor = document.editor {
                NativeEditorHost(editor: editor).id(document.id)
            }
        }.foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.panel)
    }
}

struct EditorSettingsView: View {
    @Bindable var store: WorkbenchStore
    var body: some View {
        Form {
            Toggle("自动保存", isOn: $store.autoSave)
            Text("停止输入约 800 毫秒后保存到原文件；输入法组合期间暂停保存。关闭后使用 ⌘S 保存。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 440).navigationTitle("编辑设置")
    }
}
