import AppKit
import HyCodeWorkspace

extension EditorLanguageFeatures {
    @objc func typeDefinition() { navigate("textDocument/typeDefinition") }
    @objc func implementation() { navigate("textDocument/implementation") }
    @objc func renameSymbol() {
        guard let document, !document.readOnly, let view = document.editor?.textView, let window = view.window,
            let controller, controller.supportsWorkspaceEdits
        else { return }
        dismissHover()
        let selected = view.selectedRange()
        let revision = version
        var initialName = ""
        if let range = DartHoverTarget.range(at: selected.location, in: view.string as NSString) {
            initialName = (view.string as NSString).substring(with: range)
        }
        WorkbenchPrompt.present(
            in: window, title: "重命名符号", detail: "输入新名称，下一步查看涉及文件的修改预览。",
            initialValue: initialName, accept: "预览"
        ) { [weak self] response, name in
            guard response == .accept, let self, self.version == revision,
                !name.isEmpty, name.count <= 256, !name.contains("\0")
            else { return }
            Task {
                do {
                    let value = try await controller.query(
                        "textDocument/rename", feature: self,
                        position: .at(selected.location, in: self.lines), parameters: ["newName": .string(name)])
                    guard self.version == revision else { return }
                    controller.previewWorkspaceEdit(value, feature: self, revision: revision, title: "重命名为 " + name)
                } catch { controller.report(error) }
            }
        }
    }
    @objc func quickFix() { codeActions(only: nil) }
    @objc func organizeImports() { codeActions(only: "source.organizeImports") }
    private func codeActions(only: String?) {
        guard let view = document?.editor?.textView, document?.readOnly == false,
            let controller, controller.supportsWorkspaceEdits
        else { return }
        dismissHover()
        let revision = version
        let selection = view.selectedRange()
        let workspaceRevision = controller.editRevision
        let position = LSPPosition.at(selection.location, in: lines)
        let range = LSPRange(start: position, end: .at(NSMaxRange(selection), in: lines))
        var context: [String: JSONValue] = [
            "diagnostics": .array(diagnosticContext(line: position.line)), "triggerKind": .number(1),
        ]
        if let only { context["only"] = .array([.string(only)]) }
        let parameters = ["range": range.json, "context": JSONValue.object(context)]
        Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await controller.query(
                    "textDocument/codeAction", feature: self, position: nil, parameters: parameters)
                guard self.version == revision, controller.editRevision == workspaceRevision,
                    view.selectedRange() == selection, view.window != nil
                else { return }
                var items: [WorkbenchContextCommand] = []
                for value in result.array.prefix(100) {
                    guard let title = value["title"].string else { continue }
                    let action = { [weak self] in
                        guard let self, self.version == revision, controller.editRevision == workspaceRevision else {
                            return
                        }
                        Task {
                            do {
                                var value = value
                                if value["edit"] == .null, value["data"] != .null, case .object(let fields) = value {
                                    value = try await controller.query(
                                        "codeAction/resolve", feature: self, position: nil, parameters: fields)
                                }
                                guard self.version == revision, controller.editRevision == workspaceRevision else {
                                    return
                                }
                                guard value["edit"] != .null else {
                                    throw LanguageServiceFailure("此动作需要额外命令，当前仅支持可预览的文本修改")
                                }
                                var edit = value["edit"]
                                if case .object(var fields) = edit {
                                    fields["hycodeService"] = value["hycodeService"]
                                    edit = .object(fields)
                                }
                                controller.previewWorkspaceEdit(edit, feature: self, revision: revision, title: title)
                            } catch { controller.report(error) }
                        }
                    }
                    items.append(
                        WorkbenchContextCommand(title: title, enabled: value["disabled"] == .null, action: action))
                }
                guard !items.isEmpty else {
                    controller.report(LanguageServiceFailure("当前位置没有可用的代码动作"))
                    return
                }
                let rect = view.firstRect(forCharacterRange: selection, actualRange: nil)
                semanticMenu.show(items, at: rect.origin, in: view)

            } catch { controller.report(error) }
        }
    }
    @objc func signatureHelp() {
        guard let controller, let view = document?.editor?.textView else { return }
        let revision = version
        let selection = view.selectedRange()
        Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await controller.query(
                    "textDocument/signatureHelp", feature: self,
                    position: .at(selection.location, in: self.lines))
                guard self.version == revision, view.selectedRange() == selection, view.window != nil else { return }
                let items = result["signatures"].array.prefix(20).compactMap { signature in
                    signature["label"].string.map { String($0.prefix(1_000)) }
                }
                if !items.isEmpty {
                    let rect = view.firstRect(forCharacterRange: selection, actualRange: nil)
                    informationPopup.show(items, at: rect.origin, in: view)
                }

            } catch { controller.report(error) }
        }
    }
}
