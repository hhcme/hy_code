import HyCodeWorkspace
import SwiftUI

struct WorkbenchTab: View {
    let tab: BrowserTab
    let projectName: String
    let active: Bool
    let activate: () -> Void
    let pin: () -> Void
    let close: () -> Void
    @State private var hovering = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: 0) {
            Button(action: activate) {
                HStack(spacing: 7) {
                    if case .file(let entry) = tab.location {
                        FileIcon(entry: entry)
                    } else {
                        Image(systemName: "folder").foregroundStyle(Color(nsColor: WorkbenchColors.nativeFolder))
                    }
                    Text(tab.location.path.isEmpty ? projectName : tab.location.title)
                        .font(.system(size: 12).italicIf(tab.isPreview))
                        .lineLimit(1).frame(maxWidth: 190)
                }
                .padding(.leading, 13).padding(.trailing, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
                .foregroundStyle(active ? WorkbenchColors.text : WorkbenchColors.secondary)
            }
            .buttonStyle(WorkbenchButtonStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded(pin))
            .accessibilityLabel(tab.location.path.isEmpty ? projectName : tab.location.path)
            .accessibilityValue(active ? "当前标签" : "")
            .accessibilityAction(named: Text("固定标签"), pin)
            WorkbenchIconButton(title: "关闭标签", symbol: "xmark", size: 20, action: close)
                .padding(.trailing, 7)
                .foregroundStyle(WorkbenchColors.secondary)
        }
        .foregroundStyle(active ? WorkbenchColors.text : WorkbenchColors.secondary)
        .background(
            active ? WorkbenchColors.tab : hovering ? WorkbenchColors.hover : .clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(
                active ? WorkbenchColors.tabBorder : .clear, lineWidth: 1 / displayScale)
        }
        .padding(.horizontal, 3).frame(height: WorkbenchMetrics.tabHeight)
        .onHover { hovering = $0 }
        .contextMenu {
            if tab.isPreview { Button("固定标签", action: pin) }
            Button("关闭标签", action: close)
        }
        .help(tab.location.path.isEmpty ? projectName : tab.location.path)
    }
}

extension Font {
    fileprivate func italicIf(_ condition: Bool) -> Font { condition ? italic() : self }
}
