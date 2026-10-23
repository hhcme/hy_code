import Foundation

public struct MarkupResourceBudget: Sendable {
    public private(set) var requests = 0
    public private(set) var deliveredBytes = 0
    public private(set) var decodedPixels = 0
    public init() {}
    public mutating func admit(active: Int) throws {
        guard active >= 0, active < 256, requests < 256 else { throw MarkupResourcePolicy.failure("页面资源请求超限") }
        requests += 1
    }
    public mutating func record(bytes: Int, pixels: Int) throws {
        guard bytes >= 0, pixels >= 0, bytes <= 64 * 1024 * 1024 - deliveredBytes,
            pixels <= 32_000_000 - decodedPixels
        else { throw MarkupResourcePolicy.failure("页面图片资源超过预览预算") }
        deliveredBytes += bytes
        decodedPixels += pixels
    }
}
