import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct MarkupResourcePolicy: Sendable {
    public let token: String
    public let baseURL: URL
    public init(path: String, token: UUID = UUID()) throws {
        guard Self.safePath(path) else { throw Self.failure("预览路径必须位于项目内") }
        self.token = token.uuidString.lowercased()
        var value = URLComponents()
        value.scheme = "hycode-preview"
        value.host = self.token
        value.path = "/" + path
        guard let url = value.url else { throw Self.failure("预览路径无效") }
        baseURL = url
    }
    public func path(for url: URL) throws -> String {
        guard url.absoluteString.utf8.count <= 8192, url.scheme == "hycode-preview", url.host == token,
            url.user == nil, url.password == nil, url.port == nil, url.path.hasPrefix("/")
        else { throw Self.failure("预览只允许当前项目资源") }
        let path = String(url.path.dropFirst())
        guard Self.safePath(path) else { throw Self.failure("资源路径无效") }
        return path
    }
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 8192 && !path.contains("\0")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }
    public static func failure(_ message: String) -> WorkspaceFailure {
        .init(code: "markup_resource", message: message)
    }
}
public struct MarkupResource: Sendable {
    public let data: Data
    public let mime: String
    public let pixels: Int
}
/// Serial native decoding bounds temporary image allocation. Every resource is
/// anchored by no-follow descriptors; WebKit never receives a disk file URL.
public actor MarkupResourceLoader {
    public init() {}
    public func load(root: URL, path: String) throws -> MarkupResource {
        try Task.checkCancellation()
        guard MarkupResourcePolicy.safePath(path) else { throw MarkupResourcePolicy.failure("资源路径无效") }
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let images = [
            "png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "heif", "svg", "ico", "bmp", "tif", "tiff", "jp2",
            "icns",
        ]
        guard ext == "css" || images.contains(ext) else { throw MarkupResourcePolicy.failure("预览资源仅支持 CSS 和图片") }
        let data = try PreviewFileIO.read(root: root, path: path, limit: ext == "css" ? 1_048_576 : 8_388_608)
        if ext == "css" {
            guard String(data: data, encoding: .utf8) != nil else {
                throw MarkupResourcePolicy.failure("CSS 需要 UTF-8 编码")
            }
            return MarkupResource(data: data, mime: "text/css", pixels: 0)
        }
        let image = try ImagePreviewDecoder.decode(data, path: path).image
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else {
            throw MarkupResourcePolicy.failure("图片资源编码失败")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 32 * 1024 * 1024 else {
            throw MarkupResourcePolicy.failure("图片资源超过预览输出上限")
        }
        try Task.checkCancellation()
        return MarkupResource(data: output as Data, mime: "image/png", pixels: image.width * image.height)
    }
}
