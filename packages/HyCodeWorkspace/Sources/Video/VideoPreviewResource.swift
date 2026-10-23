@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers

public struct VideoPreviewMetadata: Sendable {
    public let duration: Double
    public let width: Int
    public let height: Int
    public let bytes: Int64
}

/// AVFoundation sees a private, non-network URL. Only the pinned file descriptor
/// is served; no second resolution of the original path or referenced resources.
public final class VideoPreviewResource: @unchecked Sendable {
    public let asset: AVURLAsset
    private let loader: VideoResourceLoader
    private init(file: VideoPreviewFile, suffix: String) {
        let url = URL(string: "hycode-video://preview/\(UUID().uuidString).\(suffix)")!
        loader = VideoResourceLoader(file: file, suffix: suffix, url: url)
        asset = AVURLAsset(
            url: url,
            options: [
                AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
            ])
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
    }
    public static func open(root: URL, path: String, keepingAlive lease: (any Sendable)? = nil) async throws
        -> VideoPreviewResource
    {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let file = try VideoPreviewFile(root: root, path: path, keepingAlive: lease)
            return VideoPreviewResource(file: file, suffix: (path as NSString).pathExtension.lowercased())
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            if Task.isCancelled {
                value.cancel()
                throw CancellationError()
            }
            return value
        } onCancel: {
            worker.cancel()
        }
    }
    public func metadata() async throws -> VideoPreviewMetadata {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)) else {
                throw VideoPreviewFile.failure("系统无法播放此编码，或视频受到保护")
            }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let video = tracks.first else { throw VideoPreviewFile.failure("文件中没有视频画面") }
            let (size, transform) = try await video.load(.naturalSize, .preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            let w = abs(rect.width)
            let h = abs(rect.height)
            let duration = try await asset.load(.duration).seconds
            guard w.isFinite, h.isFinite, w >= 1, h >= 1, w <= 8192, h <= 8192, w * h <= 36_000_000,
                duration.isFinite, duration > 0, duration < 360_000_000
            else { throw VideoPreviewFile.failure("视频尺寸或时长超出预览范围") }
            try Task.checkCancellation()
            return VideoPreviewMetadata(
                duration: duration, width: Int(w.rounded()), height: Int(h.rounded()), bytes: loader.size)
        } onCancel: {
            self.cancel()
        }
    }
    public func cancel() {
        asset.cancelLoading()
        loader.cancel()
    }
    deinit { cancel() }
}

/// Mutable state is confined to one utility serial queue. A chunk schedules the
/// next turn rather than monopolizing the queue; cancellation can interleave.
private final class VideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "HyCode.video.read", qos: .utility)
    let size: Int64
    private var file: VideoPreviewFile?
    private let type: String
    private let url: URL
    private var requests: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private var stopped = false
    init(file: VideoPreviewFile, suffix: String, url: URL) {
        self.url = url
        self.file = file
        size = file.size
        type = UTType(filenameExtension: suffix)?.identifier ?? UTType.movie.identifier
    }
    func cancel() {
        queue.async { [self] in
            stopped = true
            for request in requests.values where !request.isCancelled && !request.isFinished {
                request.finishLoading(with: CancellationError())
            }
            requests.removeAll()
            file = nil
        }
    }
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard !stopped, let file, request.request.url == url, requests.count < 8 else { return false }
        if let info = request.contentInformationRequest {
            if let allowed = info.allowedContentTypes, !allowed.isEmpty, !allowed.contains(type) {
                request.finishLoading(with: VideoPreviewFile.failure("系统不接受此视频容器"))
                return true
            }
            info.contentType = type
            info.contentLength = file.size
            info.isByteRangeAccessSupported = true
        }
        requests[ObjectIdentifier(request)] = request
        service(request)
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        requests.removeValue(forKey: ObjectIdentifier(request))
    }
    private func service(_ request: AVAssetResourceLoadingRequest) {
        let key = ObjectIdentifier(request)
        guard !stopped, requests[key] != nil, !request.isCancelled, !request.isFinished, let file else {
            requests.removeValue(forKey: key)
            return
        }
        do {
            if let data = request.dataRequest {
                let (end, overflow) =
                    data.requestsAllDataToEndOfResource
                    ? (file.size, false) : data.requestedOffset.addingReportingOverflow(Int64(data.requestedLength))
                guard data.requestedOffset >= 0, data.requestedLength >= 0, !overflow else {
                    throw VideoPreviewFile.failure("视频分段请求无效")
                }
                let limit = data.requestsAllDataToEndOfResource ? file.size : min(file.size, end)
                let offset = max(data.currentOffset, data.requestedOffset)
                guard offset <= file.size else { throw VideoPreviewFile.failure("视频分段超出文件范围") }
                if offset < limit {
                    let bytes = try file.read(
                        offset: offset, count: Int(min(Int64(VideoPreviewFile.maximumChunk), limit - offset)))
                    data.respond(with: bytes)
                    if offset + Int64(bytes.count) < limit {
                        queue.async { [self] in service(request) }
                        return
                    }
                }
            }
            requests.removeValue(forKey: key)
            request.finishLoading()
        } catch {
            requests.removeValue(forKey: key)
            request.finishLoading(with: error)
        }
    }
}
