import Foundation
import Testing

@testable import HyCodeWorkspace

struct ProcessResourceTests {
    private func counters(_ seconds: UInt64, cpu: Double, footprint: UInt64 = 128) -> ProcessResourceCounters {
        ProcessResourceCounters(
            uptimeNanoseconds: seconds * 1_000_000_000, cpuSeconds: cpu,
            footprintBytes: footprint, residentBytes: 64, peakFootprintBytes: 256)
    }
    @Test func ratesUseElapsedTimeAllowMultipleCoresAndStartUnavailable() {
        var model = ProcessResourceAccumulator()
        #expect(model.accept(counters(10, cpu: 1)).cpuPercent == nil)
        #expect(model.accept(counters(12, cpu: 2)).cpuPercent == 50)
        #expect(model.accept(counters(14, cpu: 6)).cpuPercent == 200)
        #expect(model.accept(counters(16, cpu: 6)).cpuPercent == 0)
        // Sampling may be delayed by a busy queue; use real elapsed time.
        #expect(model.accept(counters(26, cpu: 7)).cpuPercent == 10)
        model.resetInterval()
        #expect(model.accept(counters(200, cpu: 15)).cpuPercent == nil)
    }
    @Test func invalidIntervalsAndCounterResetsNeverProduceInventedZero() {
        var model = ProcessResourceAccumulator()
        _ = model.accept(counters(10, cpu: 5))
        #expect(model.accept(counters(10, cpu: 6)).cpuPercent == nil)
        #expect(model.accept(counters(9, cpu: 7)).cpuPercent == nil)
        #expect(model.accept(counters(12, cpu: 1)).cpuPercent == nil)
        #expect(model.accept(counters(14, cpu: .nan)).cpuPercent == nil)
        #expect(model.accept(counters(16, cpu: 2)).cpuPercent == nil)
        #expect(model.accept(counters(18, cpu: .infinity)).cpuPercent == nil)
        let value = model.accept(counters(20, cpu: 3, footprint: UInt64.max))
        #expect(value.footprintBytes == UInt64.max && value.peakFootprintBytes == UInt64.max)
    }
    @Test func readsOnlyTheHeadlessTestProcessWithNoApplicationHost() async throws {
        let sampler = ProcessResourceSampler()
        let initial = try await sampler.sample()
        #expect(initial.footprintBytes > 0 && initial.residentBytes > 0)
        #expect(initial.peakFootprintBytes >= initial.footprintBytes)
        #expect(initial.cpuPercent == nil)
        await sampler.resetInterval()
        #expect(try await sampler.sample().cpuPercent == nil)
    }
}
