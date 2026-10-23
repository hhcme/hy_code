import AppKit
import HyCodeWorkspace
import SwiftUI

/// Readable parameter information is a document surface, not a disabled menu
/// command. Long signatures wrap and the bounded body scrolls without truncation.
@MainActor final class WorkbenchInformationPopup {
    private let session = WorkbenchPopupSession()
    func hide() { session.close() }
    func show(_ values: [String], at point: CGPoint, in view: NSView) {
        hide()
        guard !values.isEmpty, let window = view.window, session.begin(in: view) else { return }
        let screen = window.screen?.visibleFrame ?? window.frame
        let width = min(560, max(1, screen.width - 12))
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let contentHeight = values.reduce(CGFloat(0)) { height, value in
            height
                + max(
                    18,
                    (value as NSString).boundingRect(
                        with: CGSize(width: max(1, width - 24), height: 10000),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
                    ).height) + 12
        }
        let size = CGSize(width: width, height: min(320, 48 + contentHeight))
        let frame = HyCodeWorkspace.ContextMenuPlacement.frame(anchor: point, size: size, screen: screen)
        _ = session.append(InformationContent(values: values), frame: frame, label: "参数信息", role: .group)
    }
}
private struct InformationContent: View {
    let values: [String]
    var body: some View {
        VStack(spacing: 0) {
            Text("参数信息").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).frame(height: 34)
            WorkbenchSeparator(visible: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).frame(
                                maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(12).background(WorkbenchScrollStyle())
            }
        }.foregroundStyle(WorkbenchColors.text).workbenchPopupSurface()
    }
}
