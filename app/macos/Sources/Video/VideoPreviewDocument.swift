import AVFoundation
import HyCodeWorkspace
import Observation

/// A single active native player owns transport state. Inactive tabs keep only
/// position/volume, never an audio session, decoder, or playback observer.
@MainActor @Observable final class VideoPreviewDocument: Identifiable {
    let id = UUID()
    let path: String
    private let access: WorkspaceAccess
    private(set) var player: AVPlayer?
    private(set) var metadata: VideoPreviewMetadata?
    private(set) var loading = false
    private(set) var ready = false
    private(set) var error: String?
    private(set) var position = 0.0
    private(set) var playing = false
    var volume = 0.8 { didSet { player?.volume = Float(volume) } }
    var muted = false { didSet { player?.isMuted = muted } }
    @ObservationIgnored private var active = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var resource: VideoPreviewResource?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeObservation: Any?
    @ObservationIgnored private var endObservation: NSObjectProtocol?
    @ObservationIgnored private var seeks = VideoPreviewSeek()
    @ObservationIgnored private var scrubbing = false
    var duration: Double { metadata?.duration ?? 0 }
    var status: String { loading ? "正在读取视频…" : error != nil ? "无法预览" : "视频 · 只读" }
    init(path: String, access: WorkspaceAccess) {
        self.path = path
        self.access = access
    }
    func activate() {
        guard !active else { return }
        active = true
        reload()
    }
    func suspend() {
        guard active || player != nil || loading else { return }
        active = false
        clearPlayback()
    }
    func reload() {
        guard active else { return }
        clearPlayback()
        loading = true
        error = nil
        let ticket = generation
        task = Task(priority: .utility) { [weak self, access, path] in
            var opened: VideoPreviewResource?
            do {
                let value = try await VideoPreviewResource.open(root: access.url, path: path, keepingAlive: access)
                opened = value
                let metadata = try await value.metadata()
                guard !Task.isCancelled, let self, self.active, self.generation == ticket else {
                    value.cancel()
                    return
                }
                self.metadata = metadata
                self.resource = value
                self.configure(value, ticket: ticket)
            } catch {
                opened?.cancel()
                guard !Task.isCancelled, let self, self.active, self.generation == ticket else { return }
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }
    private func configure(_ resource: VideoPreviewResource, ticket: UUID) {
        let item = AVPlayerItem(asset: resource.asset)
        item.preferredForwardBufferDuration = 2
        let player = AVPlayer(playerItem: item)
        player.volume = Float(volume)
        player.isMuted = muted
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        self.player = player
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, active, generation == ticket, self.player?.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    ready = true
                    loading = false
                    seek(to: position)
                case .failed:
                    let message = item.error?.localizedDescription ?? "无法播放此视频编码"
                    clearPlayback()
                    error = message
                default: break
                }
            }
        }
        timeObservation = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, active, generation == ticket, !scrubbing, seeks.inFlight == nil else { return }
                let seconds = time.seconds
                if seconds.isFinite { position = min(duration, max(0, seconds)) }
            }
        }
        endObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, active, generation == ticket else { return }
                playing = false
                position = duration
            }
        }
    }
    func togglePlayback() {
        guard active, ready, error == nil, let player else { return }
        playing.toggle()
        if playing {
            if position >= duration - 0.05 { seek(to: 0) } else if seeks.inFlight == nil, !scrubbing { player.play() }
        } else {
            player.pause()
        }
    }
    func setScrubbing(_ value: Bool) {
        scrubbing = value
        if value { player?.pause() } else if playing, seeks.inFlight == nil { player?.play() }
    }
    func seek(to seconds: Double) {
        guard ready, seconds.isFinite else { return }
        position = min(duration, max(0, seconds))
        player?.pause()
        if let target = seeks.request(position, duration: duration) { performSeek(target, ticket: generation) }
    }
    private func performSeek(_ target: Double, ticket: UUID) {
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, active, generation == ticket else { return }
                if let next = seeks.complete() {
                    performSeek(next, ticket: ticket)
                } else if playing, !scrubbing {
                    player?.play()
                }
            }
        }
    }
    private func clearPlayback() {
        generation = UUID()
        task?.cancel()
        task = nil
        player?.pause()
        if let timeObservation, let player { player.removeTimeObserver(timeObservation) }
        timeObservation = nil
        itemObservation?.invalidate()
        itemObservation = nil
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        endObservation = nil
        player?.currentItem?.cancelPendingSeeks()
        player?.replaceCurrentItem(with: nil)
        player = nil
        resource?.cancel()
        resource = nil
        seeks = VideoPreviewSeek()
        scrubbing = false
        playing = false
        loading = false
        ready = false
    }
}
