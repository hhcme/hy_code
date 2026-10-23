import HyCodeWorkspace
import SwiftUI

struct ImagePreviewPanel: View {
    @Bindable var document: ImagePreviewDocument
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    WorkbenchIconButton(title: "缩小 ⌘−", symbol: "minus.magnifyingglass") { document.zoom(by: 1 / 1.25) }
                    WorkbenchMenuButton(title: "缩放比例", items: zoomItems) {
                        HStack(spacing: 5) {
                            Text(document.zoomLabel).monospacedDigit().frame(minWidth: 64)
                            Image(systemName: "chevron.down").font(.system(size: 8))
                        }.padding(.horizontal, 6).frame(height: 26)
                    }
                    WorkbenchIconButton(title: "放大 ⌘+", symbol: "plus.magnifyingglass") { document.zoom(by: 1.25) }
                    WorkbenchSeparator(vertical: true, visible: true).frame(height: 18).padding(.horizontal, 4)
                    WorkbenchIconButton(
                        title: "适应窗口 ⌥⌘0", symbol: "arrow.up.left.and.arrow.down.right", active: document.fits
                    ) { document.fit() }
                    Button("100%") { document.zoom(to: 1) }.buttonStyle(WorkbenchButtonStyle()).padding(.horizontal, 4)
                        .help("原始尺寸 ⌥⌘1")
                    WorkbenchMenuButton(
                        title: "图片背景",
                        items: ImagePreviewBackground.allCases.map { value in
                            WorkbenchMenuItem(title: value.rawValue, checked: document.background == value) {
                                document.background = value
                            }
                        }
                    ) { Image(systemName: "checkerboard.rectangle").frame(width: 26, height: 26) }
                    WorkbenchIconButton(title: "重新载入图片", symbol: "arrow.clockwise", action: document.reload)
                    if document.pixelSize.width > 0 {
                        Text(
                            "\(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height)) · \(document.format)"
                        )
                        .foregroundStyle(WorkbenchColors.secondary).padding(.leading, 8)
                    }
                    if document.content?.frameCount ?? 0 > 1 {
                        Text("首帧预览").foregroundStyle(WorkbenchColors.secondary)
                    }
                    if document.content?.downsampled == true {
                        Text("已降采样").foregroundStyle(WorkbenchColors.secondary).help("缩放使用受限分辨率预览，原文件保持不变")
                    }
                }.padding(.horizontal, 8).frame(height: WorkbenchMetrics.secondaryToolbarHeight)
                    .disabled(document.loading || document.error != nil)
            }.fixedSize(horizontal: false, vertical: true)
            WorkbenchSeparator(visible: true)
            ZStack {
                ImagePreviewHost(document: document)
                if document.loading {
                    ProgressView("正在读取图片…").padding(16).background(
                        WorkbenchColors.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                if let error = document.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("无法预览此图片", systemImage: "photo.badge.exclamationmark").fontWeight(.medium)
                        Text(error).foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                        Button("重新读取", action: document.reload).buttonStyle(WorkbenchActionButtonStyle())
                    }.padding(24).frame(maxWidth: 520).background(WorkbenchColors.panel)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(.system(size: 13)).foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.canvas)
    }
    private var zoomItems: [WorkbenchMenuItem] {
        [WorkbenchMenuItem(title: "适应窗口", checked: document.fits, action: document.fit), .separator]
            + ImagePreviewZoom.presets.map { factor in
                WorkbenchMenuItem(title: "\(Int(factor * 100))%") { document.zoom(to: factor) }
            }
    }
}
private struct ImagePreviewHost: NSViewRepresentable {
    let document: ImagePreviewDocument
    func makeNSView(context: Context) -> ImagePreviewViewport {
        if let view = document.viewport { return view }
        let view = ImagePreviewViewport()
        view.zoomChanged = { [weak document] factor, fit in document?.updateZoomFeedback(factor, fit: fit) }
        view.background = document.background
        document.viewport = view
        return view
    }
    func updateNSView(_ view: ImagePreviewViewport, context: Context) { view.display(document.content) }
}
