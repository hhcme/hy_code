import Foundation
import HyCodeWorkspace
import Observation

@MainActor @Observable final class WorkspaceProblemsController {
    private(set) var snapshot = WorkspaceProblemSnapshot.empty
    private(set) var limited = false
    var category: ProblemCategory? { didSet { schedule() } }
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var inputs: [String: [String: [LSPDiagnostic]]] = [:]
    @ObservationIgnored private var limits: [String: Bool] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var revision: UInt64 = 0
    func configure(root: URL?) {
        worker?.cancel()
        worker = nil
        generation = UUID()
        revision &+= 1
        self.root = root
        inputs.removeAll()
        limits.removeAll()
        snapshot = .empty
        limited = false
        category = nil
    }
    func update(_ language: String, values: [String: [LSPDiagnostic]], limited: Bool) {
        inputs[language] = values
        limits[language] = limited
        schedule()
    }
    private func schedule() {
        revision &+= 1
        guard worker == nil, let root else { return }
        let context = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == context { self.worker = nil } }
            do {
                while true {
                    try await Task.sleep(for: .milliseconds(100))
                    guard self.generation == context else { return }
                    let revision = self.revision
                    let inputs = self.inputs
                    let category = self.category
                    let task = Task.detached(priority: .utility) {
                        try WorkspaceProblemSnapshot.make(inputs, root: root, category: category)
                    }
                    let result = try await withTaskCancellationHandler {
                        try await task.value
                    } onCancel: {
                        task.cancel()
                    }
                    guard self.generation == context else { return }
                    if self.revision != revision { continue }
                    self.snapshot = result
                    self.limited = result.limited || self.limits.values.contains(true)
                    return
                }
            } catch {}
        }
    }
}
