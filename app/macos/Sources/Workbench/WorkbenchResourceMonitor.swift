import Foundation
import HyCodeWorkspace
import Observation

struct WorkbenchCacheCleanup {
    var documents = 0
    var grammars = 0
    var failures = 0
}

/// Only this small view's observation graph changes with a sample; the workbench
/// store, layout, editor and file tree do not subscribe to the polling counters.
@MainActor @Observable final class WorkbenchResourceMonitor {
    private(set) var sample: ProcessResourceSample?
    private(set) var error: String?
    private(set) var cleaning = false
    private(set) var cleanup: WorkbenchCacheCleanup?
    private(set) var beforeCleanup: UInt64?
    private(set) var afterCleanup: UInt64?
    @ObservationIgnored private let sampler = ProcessResourceSampler()
    @ObservationIgnored private var generation = UUID()

    func observe(active: Bool) async {
        let ticket = UUID()
        generation = ticket
        guard active else { return }
        await sampler.resetInterval()
        while !Task.isCancelled, generation == ticket {
            do {
                let value = try await sampler.sample()
                guard !Task.isCancelled, generation == ticket else { return }
                sample = value
                error = nil
            } catch {
                guard !Task.isCancelled, generation == ticket else { return }
                self.error = error.localizedDescription
                sample = nil
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    func cleanCaches(_ action: () async -> WorkbenchCacheCleanup) async {
        guard !cleaning else { return }
        cleaning = true
        defer { cleaning = false }
        cleanup = nil
        // Independent samples don't perturb the periodic CPU interval. Errors
        // stay unavailable, never an invented zero or a claimed amount freed.
        let measurement = ProcessResourceSampler()
        beforeCleanup = try? await measurement.sample().footprintBytes
        afterCleanup = nil
        cleanup = await action()
        afterCleanup = try? await measurement.sample().footprintBytes
    }
}
