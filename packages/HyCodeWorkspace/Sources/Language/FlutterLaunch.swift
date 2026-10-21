import Foundation

public struct FlutterDevice: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let platform: String
    public let emulator: Bool
    public static func parse(_ text: String) throws -> [Self] {
        guard text.utf8.count <= 1_048_576,
            let values = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
            case .array = values
        else { throw LanguageServiceFailure("设备列表不是有效的 machine JSON") }
        var seen = Set<String>()
        return values.array.prefix(200).compactMap { item in
            guard let id = item["id"].string, !id.isEmpty, id.count <= 512, seen.insert(id).inserted,
                item["isSupported"] != .bool(false)
            else { return nil }
            return Self(
                id: id, name: String((item["name"].string ?? id).prefix(512)),
                platform: String((item["targetPlatform"].string ?? "").prefix(128)),
                emulator: item["emulator"] == .bool(true))
        }
    }
}

public struct FlutterLaunchConfiguration: Codable, Sendable, Equatable {
    public enum Mode: String, CaseIterable, Codable, Sendable { case debug, profile, release }
    public var program = "lib/main.dart"
    public var deviceID = ""
    public var mode = Mode.debug
    public var flavor = ""
    public var defines: [String] = []
    public var arguments: [String] = []
    public var hotReloadOnSave = false
    public init() {}
    public func validate() throws {
        guard !program.isEmpty, !program.hasPrefix("/"), program.hasSuffix(".dart"), program.count <= 1_024,
            !program.split(separator: "/").contains(".."), !program.contains("\0"),
            deviceID.count <= 512, flavor.count <= 256,
            defines.count <= 100, arguments.count <= 100,
            (defines + arguments + [deviceID, flavor]).allSatisfy({ $0.count <= 4_096 && !$0.contains("\0") }),
            defines.allSatisfy({ $0.contains("=") && !$0.hasPrefix("=") })
        else { throw LanguageServiceFailure("运行配置无效：入口须为包内 Dart 文件，define 使用 KEY=VALUE") }
    }
    public func toolArguments() throws -> [String] {
        try validate()
        return ["--\(mode.rawValue)", "--no-pub"] + (deviceID.isEmpty ? [] : ["-d", deviceID])
            + (flavor.isEmpty ? [] : ["--flavor", flavor]) + defines.map { "--dart-define=" + $0 }
    }
    public func launchArguments(root: URL, debug: Bool) throws -> JSONValue {
        JSONValue([
            "cwd": root.path, "program": root.appendingPathComponent(program).path,
            "noDebug": !debug || mode != .debug, "toolArgs": try toolArguments(), "args": arguments,
            "debugSdkLibraries": false, "debugExternalPackageLibraries": false,
            "evaluateGettersInDebugViews": false, "evaluateToStringInDebugViews": false,
            "allowAnsiColorOutput": false,
        ])
    }
}

public struct FlutterBreakpoint: Codable, Sendable, Equatable, Identifiable {
    public var line: Int
    public var enabled = true
    public var condition = ""
    public var logMessage = ""
    public var id: Int { line }
    public init(line: Int) { self.line = line }
    public var dap: JSONValue {
        var value: [String: JSONValue] = ["line": .number(Double(line))]
        if !condition.isEmpty { value["condition"] = .string(condition) }
        if !logMessage.isEmpty { value["logMessage"] = .string(logMessage) }
        return .object(value)
    }
}

/// Only UI state, never a second source-text owner. A new session or stop epoch
/// invalidates every stale frame/variable/evaluation result.
public struct FlutterDebugState {
    public enum Phase: String, Sendable { case idle, starting, running, paused, stopping, ended }
    public private(set) var phase = Phase.idle
    public private(set) var epoch: UInt64 = 0
    public private(set) var threadID: Int?
    public private(set) var vmServiceURI = ""
    public private(set) var exitCode: Int?
    public init() {}
    public mutating func start() {
        let next = epoch &+ 1
        self = Self()
        phase = .starting
        epoch = next
    }
    public mutating func stopping() {
        phase = .stopping
        epoch &+= 1
        threadID = nil
        vmServiceURI = ""
    }
    public mutating func receive(_ event: JSONValue) {
        let body = event["body"]
        switch event["event"].string {
        case "stopped":
            guard phase == .starting || phase == .running || phase == .paused else { return }
            phase = .paused
            threadID = body["threadId"].int
            epoch &+= 1
        case "continued", "flutter.appStarted":
            guard phase != .stopping && phase != .ended else { return }
            phase = .running
            threadID = nil
            epoch &+= 1
        case "dart.debuggerUris":
            guard phase != .stopping && phase != .ended,
                let value = body["vmServiceUri"].string, value.count <= 4_096,
                let uri = URL(string: value), ["ws", "wss", "http", "https"].contains(uri.scheme ?? "")
            else { return }
            vmServiceURI = value
        case "exited": exitCode = body["exitCode"].int
        case "terminated", "hycode/disconnected":
            phase = .ended
            threadID = nil
            vmServiceURI = ""
            epoch &+= 1
        default: break
        }
    }
}
