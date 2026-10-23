import AVFoundation
import AppKit
import HyCodeWorkspace
import SwiftUI

struct VideoPreviewPanel: View {
    @Bindable var document: VideoPreviewDocument
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Label("视频预览", systemImage: "film").fontWeight(.medium)
                    if let metadata = document.metadata {
                        Text("\(metadata.width) × \(metadata.height)").foregroundStyle(WorkbenchColors.secondary)
                    }
                    Text("适应窗口").foregroundStyle(WorkbenchColors.secondary)
                    WorkbenchIconButton(title: "重新载入视频", symbol: "arrow.clockwise", action: document.reload)
                }.padding(.horizontal, 10).frame(height: WorkbenchMetrics.secondaryToolbarHeight)
            }.fixedSize(horizontal: false, vertical: true)
            WorkbenchSeparator(visible: true)
            ZStack {
                VideoPlayerHost(document: document)
                if document.loading {
                    ProgressView("正在读取视频…").padding(16).background(
                        WorkbenchColors.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                if let error = document.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("无法预览此视频", systemImage: "film").fontWeight(.medium)
                        Text(error).foregroundStyle(WorkbenchColors.secondary).textSelection(.enabled)
                        Button("重新读取", action: document.reload).buttonStyle(WorkbenchActionButtonStyle())
                    }.padding(24).frame(maxWidth: 520).background(WorkbenchColors.panel)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            WorkbenchSeparator(visible: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    playbackButton
                    timeLabel(document.position)
                    progress.frame(minWidth: 60)
                    timeLabel(document.duration)
                    volumeButton
                    Slider(value: $document.volume, in: 0...1).frame(width: 80).accessibilityLabel("音量")
                }.padding(.horizontal, 8).frame(minWidth: 360).frame(height: 40)
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        progress
                        Text(
                            VideoPreviewTime.label(document.position) + " / "
                                + VideoPreviewTime.label(document.duration)
                        ).monospacedDigit().font(.system(size: 12)).fixedSize()
                    }.padding(.horizontal, 10).frame(height: 30)
                    HStack(spacing: 8) {
                        playbackButton
                        Spacer(minLength: 0)
                        volumeButton
                        Slider(value: $document.volume, in: 0...1).frame(width: 80).accessibilityLabel("音量")
                    }.padding(.horizontal, 8).frame(height: 36)
                }
            }.disabled(!document.ready)
        }.font(.system(size: 13)).foregroundStyle(WorkbenchColors.text).background(WorkbenchColors.canvas)
    }
    private var playbackButton: some View {
        WorkbenchIconButton(
            title: document.playing ? "暂停 · 画布聚焦后按空格" : "播放 · 画布聚焦后按空格",
            symbol: document.playing ? "pause.fill" : "play.fill", action: document.togglePlayback)
    }
    private var volumeButton: some View {
        WorkbenchIconButton(
            title: document.muted ? "取消静音" : "静音", symbol: document.muted ? "speaker.slash" : "speaker.wave.2"
        ) { document.muted.toggle() }
    }
    private var progress: some View {
        Slider(
            value: Binding(get: { document.position }, set: { document.seek(to: $0) }),
            in: 0...max(0.001, document.duration), onEditingChanged: document.setScrubbing
        ).accessibilityLabel("视频进度")
    }
    private func timeLabel(_ time: Double) -> some View {
        Text(VideoPreviewTime.label(time)).monospacedDigit().frame(minWidth: 48)
    }

}
private struct VideoPlayerHost: NSViewRepresentable {
    let document: VideoPreviewDocument
    func makeNSView(context: Context) -> VideoPlayerCanvas { VideoPlayerCanvas() }
    func updateNSView(_ view: VideoPlayerCanvas, context: Context) {
        if view.video.player !== document.player {
            view.video.player = document.player
            view.window?.invalidateCursorRects(for: view)
        }
        view.toggle = { [weak document] in document?.togglePlayback() }
        view.skip = { [weak document] seconds in
            guard let document else { return }
            document.seek(to: document.position + seconds)
        }
    }
    static func dismantleNSView(_ view: VideoPlayerCanvas, coordinator: ()) {
        view.video.player = nil
        view.toggle = {}
        view.skip = { _ in }
    }
}
private final class VideoPlayerCanvas: NSView {
    let video = AVPlayerLayer()
    var toggle: () -> Void = {}
    var skip: (Double) -> Void = { _ in }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        video.videoGravity = .resizeAspect
        layer?.addSublayer(video)
        setAccessibilityRole(.group)
        setAccessibilityLabel("视频预览")
        setAccessibilityHelp("单击或空格播放与暂停，左右方向键前后跳转五秒")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        video.frame = bounds
        CATransaction.commit()
    }
    override func resetCursorRects() { if video.player != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        toggle()
    }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 49: toggle()
        case 123: skip(-5)
        case 124: skip(5)
        default: super.keyDown(with: event)
        }
    }
}
