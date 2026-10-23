import SwiftUI

/// Workbench-owned controls. System permission/file dialogs retain their native
/// controls and ownership; no global AppKit appearance is changed.
struct WorkbenchActionButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        WorkbenchActionSurface(pressed: configuration.isPressed, primary: primary) {
            configuration.label.font(.system(size: WorkbenchMetrics.uiFontSize)).padding(.horizontal, 10)
                .frame(minWidth: 48, minHeight: WorkbenchMetrics.controlHeight)
        }
    }
}
private struct WorkbenchActionSurface<Content: View>: View {
    let pressed: Bool
    let primary: Bool
    var filled = true
    @ViewBuilder let content: () -> Content
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    var body: some View {
        content()
            .background(
                filled ? (primary ? WorkbenchColors.selection : WorkbenchColors.field) : .clear,
                in: RoundedRectangle(cornerRadius: WorkbenchMetrics.controlRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.controlRadius).strokeBorder(
                    filled ? WorkbenchColors.tabBorder : .clear, lineWidth: 0.5)
            )
            .modifier(WorkbenchControlSurface(active: primary, hovering: hovering, pressed: pressed, focused: focused))
            .background(WorkbenchPointerRegion(enabled: enabled))
            .onHover { hovering = enabled && $0 }
            .onChange(of: enabled) { _, value in if !value { hovering = false } }
            .onDisappear { hovering = false }
    }
}
@MainActor struct WorkbenchTextFieldStyle: @preconcurrency TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        WorkbenchFieldSurface { configuration.textFieldStyle(.plain).font(.system(size: WorkbenchMetrics.uiFontSize)) }
    }
}
private struct WorkbenchFieldSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.displayScale) private var scale
    var body: some View {
        content().padding(.horizontal, 8).padding(.vertical, 5)
            .frame(minHeight: WorkbenchMetrics.controlHeight).foregroundStyle(WorkbenchColors.text)
            .background(WorkbenchColors.field, in: RoundedRectangle(cornerRadius: WorkbenchMetrics.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.controlRadius).strokeBorder(
                    focused ? WorkbenchColors.accent : WorkbenchColors.tabBorder, lineWidth: 1 / scale)
            )
            .opacity(enabled ? 1 : 0.5)
    }
}
struct WorkbenchSectionTab: View {
    let title: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: WorkbenchMetrics.uiFontSize)).padding(.horizontal, 8).frame(
                height: WorkbenchMetrics.sectionTabHeight)
        }
        .buttonStyle(WorkbenchButtonStyle(active: active, neutral: true))
        .overlay(
            RoundedRectangle(cornerRadius: WorkbenchMetrics.controlRadius).strokeBorder(
                active ? WorkbenchColors.tabBorder : .clear, lineWidth: 0.5
            ).allowsHitTesting(false))
    }
}
struct WorkbenchDialogHeader: View {
    let title: String
    var symbol = "slider.horizontal.3"
    var body: some View {
        Label(title, systemImage: symbol).lineLimit(1).truncationMode(.middle).help(title).font(
            .system(size: 13, weight: .semibold)
        )
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).frame(
            height: WorkbenchMetrics.dialogHeaderHeight
        )
        .background(WorkbenchColors.chrome)
    }
}
extension View {
    func workbenchContentStyle() -> some View {
        font(.system(size: WorkbenchMetrics.uiFontSize)).foregroundStyle(WorkbenchColors.text)
            .buttonStyle(WorkbenchActionButtonStyle()).textFieldStyle(WorkbenchTextFieldStyle())
            .toggleStyle(.checkbox).tint(WorkbenchColors.accent).background(WorkbenchColors.panel)
    }
    func workbenchPopupSurface() -> some View {
        background(WorkbenchColors.chrome, in: RoundedRectangle(cornerRadius: WorkbenchMetrics.popupRadius))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchMetrics.popupRadius).strokeBorder(
                    WorkbenchColors.tabBorder, lineWidth: 0.5
                )
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.popupRadius))
    }
}

struct WorkbenchStatusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WorkbenchActionSurface(pressed: configuration.isPressed, primary: false, filled: false) {
            configuration.label.font(.system(size: WorkbenchMetrics.statusFontSize)).padding(.horizontal, 4).frame(
                height: 24)
        }
    }
}
