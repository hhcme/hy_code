import Foundation
import HyCodeWorkspace
import WebKit

/// WKURLSchemeTask is owned/called exclusively on MainActor. I/O/decoding is
/// serialized by the loader actor; stop removes the task before any callbacks.
@MainActor final class MarkupResourceHandler: NSObject, WKURLSchemeHandler {
    private let access: WorkspaceAccess
    private let loader = MarkupResourceLoader()
    private var policy: MarkupResourcePolicy
    private var generation = UUID()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var budget = MarkupResourceBudget()
    var failed: (() -> Void)?
    init(access: WorkspaceAccess, policy: MarkupResourcePolicy) {
        self.access = access
        self.policy = policy
    }
    func reset(_ policy: MarkupResourcePolicy) {
        cancel()
        self.policy = policy
        budget = MarkupResourceBudget()
    }
    func cancel() {
        generation = UUID()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        do {
            guard let url = urlSchemeTask.request.url,
                urlSchemeTask.request.httpMethod == nil || urlSchemeTask.request.httpMethod == "GET"
            else { throw MarkupResourcePolicy.failure("资源请求无效") }
            let path = try policy.path(for: url)
            try budget.admit(active: tasks.count)
            let ticket = generation
            let loader = loader
            tasks[id] = Task { [weak self, access] in
                defer { withExtendedLifetime(access) {} }
                do {
                    let value = try await loader.load(root: access.url, path: path)
                    guard let self, !Task.isCancelled, self.generation == ticket,
                        self.tasks.removeValue(forKey: id) != nil
                    else { return }
                    try self.budget.record(bytes: value.data.count, pixels: value.pixels)
                    urlSchemeTask.didReceive(
                        URLResponse(
                            url: url, mimeType: value.mime, expectedContentLength: value.data.count,
                            textEncodingName: value.mime == "text/css" ? "utf-8" : nil))
                    urlSchemeTask.didReceive(value.data)
                    urlSchemeTask.didFinish()
                } catch {
                    guard let self, !Task.isCancelled, self.generation == ticket else { return }
                    self.tasks[id] = nil
                    urlSchemeTask.didFailWithError(error)
                    self.failed?()
                }
            }
        } catch {
            urlSchemeTask.didFailWithError(error)
            failed?()
        }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }
}
