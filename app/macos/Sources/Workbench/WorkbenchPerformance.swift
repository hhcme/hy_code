import os

/// Opt-in Instruments intervals only. No file names, paths, project data or eager
/// logging; disabled signposts add no allocation or string formatting per frame.
@MainActor
enum WorkbenchPerformance {
    private static let signposter = OSSignposter(subsystem: "io.github.hhcme.hycode", category: "Workbench")
    static func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard signposter.isEnabled else { return nil }
        return signposter.beginInterval(name, id: signposter.makeSignpostID())
    }
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        if let state { signposter.endInterval(name, state) }
    }
}
