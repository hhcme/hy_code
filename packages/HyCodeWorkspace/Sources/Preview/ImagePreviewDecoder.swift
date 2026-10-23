import CHyCodeCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Immutable decoded pixels cross the worker boundary. No NSImage/AppKit or
/// mutable image-source handles escape the worker; no lazy decode on UI draw.
public struct ImagePreviewContent: @unchecked Sendable {
    public let image: CGImage
    public let pixelSize: CGSize
    public let format: String
    public let byteCount: Int
    public let frameCount: Int
    public let downsampled: Bool
}
public actor ImagePreviewLoader {
    public static let shared = ImagePreviewLoader()
    public func load(root: URL, path: String) throws -> ImagePreviewContent {
        try Task.checkCancellation()
        let data = try PreviewFileIO.read(root: root, path: path)
        return try ImagePreviewDecoder.decode(data, path: path)
    }
}
public enum ImagePreviewDecoder {
    public static let maximumDecodedEdge = 4096
    public static let maximumSourcePixels = 160_000_000.0
    private static func failure(_ message: String) -> WorkspaceFailure {
        WorkspaceFailure(code: "image_decode", message: message)
    }
    /// Pure background entry also used by generated no-GUI fixtures.
    public static func decode(_ data: Data, path: String) throws -> ImagePreviewContent {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= PreviewFileIO.maximumBytes else { throw failure("图片为空或超过 64 MiB") }
        if ImagePreviewFormat.isSVG(path) { return try svg(data) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let type = CGImageSourceGetType(source), UTType(type as String)?.conforms(to: .image) == true,
            CGImageSourceGetStatus(source) == .statusComplete
        else { throw failure("无法识别图片或文件数据不完整") }
        let count = CGImageSourceGetCount(source)
        let icon = ["com.microsoft.ico", "com.microsoft.cur", "com.apple.icns"].contains(type as String)
        var index = 0
        if icon {
            var largest = 0.0
            for candidate in 0..<min(128, count) {
                let info = CGImageSourceCopyPropertiesAtIndex(source, candidate, options) as? [CFString: Any]
                let w = (info?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
                let h = (info?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
                if w >= 1, h >= 1, w <= 65_535, h <= 65_535, w * h <= maximumSourcePixels, w * h > largest {
                    index = candidate
                    largest = w * h
                }
            }
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width.isFinite, height.isFinite, width >= 1, height >= 1,
            width <= 65_535, height <= 65_535, width * height <= maximumSourcePixels
        else {
            throw failure("无法识别此图片，或其像素尺寸超过预览限制")
        }
        try Task.checkCancellation()
        let edge = min(maximumDecodedEdge, Int(max(width, height)))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge, kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary) else {
            throw failure("系统未能解码此图片格式或文件已损坏")
        }
        // An explicit bounded RGBA surface makes the projection eagerly decoded.
        guard decoded.width <= maximumDecodedEdge, decoded.height <= maximumDecodedEdge,
            let context = CGContext(
                data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8,
                bytesPerRow: decoded.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw failure("图片预览分配失败") }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        guard let image = context.makeImage() else { throw failure("无法生成图片预览") }
        try Task.checkCancellation()
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let size = CGSize(width: rotated ? height : width, height: rotated ? width : height)
        let name = UTType(type as String)?.preferredFilenameExtension?.uppercased() ?? (type as String)
        return ImagePreviewContent(
            image: image, pixelSize: size, format: name, byteCount: data.count,
            frameCount: icon ? 1 : max(1, count), downsampled: Double(edge) < max(width, height))
    }
    private static func svg(_ data: Data) throws -> ImagePreviewContent {
        guard data.count <= 2 * 1024 * 1024 else { throw failure("SVG 文件超过 2 MiB 预览上限") }
        let result = data.withUnsafeBytes { bytes in
            hycode_svg_render(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, 2048, true)
        }
        defer {
            hycode_buffer_free(result.pixels)
            hycode_buffer_free(result.error)
        }
        if let pointer = result.error.data, result.error.len > 0 {
            throw try JSONDecoder().decode(WorkspaceFailure.self, from: Data(bytes: pointer, count: result.error.len))
        }
        let w = Int(result.width)
        let h = Int(result.height)
        guard w > 0, h > 0, w <= maximumDecodedEdge, h <= maximumDecodedEdge,
            result.pixels.len == w * h * 4, let pointer = result.pixels.data,
            let provider = CGDataProvider(data: Data(bytes: pointer, count: result.pixels.len) as CFData),
            let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw failure("SVG 像素响应无效") }
        try Task.checkCancellation()
        return ImagePreviewContent(
            image: image, pixelSize: CGSize(width: result.source_width, height: result.source_height),
            format: "SVG", byteCount: data.count, frameCount: 1, downsampled: false)
    }
}
