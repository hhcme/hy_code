@preconcurrency import AVFoundation
import CoreVideo
import Darwin
import Foundation
import Testing

@testable import HyCodeWorkspace

struct VideoPreviewStateTests {
    @Test func onlyLocalVideoSuffixesEnterPreview() {
        for path in ["movie.mp4", "目录/%_video.MOV", "sample.m4v"] { #expect(VideoPreviewFormat.matches(path)) }
        for path in ["main.swift", "pubspec.yaml", "frame.png", "stream.m3u8", "video.mp4.dart", "movie.mkv"] {
            #expect(!VideoPreviewFormat.matches(path))
        }
    }
    @Test func seekingKeepsOneFlightAndLatestTarget() {
        var queue = VideoPreviewSeek()
        #expect(queue.request(2, duration: 10) == 2)
        #expect(queue.request(3, duration: 10) == nil)
        #expect(queue.request(8, duration: 10) == nil)
        #expect(queue.inFlight == 2 && queue.pending == 8)
        #expect(queue.complete() == 8)
        #expect(queue.complete() == nil && queue.inFlight == nil && queue.pending == nil)
    }
    @Test func seekingRejectsInvalidTimesAndClampsBeforePlayback() {
        var queue = VideoPreviewSeek()
        #expect(queue.request(.nan, duration: 10) == nil)
        #expect(queue.request(1, duration: .infinity) == nil)
        #expect(queue.request(1, duration: 0) == nil)
        #expect(queue.request(-4, duration: 10) == 0)
        #expect(queue.request(-1, duration: 10) == nil)
        #expect(queue.complete() == nil)
        #expect(queue.request(50, duration: 10) == 10)
        _ = queue.complete()
        #expect(queue.inFlight == nil)
    }
    @Test func labelsHandleHoursAndUnloadedDuration() {
        #expect(VideoPreviewTime.label(0) == "0:00")
        #expect(VideoPreviewTime.label(59.9) == "0:59")
        #expect(VideoPreviewTime.label(3661) == "1:01:01")
        #expect(VideoPreviewTime.label(.infinity) == "—:—")
        #expect(VideoPreviewTime.label(-1) == "—:—")
    }
}

struct VideoPreviewFileTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func rangeReadsAreBoundedAndStayPinnedToOneFile() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("原片%.mov")
        let bytes = Data((0..<2048).map { UInt8($0 % 255) })
        try bytes.write(to: url)
        let file = try VideoPreviewFile(root: root, path: url.lastPathComponent)
        #expect(file.size == 2048)
        #expect(try file.read(offset: 2000, count: 256) == bytes.subdata(in: 2000..<2048))
        #expect(try file.read(offset: 2048, count: 20).isEmpty)
        #expect(throws: WorkspaceFailure.self) { try file.read(offset: -1, count: 1) }
        #expect(throws: WorkspaceFailure.self) { try file.read(offset: 0, count: VideoPreviewFile.maximumChunk + 1) }
        #expect(throws: WorkspaceFailure.self) { try file.read(offset: 3000, count: 1) }
        try Data([9]).write(to: url)
        #expect(throws: WorkspaceFailure.self) { try file.read(offset: 0, count: 1) }
    }
    @Test func pathLinksSpecialFilesAndOversizeAreRejected() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("good.mov"))
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("link.mov").path, withDestinationPath: "good.mov")
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("dir").path, withDestinationPath: root.path)
        #expect(mkfifo(root.appendingPathComponent("fifo.mov").path, 0o600) == 0)
        for path in ["../good.mov", "/good.mov", "dir/good.mov", "link.mov", "fifo.mov", "", "nul\0.mov"] {
            #expect(throws: WorkspaceFailure.self) { try VideoPreviewFile(root: root, path: path) }
        }
        let huge = root.appendingPathComponent("huge.mov")
        let fd = Darwin.open(huge.path, O_CREAT | O_WRONLY, 0o600)
        defer { Darwin.close(fd) }
        #expect(ftruncate(fd, VideoPreviewFile.maximumBytes + 1) == 0)
        #expect(throws: WorkspaceFailure.self) { try VideoPreviewFile(root: root, path: "huge.mov") }
    }
    @Test func cancellationDoesNotStartFileAccess() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoPreviewResource.open(root: URL(fileURLWithPath: "/nonexistent"), path: "x.mov")
        }
        do {
            _ = try await task.value
            Issue.record("Canceled resource opened")
        } catch is CancellationError {} catch { Issue.record("Unexpected cancellation: \(error)") }
    }
}

/// No AVPlayer, audio track, AppKit, view or application host. Tiny owned
/// fixtures are encoded offscreen; only async metadata and a single frame load.
@Suite(.serialized) struct VideoPreviewResourceTests {
    private func fixture(root: URL, suffix: String, type: AVFileType, codec: AVVideoCodecType) async throws -> URL {
        let url = root.appendingPathComponent("sample." + suffix)
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(
            mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32,
            ])
        try #require(writer.canAdd(input))
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        #expect(
            CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &buffer)
                == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let pointer = CVPixelBufferGetBaseAddress(pixels) { memset(pointer, 128, CVPixelBufferGetDataSize(pixels)) }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for index in 0..<2 {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(3)
            while !input.isReadyForMoreMediaData, clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
            try #require(input.isReadyForMoreMediaData)
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 2)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
    @Test func mp4MovM4vLoadThroughPinnedRangesAndDecodeOneVideoFrame() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (suffix, type, codec) in [
            ("mov", AVFileType.mov, AVVideoCodecType.jpeg), ("mp4", .mp4, .h264), ("m4v", .m4v, .h264),
        ] {
            let url = try await fixture(root: root, suffix: suffix, type: type, codec: codec)
            let resource = try await VideoPreviewResource.open(root: root, path: url.lastPathComponent)
            defer { resource.cancel() }
            #expect(resource.asset.url.scheme == "hycode-video")
            #expect(resource.asset.referenceRestrictions == .forbidAll)
            let metadata = try await resource.metadata()
            #expect(metadata.width == 32 && metadata.height == 32)
            #expect(abs(metadata.duration - 1) < 0.05 && metadata.bytes > 0)
            let generator = AVAssetImageGenerator(asset: resource.asset)
            generator.maximumSize = CGSize(width: 64, height: 64)
            let frame = try await generator.image(at: .zero)
            #expect(frame.image.width == 32 && frame.image.height == 32)
            #expect(try await resource.asset.loadTracks(withMediaType: .audio).isEmpty)
            print("VIDEO_FORMAT_PASS: " + suffix)
        }
    }
    @Test func cancelReleasesThePinnedFileAndAccessLease() async throws {
        final class Lease: @unchecked Sendable {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fixture".utf8).write(to: root.appendingPathComponent("lease.mov"))
        var lease: Lease? = Lease()
        weak let weakLease = lease
        var resource: VideoPreviewResource? = try await VideoPreviewResource.open(
            root: root, path: "lease.mov", keepingAlive: lease)
        lease = nil
        #expect(weakLease != nil)
        resource?.cancel()
        resource = nil
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while weakLease != nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(weakLease == nil)
    }
    @Test func corruptedAndCanceledResourcesCannotBecomeReady() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("invalid movie".utf8).write(to: root.appendingPathComponent("bad.mov"))
        let resource = try await VideoPreviewResource.open(root: root, path: "bad.mov")
        do {
            _ = try await resource.metadata()
            Issue.record("Corrupt video accepted")
        } catch {}
        resource.cancel()
        do {
            _ = try await resource.metadata()
            Issue.record("Canceled video accepted")
        } catch {}
    }
}
