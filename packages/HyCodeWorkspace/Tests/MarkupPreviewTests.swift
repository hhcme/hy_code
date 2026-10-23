import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HyCodeWorkspace

struct MarkupPreviewTests {
    @Test func formatModesAndFiniteScrollGeometry() {
        #expect(MarkupFormat.detect("README.MD") == .markdown)
        #expect(MarkupFormat.detect("notes.markdown") == .markdown)
        #expect(MarkupFormat.detect("index.htm") == .html)
        #expect(MarkupFormat.detect("Component.vue") == nil)
        #expect(MarkupPreviewMode.allCases.count == 3)
        #expect(MarkupScrollMapping.splitRatio(.nan) == 0.5)
        #expect(MarkupScrollMapping.splitRatio(-10) == 0.2)
        #expect(MarkupScrollMapping.splitRatio(99) == 0.8)
        #expect(MarkupScrollMapping.fraction(.infinity) == 0)
        #expect(MarkupScrollMapping.fraction(4) == 1)
        #expect(MarkupScrollMapping.line(2, count: 3) == 2)
        #expect(MarkupScrollMapping.line(2.5, count: 3) == nil)
        #expect(MarkupScrollMapping.line(.infinity, count: 3) == nil)
        #expect(MarkupScrollMapping.line(3, count: 3) == nil)
    }
    @Test func resourceURLsStayWithinTheCurrentPreviewAndSafePath() throws {
        let policy = try MarkupResourcePolicy(path: "文档/README %.md")
        let css = URL(string: "../styles/main.css?v=1", relativeTo: policy.baseURL)!.absoluteURL
        #expect(try policy.path(for: css) == "styles/main.css")
        for value in ["../outside.md", "/root.md", "a//b.md", "a/./b.md", "a/../b.md", "a\0b"] {
            #expect(!MarkupResourcePolicy.safePath(value))
        }
        for value in [
            "https://example.com/x.png", "file:///tmp/a.png", "data:image/png;base64,AA==",
            "hycode-preview://other/a.png", "hycode-preview://\(policy.token):9/a.png",
            "hycode-preview://user@\(policy.token)/a.png", "hycode-preview://\(policy.token)/%2e%2e/a.png",
        ] {
            #expect(throws: WorkspaceFailure.self) { try policy.path(for: URL(string: value)!) }
        }
    }
    @Test func pageResourceBudgetCannotOverflowAndRejectsExcessBeforeMutation() throws {
        var queued = MarkupResourceBudget()
        for active in 0..<12 { try queued.admit(active: active) }
        #expect(queued.requests == 12)  // More than four resources wait for the serial decoder.
        var budget = MarkupResourceBudget()
        #expect(throws: WorkspaceFailure.self) { try budget.admit(active: 256) }
        #expect(budget.requests == 0)
        for _ in 0..<256 { try budget.admit(active: 0) }
        #expect(throws: WorkspaceFailure.self) { try budget.admit(active: 0) }
        try budget.record(bytes: 64 * 1024 * 1024, pixels: 32_000_000)
        #expect(throws: WorkspaceFailure.self) { try budget.record(bytes: 1, pixels: 0) }
        #expect(throws: WorkspaceFailure.self) { try budget.record(bytes: Int.max, pixels: 0) }
        #expect(throws: WorkspaceFailure.self) { try budget.record(bytes: 0, pixels: 1) }
        #expect(budget.decodedPixels == 32_000_000)
    }
    @Test func offlineRulesCoverEveryNetworkResourceCategory() throws {
        let rules = try JSONDecoder().decode(JSONValue.self, from: Data(MarkupPage.networkRules.utf8)).array
        #expect(rules.count == 5)
        let expressions = try rules.map { rule in
            #expect(rule["action"]["type"].string == "block")
            #expect(rule["trigger"]["resource-type"] == .null)
            #expect(rule["trigger"]["url-filter-is-case-sensitive"] == .bool(false))
            let filter = try #require(rule["trigger"]["url-filter"].string)
            #expect(!filter.contains("|"))
            return try NSRegularExpression(pattern: filter, options: .caseInsensitive)
        }
        for url in [
            "https://example.com/a", "HTTP://example.com", "ws://example.com/socket", "wss://example.com",
            "ftp://example.com/a",
        ] {
            #expect(
                expressions.contains {
                    $0.firstMatch(in: url, range: NSRange(location: 0, length: url.utf16.count)) != nil
                })
        }
        for local in ["hycode-preview://id/a.css", "file:///tmp/a.png", "data:image/png;base64,AA=="] {
            #expect(
                !expressions.contains {
                    $0.firstMatch(in: local, range: NSRange(location: 0, length: local.utf16.count)) != nil
                })
        }
    }
    @Test func previewPreparationFailureIncludesTheWebKitCompilerReason() {
        let reason = "Rule list compilation failed: Disjunctions are not supported."
        let error = NSError(domain: "WKErrorDomain", code: 6, userInfo: [NSHelpAnchorErrorKey: reason])
        #expect(MarkupPreviewFailure.preparation(error) == "无法准备离线预览：" + reason)
        let generic = NSError(domain: "owned-test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Read failed"])
        #expect(MarkupPreviewFailure.preparation(generic).contains("Read failed"))
        let oversized = NSError(
            domain: "owned-test", code: 1, userInfo: [NSHelpAnchorErrorKey: String(repeating: "x", count: 4096)])
        #expect(MarkupPreviewFailure.preparation(oversized).count < 550)
    }
    @Test func unsavedNativeRevisionsAndUtf16GenerateTheSamePreviewWithoutWritingDisk() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let text = "# 标题😀\r\n\r\n- [x] 完成\r\n\r\n| A | B |\r\n| - | - |\r\n| 中 | 文 |\r\n"
        let bytes = Data([0xff, 0xfe] + text.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
        let file = root.appendingPathComponent("README.md")
        try bytes.write(to: file)
        let doc = NativeTextDocument(root: root, path: "README.md")
        _ = try await doc.open()
        let before = try await doc.markup(revision: 0, markdown: true)
        #expect(before.html.contains("标题😀") && before.html.contains("<table>"))
        #expect(before.html.contains("checkbox"))
        try await doc.replace(expected: 0, range: NSRange(location: 2, length: 2), text: "修改")
        do {
            _ = try await doc.markup(revision: 0, markdown: true)
            Issue.record("Stale preview was accepted")
        } catch {}
        let after = try await doc.markup(revision: 1, markdown: true)
        #expect(after.html.contains("修改😀") && after.blocks.first?.line == 0)
        #expect(try Data(contentsOf: file) == bytes)
        let page = MarkupPage.document(after, dark: true)
        #expect(page.range(of: MarkupPage.policy)!.lowerBound < page.range(of: "修改😀")!.lowerBound)
        #expect(MarkupPage.policy.contains("script-src 'none'") && MarkupPage.policy.contains("base-uri 'none'"))
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await doc.markup(revision: 1, markdown: true)
        }
        do {
            _ = try await canceled.value
            Issue.record("Canceled preview succeeded")
        } catch is CancellationError {} catch { Issue.record("Unexpected error") }
    }
    @Test func nativeResourcesReadCSSAndDecodeImagesWithoutFollowingLinksOrSpecialFiles() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = MarkupResourceLoader()
        let css = Data("p {color: red;} /* 中文 */".utf8)
        try css.write(to: root.appendingPathComponent("style.css"))
        #expect(try await loader.load(root: root, path: "style.css").data == css)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("link.css").path,
            withDestinationPath: root.appendingPathComponent("style.css").path)
        #expect(mkfifo(root.appendingPathComponent("pipe.css").path, 0o600) == 0)
        try Data(repeating: 32, count: 1_048_577).write(to: root.appendingPathComponent("large.css"))
        try Data("<script>alert('no')</script>".utf8).write(to: root.appendingPathComponent("script.js"))
        for path in ["link.css", "pipe.css", "large.css", "script.js", "../style.css"] {
            do {
                _ = try await loader.load(root: root, path: path)
                Issue.record("Unsafe resource accepted: \(path)")
            } catch {}
        }
        let context = CGContext(
            data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: root.appendingPathComponent("image.png"))
        let image = try await loader.load(root: root, path: "image.png")
        #expect(image.mime == "image/png" && image.pixels == 6)
        #expect(try ImagePreviewDecoder.decode(image.data, path: "image.png").pixelSize == CGSize(width: 3, height: 2))
    }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hycode-markup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
