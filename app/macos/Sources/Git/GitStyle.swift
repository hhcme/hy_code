import AppKit
import HyCodeWorkspace
import SwiftUI

enum GitStyle {
    static let rowHeight = WorkbenchStyleMetrics.rowHeight
    static let toolbarHeight = WorkbenchStyleMetrics.secondaryToolbarHeight
    static let versionHeight: CGFloat = 28
    static let bandAlpha = GitConnectionBand.opacity
    static let graph = Color(red: 0.40, green: 0.35, blue: 0.64)
    static func fileColor(_ entry: GitStatusEntry) -> Color {
        if entry.conflicted { return .orange }
        if entry.untracked { return Color(nsColor: WorkbenchColors.nativeCode) }
        if entry.label == "删除" { return .red }
        return WorkbenchColors.accent
    }
    static func changeColor(_ kind: GitDiffRow.Kind) -> NSColor? {
        switch kind {
        case .added: .systemGreen
        case .removed: NSColor(srgbRed: 0.66, green: 0.68, blue: 0.67, alpha: 1)
        case .changed: NSColor(srgbRed: 0.31, green: 0.55, blue: 0.72, alpha: 1)
        default: nil
        }
    }
}

/// Git search belongs to the tool strip, with a quiet outline rather than a
/// filled settings-form field. It keeps the workbench's normal input behavior.
struct GitSearchField: View {
    let prompt: String
    @Binding var text: String
    var submit: () -> Void = {}
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                .onSubmit(submit)
            if !text.isEmpty {
                WorkbenchIconButton(title: "清除筛选", symbol: "xmark", size: 18) {
                    text = ""
                    submit()
                }
            }
        }.padding(.horizontal, 7).frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 4).strokeBorder(
                    focused ? WorkbenchColors.accent : WorkbenchColors.tabBorder.opacity(0.75), lineWidth: 0.5)
            )
    }
}
