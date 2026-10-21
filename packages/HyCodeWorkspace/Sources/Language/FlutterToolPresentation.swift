import Foundation

/// Presentation follows explicit tool actions and real debugger stops; merely
/// opening a tool tab never starts a process or changes the runtime state.
public enum FlutterToolSection: String, CaseIterable, Identifiable, Sendable {
    case debugger, console, inspector, tests
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .debugger: "线程和变量"
        case .console: "控制台"
        case .inspector: "Flutter Inspector"
        case .tests: "测试结果"
        }
    }
    public static func initialSection(for command: String) -> Self {
        command == "test" ? .tests : .console
    }
}

/// A dialog edits a snapshot. Workspace switches or concurrent changes must not
/// replace the new workspace's configuration with an old dialog's draft.
public struct FlutterConfigurationDraft: Sendable {
    public let context: UUID
    public let original: FlutterLaunchConfiguration
    public var value: FlutterLaunchConfiguration
    public init(context: UUID, configuration: FlutterLaunchConfiguration) {
        self.context = context
        original = configuration
        value = configuration
    }
    public func validated(context: UUID, current: FlutterLaunchConfiguration, busy: Bool) throws
        -> FlutterLaunchConfiguration
    {
        guard self.context == context, original == current, !busy else {
            throw LanguageServiceFailure("运行配置已改变或任务正在执行，请重新打开配置")
        }
        try value.validate()
        return value
    }
}
