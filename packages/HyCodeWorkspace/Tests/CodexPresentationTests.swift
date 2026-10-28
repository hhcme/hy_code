import Foundation
import Testing

@testable import HyCodeWorkspace

struct CodexPresentationTests {
    @Test func composerRemainsCompactForEmptyAndBoundedForLargeInput() {
        #expect(CodexChatPresentation.composerHeight(0) == 46)
        #expect(CodexChatPresentation.composerHeight(86) == 86)
        #expect(CodexChatPresentation.composerHeight(9_000) == 166)
        #expect(CodexChatPresentation.composerHeight(.nan) == 46)
        #expect(CodexChatPresentation.contextName(1_048_576) == "1M")
        #expect(CodexChatPresentation.contextName(131_072) == "128K")
    }
    @Test func fencedCodePreservesLiteralContentsAndIncompleteStream() {
        let body = "let value = `literal`\nprint(\"你好 👋\")\n"
        #expect(
            CodexChatMarkdown.blocks("说明\n```swift\n" + body + "```\n完成") == [
                .markdown("说明"), .code(language: "swift", text: body), .markdown("完成"),
            ])
        #expect(CodexChatMarkdown.blocks("~~~text\n未完成的输出") == [.code(language: "text", text: "未完成的输出")])
        #expect(CodexChatMarkdown.blocks("inline ``` code") == [.markdown("inline ``` code")])
        #expect(CodexChatMarkdown.blocks("````txt\n```\n````") == [.code(language: "txt", text: "```\n")])
        #expect(
            CodexChatMarkdown.blocks("说明\r\n```swift\r\nlet x = 1\r\n```\r\n完成") == [
                .markdown("说明\r"), .code(language: "swift", text: "let x = 1\r\n"), .markdown("完成"),
            ])
    }
    @Test func excessiveFencesFallBackWithoutDiscardingAnySource() {
        let text = String(repeating: "```text\ncontent\n```\n", count: 256)
        #expect(CodexChatMarkdown.blocks(text) == [.markdown(text)])
    }
    @Test func applicationDefaultsKeepDraftsAndExplicitProjectSettingsIndependent() throws {
        let a = URL(fileURLWithPath: "/fixture/project-a")
        let b = URL(fileURLWithPath: "/fixture/project-b")
        var defaults = CodexConfiguration.deepSeek()
        defaults.credentialScope = .application
        defaults.credentialID = UUID()
        #expect(defaults.credentialAccount(root: a) == defaults.credentialAccount(root: b))
        var project = defaults
        project.credentialScope = .project
        #expect(project.credentialAccount(root: a) != project.credentialAccount(root: b))
        var state = CodexProjectState()
        var draft = CodexConversation(configuration: state.configuration)
        draft.draft = "你好呀"
        state.conversations = [draft]
        state.selectedID = draft.id
        let inherited = state.inheritConfiguration(defaults)
        #expect(inherited)
        #expect(state.selectedID == draft.id && state.conversations.count == 1)
        #expect(state.conversations[0].draft == "你好呀" && state.conversations[0].model == "deepseek-v4-pro")
        state.configuration.contextWindow = 131_072
        state.configuration.model = "deepseek-flash"
        let originalID = defaults.credentialID
        defaults.credentialID = UUID()
        let refreshed = state.inheritConfiguration(defaults)
        #expect(refreshed)
        #expect(state.configuration.credentialID != originalID)
        #expect(state.configuration.contextWindow == 131_072 && state.configuration.model == "deepseek-flash")
        state.configuration = project
        let changedExplicit = state.inheritConfiguration(defaults)
        #expect(!changedExplicit)
        #expect(state.configuration == project)
        let decoded = try JSONDecoder().decode(CodexConfiguration.self, from: JSONEncoder().encode(defaults))
        #expect(decoded.credentialScope == .application)
        #expect(decoded.credentialAccount(root: a) == defaults.credentialAccount(root: a))
    }
}
