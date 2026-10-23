import Foundation
import HyCodeWorkspace
import WebKit

/// Prepared before a WebView can load any source content. Rule lists also
/// intercept DNS-prefetch/preconnect, which are not navigation and can bypass
/// a CSP-only policy. No runtime download or network permission fallback.
@MainActor enum MarkupNetworkPolicy {
    private static var preparation: Task<WKContentRuleList, Error>?
    static func rules() async throws -> WKContentRuleList {
        if let preparation { return try await preparation.value }
        let task = Task<WKContentRuleList, Error> { @MainActor in
            guard
                let value = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: MarkupPage.networkRuleListIdentifier,
                    encodedContentRuleList: MarkupPage.networkRules)
            else { throw MarkupResourcePolicy.failure("网络拦截规则不可用") }
            return value
        }
        preparation = task
        do {
            return try await task.value
        } catch {
            preparation = nil
            throw error
        }
    }
}
