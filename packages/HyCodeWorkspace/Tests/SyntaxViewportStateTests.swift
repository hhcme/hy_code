import Foundation
import Testing

@testable import HyCodeWorkspace

struct SyntaxViewportStateTests {
    @Test func continuousScrollEventsJoinOneWorkerWithoutInvalidatingItsResult() throws {
        var state = SyntaxViewportState()
        let ticket = try #require({ state.beginUpdates() }())
        for _ in 0..<240 {
            #expect({ state.beginUpdates() == nil }())
            #expect(state.accepts(ticket))
        }
        _ = state.record(NSRange(location: 0, length: 4_096))
        #expect({ state.covers(NSRange(location: 1_024, length: 512)) }())
        state.finish(ticket)
        #expect({ state.beginUpdates() != nil }())
    }

    @Test func readAheadAvoidsARequestForEverySmallScrollAndKeepsEarlierColors() throws {
        let source = String(repeating: "a", count: 20_000) as NSString
        var state = SyntaxViewportState()
        var requests = 0
        for location in stride(from: 0, through: 7_000, by: 70) {
            let visible = NSRange(location: location, length: 400)
            if !state.covers(visible) {
                requests += 1
                let range = try #require(SyntaxViewportState.requestRange(for: visible, source: source))
                #expect(state.record(range).isEmpty)
            }
            #expect({ state.covers(visible) }())
        }
        #expect(requests < 12)
        #expect({ state.covers(NSRange(location: 0, length: 400)) }())
    }

    @Test func boundedEvictionPreservesOverlappingFreshColorsAndTouchesRecentWindows() {
        var state = SyntaxViewportState()
        for index in 0..<8 { _ = state.record(NSRange(location: index * 200, length: 100)) }
        let removed = state.record(NSRange(location: 50, length: 100))
        #expect(removed == [NSRange(location: 0, length: 50)])
        #expect({ state.covers(NSRange(location: 50, length: 100)) }())
        #expect({ !state.covers(NSRange(location: 0, length: 50)) }())
        #expect({ state.covers(NSRange(location: 200, length: 100)) }())  // touch the next-oldest window
        let next = state.record(NSRange(location: 2_000, length: 100))
        #expect(next == [NSRange(location: 400, length: 100)])
        #expect({ state.covers(NSRange(location: 200, length: 100)) }())
    }

    @Test func adjacentCoverageIsReusableAndResetRejectsOldRevisionWorkers() throws {
        var state = SyntaxViewportState()
        let old = try #require({ state.beginUpdates() }())
        _ = state.record(NSRange(location: 0, length: 100))
        _ = state.record(NSRange(location: 100, length: 100))
        #expect({ state.covers(NSRange(location: 50, length: 100)) }())
        #expect({ state.reset().count == 2 }())
        #expect({ !state.covers(NSRange(location: 0, length: 100)) }())
        let new = try #require({ state.beginUpdates() }())
        #expect(!state.accepts(old))
        state.finish(old)
        #expect(state.accepts(new))
        state.cancel()
        #expect(!state.accepts(new))
    }

    @Test func failedOldViewportStillProcessesTheFinalScrollWithoutRetryingInPlace() throws {
        var state = SyntaxViewportState()
        let ticket = try #require({ state.beginUpdates() }())
        let failed = NSRange(location: 0, length: 400)
        let latest = NSRange(location: 20_000, length: 400)
        #expect({ state.beginUpdates() == nil }())
        #expect({ state.needsUpdate(after: failed, latest: latest) }())
        #expect({ !state.needsUpdate(after: failed, latest: failed) }())
        #expect(state.accepts(ticket))
        _ = state.record(latest)
        #expect({ !state.needsUpdate(after: failed, latest: latest) }())
    }

    @Test func prefetchPreservesVisibleUnicodeScalarsAndStaysWithinTheCoreBudget() throws {
        let source =
            (String(repeating: "a", count: 3_000) + "😀"
            + String(repeating: "a", count: 2_056) + "😀" + String(repeating: "a", count: 80_000)) as NSString
        let range = try #require(
            SyntaxViewportState.requestRange(for: NSRange(location: 4_025, length: 10), source: source))
        #expect(range == NSRange(location: 3_002, length: 2_056))
        let maximum = try #require(
            SyntaxViewportState.requestRange(for: NSRange(location: 6_000, length: 65_536), source: source))
        #expect(maximum.length == 65_536)
        for invalid in [
            NSRange(location: -1, length: 1), NSRange(location: 0, length: 0),
            NSRange(location: NSNotFound, length: 1), NSRange(location: 0, length: 65_537),
            NSRange(location: source.length, length: 1),
        ] {
            #expect(SyntaxViewportState.requestRange(for: invalid, source: source) == nil)
        }
    }
}
