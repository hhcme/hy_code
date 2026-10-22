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
        let alert = NSAlert()
        alert.messageText = "重命名符号"
        alert.informativeText = "输入新名称，下一步查看涉及文件的修改预览。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        if let range = DartHoverTarget.range(at: selected.location, in: view.string as NSString) {
            field.stringValue = (view.string as NSString).substring(with: range)
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "预览")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self, self.version == revision,
                !field.stringValue.isEmpty, field.stringValue.count <= 256, !field.stringValue.contains("\0")
            else { return }
            let name = field.stringValue
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
                var actions: [WebMenuAction] = []
                let menu = NSMenu()
                for value in result.array.prefix(100) {
                    guard let title = value["title"].string else { continue }
                    let action = WebMenuAction { [weak self] in
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
                    actions.append(action)
                    let item = NSMenuItem(title: title, action: #selector(WebMenuAction.choose), keyEquivalent: "")
                    item.target = action
                    item.isEnabled = value["disabled"] == .null
                    menu.addItem(item)
                }
                guard !menu.items.isEmpty else {
                    controller.report(LanguageServiceFailure("当前位置没有可用的代码动作"))
                    return
                }
                menu.autoenablesItems = false
                let rect = view.firstRect(forCharacterRange: selection, actualRange: nil)
                let point = view.convert(view.window!.convertPoint(fromScreen: rect.origin), from: nil)
                withExtendedLifetime(actions) { _ = menu.popUp(positioning: nil, at: point, in: view) }
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
                let menu = NSMenu()
                menu.autoenablesItems = false
                for signature in result["signatures"].array.prefix(20) {
                    let item = NSMenuItem(
                        title: String((signature["label"].string ?? "").prefix(1_000)), action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
                if !menu.items.isEmpty {
                    let rect = view.firstRect(forCharacterRange: selection, actualRange: nil)
                    _ = menu.popUp(
                        positioning: nil,
                        at: view.convert(view.window!.convertPoint(fromScreen: rect.origin), from: nil), in: view)
                }
            } catch { controller.report(error) }
        }
    }
}

@MainActor private final class WebMenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func choose() { action() }
}
