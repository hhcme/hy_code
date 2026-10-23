import AppKit
import HyCodeWorkspace
import Observation

/// Owns only a read-only projection. No text engine, undo, save, or language
/// service. Only the active image holds pixels; inactive tabs retain view state.
@MainActor @Observable final class ImagePreviewDocument: Identifiable {
    let id = UUID()
    let path: String
    private let access: WorkspaceAccess
    private(set) var content: ImagePreviewContent?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var pixelSize = CGSize.zero
    private(set) var format = ""
    private(set) var byteCount = 0
    var zoomLabel = "适应窗口"
    var fits = true
    var background: ImagePreviewBackground = .checkerboard { didSet { viewport?.background = background } }
    @ObservationIgnored var viewport: ImagePreviewViewport?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var feedback: (CGFloat, Bool)?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    var status: String { loading ? "正在预览…" : error != nil ? "无法预览" : "图片 · 只读" }
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
        guard active || content != nil || loading else { return }
        active = false
        request = UUID()
        task?.cancel()
        task = nil
        content = nil
        viewport?.display(nil)
        loading = false
    }
    func reload() {
        guard active else { return }
        task?.cancel()
        request = UUID()
        let ticket = request
        content = nil
        viewport?.display(nil)
        loading = true
        error = nil
        task = Task(priority: .utility) { [weak self, access, path] in
            defer { withExtendedLifetime(access) {} }
            do {
                let value = try await ImagePreviewLoader.shared.load(root: access.url, path: path)
                guard !Task.isCancelled, let self, self.active, self.request == ticket else { return }
                self.content = value
                self.pixelSize = value.pixelSize
                self.format = value.format
                self.byteCount = value.byteCount
                self.loading = false
            } catch {
                guard !Task.isCancelled, let self, self.active, self.request == ticket else { return }
                self.error = error.localizedDescription
                self.loading = false
            }
        }
    }
    func updateZoomFeedback(_ factor: CGFloat, fit: Bool) {
        feedback = (factor, fit)
        guard feedbackTask == nil else { return }
        feedbackTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            feedbackTask = nil
            guard active, let (factor, fit) = feedback else { return }
            zoomLabel =
                (fit ? "适应 · " : "")
                + (factor < 0.1 ? String(format: "%.1f%%", factor * 100) : String(format: "%.0f%%", factor * 100))
            fits = fit
        }
    }
    func fit() { viewport?.fit() }
    func zoom(to factor: CGFloat) { viewport?.zoom(to: factor) }
    func zoom(by factor: CGFloat) { viewport?.zoom(by: factor) }
}
enum ImagePreviewBackground: String, CaseIterable {
    case checkerboard = "透明棋盘"
    case light = "浅色"
    case dark = "深色"
}
