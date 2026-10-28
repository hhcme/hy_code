import Foundation
import Testing

@testable import HyCodeWorkspace

struct CodexTranscriptTests {
    private func event(_ method: String, item: [String: Any], turn: String = "turn-a") -> JSONValue {
        JSONValue(["method": method, "params": ["item": item, "turnId": turn]])
    }
    private let patch =
        "--- a/source.swift\n+++ b/source.swift\n@@ -1 +1,2 @@\n-old\n+new\n+++ literal code, not a file header\n"
    @Test func commandsRetainStreamOutputAndAuthoritativeStatusAndActions() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("了解项目")
        let command: [String: Any] = [
            "id": "read", "type": "commandExecution", "command": "cat source.swift", "status": "inProgress",
            "commandActions": [["type": "read", "path": "Sources/source.swift", "name": "source.swift"]],
        ]
        try chat.receive(event("item/started", item: command))
        try chat.receive(
            JSONValue([
                "method": "item/commandExecution/outputDelta",
                "params": ["itemId": "read", "turnId": "turn-a", "delta": "hello"],
            ]))
        #expect(chat.messages.last?.text.contains("hello") == true)
        var completed = command
        completed["status"] = "completed"
        completed["durationMs"] = 4200
        completed["exitCode"] = 0
        completed["aggregatedOutput"] = "authoritative output"
        try chat.receive(event("item/completed", item: completed))
        #expect(chat.messages.count == 2)
        let message = try #require(chat.messages.last)
        #expect(message.turnID == "turn-a" && message.activity?.exitCode == 0)
        #expect(message.text == "cat source.swift\nauthoritative output")
        #expect(CodexChatPresentation.activityTitle(message) == "已读取 source.swift")
        var failed = completed
        failed["status"] = "failed"
        try chat.receive(event("item/completed", item: failed))
        #expect(CodexChatPresentation.activityTitle(try #require(chat.messages.last)) == "读取失败 source.swift")
    }
    @Test func unifiedDiffPreservesLiteralHunkLinesAndHandlesAddsDeletesAndRenames() throws {
        let text =
            "diff --git a/source.swift b/source.swift\n" + patch
            + "diff --git a/new.txt b/new.txt\n--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+created\n"
            + "diff --git a/gone.txt b/gone.txt\n--- a/gone.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-deleted\n"
            + "diff --git a/old name.txt b/new name.txt\nsimilarity index 100%\nrename from old name.txt\nrename to new name.txt\n"
        let files = CodexUnifiedDiff.files(text)
        #expect(files.map(\.path) == ["source.swift", "new.txt", "gone.txt", "new name.txt"])
        #expect(files.map(\.kind) == ["update", "add", "delete", "update"])
        #expect(files[0].added == 2 && files[0].removed == 1)
        #expect(files[1].added == 1 && files[2].removed == 1)
        #expect(files[3].added == 0 && files[3].removed == 0)
        #expect(files[0].diff.contains("+++ literal code, not a file header"))
        let restored = try JSONDecoder().decode(CodexFileChange.self, from: JSONEncoder().encode(files[0]))
        #expect(restored == files[0])
    }
    @Test func aggregateChangesReplacePerToolCountsAndAnEmptyAggregateClearsThem() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("修改代码")
        try chat.receive(
            event(
                "item/completed",
                item: [
                    "id": "patch", "type": "fileChange", "status": "completed",
                    "changes": [["path": "source.swift", "kind": ["type": "update"], "diff": patch]],
                ]))
        #expect(CodexChangeSummary(messages: chat.messages).added == 2)
        let aggregate =
            "diff --git a/source.swift b/source.swift\n--- a/source.swift\n+++ b/source.swift\n@@ -1 +1 @@\n-old\n+final\n"
        try chat.receive(
            JSONValue(["method": "turn/diff/updated", "params": ["turnId": "turn-a", "diff": aggregate]]))
        let summary = CodexChangeSummary(messages: chat.messages)
        #expect(summary.files.count == 1 && summary.added == 1 && summary.removed == 1)
        #expect(CodexTranscriptEntry.project(chat.messages).count == 2)
        try chat.receive(JSONValue(["method": "turn/diff/updated", "params": ["turnId": "turn-a", "diff": ""]]))
        #expect(CodexChangeSummary(messages: chat.messages).files.isEmpty)
    }
    @Test func repeatedHeaderOnlyPatchesOfOneFileDoNotCountTheNextHeadersAsContent() throws {
        let one = "--- a/source.swift\n+++ b/source.swift\n@@ -1 +1 @@\n-old\n+new\n"
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("两次修改同一文件")
        for id in ["patch-a", "patch-b"] {
            try chat.receive(
                event(
                    "item/completed",
                    item: [
                        "id": id, "type": "fileChange", "status": "completed",
                        "changes": [["path": "source.swift", "kind": ["type": "update"], "diff": one]],
                    ]))
        }
        let summary = CodexChangeSummary(messages: chat.messages)
        #expect(summary.files.count == 1 && summary.added == 2 && summary.removed == 2)
        #expect(CodexDiffStatistics(one + one).added == 2)
        #expect(CodexDiffStatistics(one + one).removed == 2)
    }
    @Test func failedPatchesAreNotPresentedAsCompletedAndANewPromptStartsANewSummary() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("第一个任务")
        let failed: [String: Any] = [
            "id": "failed", "type": "fileChange", "status": "failed",
            "changes": [["path": "failed.swift", "kind": ["type": "update"], "diff": patch]],
        ]
        try chat.receive(event("item/completed", item: failed))
        #expect(CodexChangeSummary(messages: chat.messages).files.isEmpty)
        var success = failed
        success["id"] = "success"
        success["status"] = "completed"
        try chat.receive(event("item/completed", item: success))
        #expect(CodexChangeSummary(messages: chat.messages).files.count == 1)
        try chat.addUserMessage("第二个任务")
        #expect(CodexChangeSummary(messages: chat.messages).files.isEmpty)
    }
    @Test func activitiesCollapseOnlyAcrossContiguousToolsAndKeepStableIdentities() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("任务")
        try chat.receive(
            event(
                "item/completed",
                item: [
                    "id": "read", "type": "commandExecution", "command": "cat file",
                    "commandActions": [["type": "read", "path": "file"]],
                ]))
        try chat.receive(
            event(
                "item/completed",
                item: [
                    "id": "search", "type": "commandExecution", "command": "rg text",
                    "commandActions": [["type": "search", "query": "text"]],
                ]))
        try chat.receive(
            event(
                "item/completed",
                item: ["id": "message", "type": "agentMessage", "text": "接着处理", "phase": "commentary"]))
        try chat.receive(
            event(
                "item/completed",
                item: ["id": "command", "type": "commandExecution", "command": "build", "durationMs": 4200]))
        let entries = CodexTranscriptEntry.project(chat.messages)
        #expect(entries.count == 4 && entries[1].messages.count == 2)
        #expect(entries[1].title == "读取了文件、搜索了代码")
        #expect(entries[1].id == chat.messages[1].id)
        #expect(CodexChatPresentation.activityTitle(chat.messages.last!) == "已在4秒内运行 build")
        #expect(chat.messages[3].phase == "commentary")
    }
    @Test func onlyPublicReasoningSummariesAreCollectedAndTokenUsageIsActual() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.receive(
            JSONValue([
                "method": "item/reasoning/textDelta", "params": ["itemId": "thought", "delta": "private raw content"],
            ]))
        #expect(chat.messages.isEmpty && chat.tokenUsage == nil)
        try chat.receive(
            JSONValue([
                "method": "item/reasoning/summaryTextDelta",
                "params": ["itemId": "summary", "summaryIndex": 0, "delta": "公开摘要"],
            ]))
        try chat.receive(
            event(
                "item/completed",
                item: ["id": "summary", "type": "reasoning", "summary": ["完整公开摘要"], "content": ["private raw content"]])
        )
        #expect(chat.messages.count == 1 && chat.messages[0].text == "完整公开摘要" && chat.messages[0].role == .reasoning)
        try chat.receive(
            JSONValue([
                "method": "thread/tokenUsage/updated",
                "params": ["tokenUsage": ["modelContextWindow": 996147, "last": ["totalTokens": 1024]]],
            ]))
        #expect(chat.tokenUsage?.lastRequestTokens == 1024 && chat.tokenUsage?.modelContextWindow == 996147)
        try chat.receive(
            JSONValue([
                "method": "turn/completed",
                "params": ["turn": ["id": "turn-a", "status": "interrupted", "durationMs": 458000]],
            ]))
        #expect(chat.messages.last?.activity?.status == "interrupted")
        #expect(CodexChatPresentation.duration(chat.messages.last!.activity!.durationMs!) == "7分钟38秒")
    }
    @Test func structuredMetadataIsRedactedBudgetedAndOldHistoryStillDecodes() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        let secret = "fixture-only-secret"
        try chat.receive(
            event(
                "item/completed",
                item: [
                    "id": "patch", "type": "fileChange", "status": "completed",
                    "changes": [["path": secret, "diff": "@@ -1 +1 @@\n-old\n+" + secret]],
                ]), redacting: secret)
        let encoded = try JSONEncoder().encode(chat)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
        let before = chat.messages
        #expect(throws: LanguageServiceFailure.self) {
            try chat.receive(
                event(
                    "item/completed",
                    item: [
                        "id": "over", "type": "fileChange",
                        "changes": [["path": "file", "diff": String(repeating: "x", count: 262145)]],
                    ]))
        }
        #expect(chat.messages == before)
        let old = CodexMessage(role: .assistant, text: "旧消息", itemID: "old")
        let decoded = try JSONDecoder().decode(CodexMessage.self, from: JSONEncoder().encode(old))
        #expect(decoded.activity == nil && decoded.turnID == nil && decoded.text == "旧消息")
    }
    @Test func scrollPinningRequiresTheActualBottomAndRejectsInvalidGeometry() {
        #expect(CodexChatPresentation.nearBottom(documentHeight: 1000, viewportBottom: 998))
        #expect(!CodexChatPresentation.nearBottom(documentHeight: 1000, viewportBottom: 950))
        #expect(!CodexChatPresentation.nearBottom(documentHeight: .nan, viewportBottom: 1000))
    }
    @Test func anInterruptedOrDisconnectedRunDoesNotKeepActivitiesRunningForever() throws {
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.receive(
            event(
                "item/started",
                item: ["id": "command", "type": "commandExecution", "command": "fixed fixture", "status": "inProgress"])
        )
        chat.updatedAt = Date(timeIntervalSince1970: 1)
        chat.finishPendingActivities("interrupted")
        #expect(chat.messages[0].activity?.status == "interrupted")
        #expect(chat.updatedAt > Date(timeIntervalSince1970: 1))
        try chat.receive(
            event(
                "item/started",
                item: ["id": "other", "type": "commandExecution", "command": "another fixture", "status": "inProgress"])
        )
        chat.finishPendingActivities("unknown")
        #expect(chat.messages[1].activity?.status == "unknown")
        #expect(CodexChatPresentation.activityTitle(chat.messages[1]) == "执行状态未知 another fixture")
        for action in ["read", "search", "listFiles"] {
            var message = chat.messages[1]
            message.activity?.actions = [CodexCommandAction(kind: action, path: "source.swift")]
            #expect(CodexChatPresentation.activityTitle(message).contains("状态未知"))
        }
    }
    @Test func stoppingAtTheExactItemAndConversationBudgetsStillAllowsPersistence() throws {
        for count in [1, 4] {
            var chat = CodexConversation(configuration: .deepSeek())
            for index in 0..<count {
                let id = "command-\(index)"
                try chat.receive(
                    event(
                        "item/started",
                        item: ["id": id, "type": "commandExecution", "command": "", "status": "inProgress"]))
                try chat.receive(
                    JSONValue([
                        "method": "item/commandExecution/outputDelta",
                        "params": ["itemId": id, "delta": String(repeating: "x", count: 262144 - 16)],
                    ]))
            }
            #expect(chat.messages.allSatisfy { $0.payloadBytes == 262144 })
            chat.finishPendingActivities("interrupted")
            #expect(chat.messages.allSatisfy { $0.payloadBytes == 262144 && $0.activity?.status == "interrupted" })
            var state = CodexProjectState()
            state.conversations = [chat]
            try state.validate()
            let restored = try JSONDecoder().decode(CodexProjectState.self, from: JSONEncoder().encode(state))
            try restored.validate()
        }
    }
    @Test func largeChangeListsRemainVisibleAndExplicitlyReportTheProjectionLimit() throws {
        let text = (0..<257).map { index in
            "diff --git a/file-\(index).txt b/file-\(index).txt\n--- /dev/null\n+++ b/file-\(index).txt\n@@ -0,0 +1 @@\n+new\n"
        }.joined()
        let parsed = CodexUnifiedDiff.parse(text)
        #expect(parsed.files.count == 256 && parsed.fileCount == 257 && parsed.limited)
        var chat = CodexConversation(configuration: .deepSeek())
        try chat.addUserMessage("查看变化")
        for (index, range) in [0..<128, 128..<257].enumerated() {
            let changes = range.map { file in
                ["path": "file-\(file).txt", "kind": ["type": "add"], "diff": "@@ -0,0 +1 @@\n+new\n"] as [String: Any]
            }
            try chat.receive(
                event(
                    "item/completed",
                    item: ["id": "patch-\(index)", "type": "fileChange", "status": "completed", "changes": changes]))
        }
        let fallback = CodexChangeSummary(messages: chat.messages)
        #expect(fallback.files.count == 256 && fallback.fileCount == 257 && fallback.limited)
        try chat.receive(JSONValue(["method": "turn/diff/updated", "params": ["turnId": "turn-a", "diff": text]]))
        let aggregate = CodexChangeSummary(messages: chat.messages)
        #expect(aggregate.files.count == 256 && aggregate.fileCount == 257 && aggregate.limited)
        try chat.receive(JSONValue(["method": "turn/diff/updated", "params": ["turnId": "turn-a", "diff": ""]]))
        let cleared = CodexChangeSummary(messages: chat.messages)
        #expect(cleared.fileCount == 0 && !cleared.limited && cleared.files.isEmpty)
    }
}
