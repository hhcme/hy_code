import Foundation
import Testing

@testable import HyCodeWorkspace

struct FlutterPresentationTests {
    @Test func editingDoesNotChangeConfigurationUntilAccepted() throws {
        let context = UUID()
        let current = FlutterLaunchConfiguration()
        var draft = FlutterConfigurationDraft(context: context, configuration: current)
        draft.value.program = "lib/demo.dart"
        draft.value.defines = ["ENV=development"]
        #expect(current.program == "lib/main.dart" && current.defines.isEmpty)
        let accepted = try draft.validated(context: context, current: current, busy: false)
        #expect(accepted.program == "lib/demo.dart" && accepted.defines == ["ENV=development"])
    }
    @Test func staleWorkspaceConcurrentEditAndRunningTaskRejectDraft() {
        let context = UUID()
        let current = FlutterLaunchConfiguration()
        let draft = FlutterConfigurationDraft(context: context, configuration: current)
        #expect(throws: LanguageServiceFailure.self) {
            try draft.validated(context: UUID(), current: current, busy: false)
        }
        var newer = current
        newer.deviceID = "another-device"
        #expect(throws: LanguageServiceFailure.self) {
            try draft.validated(context: context, current: newer, busy: false)
        }
        #expect(throws: LanguageServiceFailure.self) {
            try draft.validated(context: context, current: current, busy: true)
        }
    }
    @Test func invalidDraftCannotOverwriteCurrentConfiguration() {
        let context = UUID()
        let current = FlutterLaunchConfiguration()
        var draft = FlutterConfigurationDraft(context: context, configuration: current)
        draft.value.program = "../outside.dart"
        #expect(throws: LanguageServiceFailure.self) {
            try draft.validated(context: context, current: current, busy: false)
        }
        #expect(current.program == "lib/main.dart")
    }
}
