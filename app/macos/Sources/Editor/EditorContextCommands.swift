import AppKit
import HyCodeWorkspace

@MainActor enum EditorContextCommands {
    static func make(for view: NSTextView, semantic: EditorLanguageFeatures?) -> [WorkbenchContextCommand] {
        let editable = view.isEditable && !view.hasMarkedText()
        let selected = view.selectedRange().length > 0
        var items: [WorkbenchContextCommand] = [
            .init(
                title: "撤销", symbol: "arrow.uturn.backward", shortcut: "⌘Z",
                enabled: editable && view.undoManager?.canUndo == true
            ) { [weak view] in
                guard let view, view.isEditable, !view.hasMarkedText() else { return }
                view.undoManager?.undo()
            },
            .init(
                title: "重做", symbol: "arrow.uturn.forward", shortcut: "⇧⌘Z",
                enabled: editable && view.undoManager?.canRedo == true
            ) { [weak view] in
                guard let view, view.isEditable, !view.hasMarkedText() else { return }
                view.undoManager?.redo()
            },
            .separator,
            .init(title: "剪切", symbol: "scissors", shortcut: "⌘X", enabled: editable && selected) { [weak view] in
                guard let view, view.isEditable, !view.hasMarkedText() else { return }
                view.cut(nil)
            },
            .init(title: "复制", symbol: "doc.on.doc", shortcut: "⌘C", enabled: selected) { [weak view] in view?.copy(nil)
            },
            .init(title: "粘贴", symbol: "doc.on.clipboard", shortcut: "⌘V", enabled: editable) { [weak view] in
                guard let view, view.isEditable, !view.hasMarkedText() else { return }
                view.pasteAsPlainText(nil)
            },
            .init(
                title: "全选", symbol: "selection.pin.in.out", shortcut: "⌘A",
                enabled: (view.textStorage?.length ?? 0) > 0
            ) { [weak view] in view?.selectAll(nil) },
        ]
        guard let semantic else { return items }
        if let language = WebLanguage.detect(semantic.document?.path ?? ""), language.isConfiguration {
            items += [
                .separator,
                .init(title: "结构导航", symbol: "list.bullet.indent") { [weak semantic] in semantic?.structure() },
                .init(title: "补全", symbol: "text.cursor", shortcut: "⌃空格", enabled: editable) { [weak semantic] in
                    semantic?.complete()
                },
                .init(title: "格式化文档", symbol: "text.alignleft", enabled: editable) { [weak semantic] in
                    semantic?.format()
                },
            ]
            if language == .yaml {
                items += [
                    .separator,
                    .init(title: "跳转锚点定义", symbol: "arrow.turn.down.right", shortcut: "⌘B") { [weak semantic] in
                        semantic?.definition()
                    },
                    .init(title: "重命名锚点…", symbol: "pencil", enabled: editable) { [weak semantic] in
                        semantic?.renameSymbol()
                    },
                    .init(title: "快速修复…", symbol: "lightbulb", shortcut: "⌥↩", enabled: editable) { [weak semantic] in
                        semantic?.quickFix()
                    },
                ]
            }
            return items
        }
        items += [
            .separator,
            .init(title: "跳转定义", symbol: "arrow.turn.down.right", shortcut: "⌘B") { [weak semantic] in
                semantic?.definition()
            },
            .init(title: "查找引用", symbol: "text.magnifyingglass", shortcut: "⇧⌘B") { [weak semantic] in
                semantic?.references()
            },
        ]
        if semantic.controller?.supportsWorkspaceEdits == true {
            items += [
                .init(title: "跳转类型", symbol: "t.square") { [weak semantic] in semantic?.typeDefinition() },
                .init(title: "跳转实现", symbol: "arrow.triangle.branch") { [weak semantic] in semantic?.implementation() },
                .init(title: "参数信息", symbol: "info.circle", shortcut: "⌘P") { [weak semantic] in
                    semantic?.signatureHelp()
                },
                .separator,
                .init(title: "重命名…", symbol: "pencil", enabled: editable) { [weak semantic] in semantic?.renameSymbol()
                },
                .init(title: "快速修复 / 重构…", symbol: "lightbulb", shortcut: "⌥↩", enabled: editable) { [weak semantic] in
                    semantic?.quickFix()
                },
                .init(title: "整理导入…", symbol: "line.3.horizontal.decrease", enabled: editable) { [weak semantic] in
                    semantic?.organizeImports()
                },
            ]
        }
        items += [
            .separator,
            .init(title: "格式化文档", symbol: "text.alignleft", enabled: editable) { [weak semantic] in semantic?.format()
            },
        ]
        return items
    }
}
