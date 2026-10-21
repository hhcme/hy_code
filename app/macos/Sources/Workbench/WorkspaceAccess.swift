import Foundation

/// Keeps the selected URL's access alive until every in-flight request releases it.
final class WorkspaceAccess: @unchecked Sendable {
    let url: URL
    let scoped: Bool
    init(url: URL) {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
    }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}
