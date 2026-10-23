import Darwin
import Foundation
import HyCodeWorkspace
import WebKit

/// Foundation CLI; only compiles fixed JSON to bytecode in an owned temporary
/// store. No WKWebView, NSApplication, window, navigation or network request.
@MainActor private final class Compilation {
    private(set) var finished = false
    private(set) var rule: WKContentRuleList?
    private(set) var error: Error?
    func run(store: WKContentRuleListStore, identifier: String, json: String) throws {
        guard Thread.isMainThread else { throw LanguageServiceFailure("Rule compiler requires the main run loop") }
        store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { [self] rule, error in
            MainActor.assumeIsolated {
                self.rule = rule
                self.error = error
                self.finished = true
            }
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished, Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard finished else { throw LanguageServiceFailure("Rule compiler timed out") }
    }
}

@main struct MarkupRuleProbe {
    @MainActor static func main() {
        do { try run() } catch {
            FileHandle.standardError.write(Data(("FAIL: " + MarkupPreviewFailure.preparation(error) + "\n").utf8))
            exit(1)
        }
    }
    @MainActor private static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HyCode-rule-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        guard let store = WKContentRuleListStore(url: root) else {
            throw LanguageServiceFailure("No isolated WebKit rule compiler")
        }
        let legacy = Compilation()
        try legacy.run(
            store: store, identifier: "owned-invalid-alternation",
            json: #"[{"trigger":{"url-filter":"^(https?|wss?|ftp)://"},"action":{"type":"block"}}]"#)
        guard legacy.rule == nil, let failure = legacy.error as NSError?,
            failure.domain == WKErrorDomain, failure.code == WKError.contentRuleListStoreCompileFailed.rawValue
        else { throw LanguageServiceFailure("Legacy alternation did not reproduce WKErrorDomain 6") }
        print("PASS: legacy alternation reproduces WKErrorDomain 6; " + MarkupPreviewFailure.preparation(failure))
        let current = Compilation()
        try current.run(store: store, identifier: MarkupPage.networkRuleListIdentifier, json: MarkupPage.networkRules)
        guard let rule = current.rule, rule.identifier == MarkupPage.networkRuleListIdentifier, current.error == nil
        else {
            throw current.error ?? LanguageServiceFailure("Current offline rules did not compile")
        }
        print("PASS: production offline rules compile with the system WebKit compiler; no WebView or GUI")
    }
}
