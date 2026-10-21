import SwiftUI

struct WorkbenchHeader: View {
    @Bindable var store: WorkbenchStore
    @Binding var appearance: WorkbenchAppearance

    var body: some View {
        HStack(spacing: 8) {
            // The system retains ownership of the traffic lights in this space.
            Color.clear.frame(width: 76).accessibilityHidden(true)
            WorkbenchProjectSwitcher(store: store)
            HStack(spacing: 2) {
                WorkbenchIconButton(title: "后退 ⌘[", symbol: "arrow.left", action: store.goBack)
                    .disabled(!store.history.canGoBack)
                WorkbenchIconButton(title: "前进 ⌘]", symbol: "arrow.right", action: store.goForward)
                    .disabled(!store.history.canGoForward)
            }
            Spacer(minLength: 12)
            if store.isLoading {
                ProgressView().controlSize(.mini).frame(width: 16)
                Text("正在读取目录").font(.system(size: 11)).foregroundStyle(WorkbenchColors.secondary)
                WorkbenchIconButton(title: "取消目录读取", symbol: "stop", action: store.cancelReading)
            }
            WorkbenchIconButton(title: "刷新目录 ⌘R", symbol: "arrow.clockwise", action: store.refresh)
                .disabled(store.rootURL == nil)
            WorkbenchIconButton(title: "打开项目目录 ⌘O", symbol: "folder.badge.plus", action: store.chooseProject)
            WorkbenchMenuButton(title: "切换界面外观", items: WorkbenchAppearance.menuItems(selection: $appearance)) {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 26, height: 26)
            }
        }
        .padding(.trailing, 12)
        .frame(height: WorkbenchMetrics.headerHeight)
        .foregroundStyle(WorkbenchColors.text)
        .background(WorkbenchWindowDragArea())
        .background(WorkbenchColors.chrome)
    }
}
