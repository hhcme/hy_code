import Darwin
import Dispatch
import Foundation

/// Only the calling process. Never enumerates processes, launches a tool, or
/// includes child services. Counters are read by the sampler's background actor.
struct ProcessResourceCounters: Sendable {
    var uptimeNanoseconds: UInt64
    var cpuSeconds: Double
    var footprintBytes: UInt64
    var residentBytes: UInt64
    var peakFootprintBytes: UInt64

    static func readSelf() throws -> Self {
        var memory = rusage_info_v4()
        // libproc declares a pointer-to-void-pointer, but writes a complete V4
        // struct at this address. Storage is sized/aligned for that exact flavor;
        // the temporary rebound pointer does not escape the synchronous call.
        let result = withUnsafeMutablePointer(to: &memory) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var cpu = rusage()
        guard getrusage(RUSAGE_SELF, &cpu) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // getrusage timeval is seconds + microseconds. Do not treat libproc's
        // CPU Mach ticks as nanoseconds on Apple Silicon.
        let seconds =
            Double(cpu.ru_utime.tv_sec) + Double(cpu.ru_stime.tv_sec)
            + (Double(cpu.ru_utime.tv_usec) + Double(cpu.ru_stime.tv_usec)) / 1_000_000
        return Self(
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds, cpuSeconds: seconds,
            footprintBytes: memory.ri_phys_footprint, residentBytes: memory.ri_resident_size,
            peakFootprintBytes: memory.ri_lifetime_max_phys_footprint)
    }
}

public struct ProcessResourceSample: Sendable, Equatable {
    public let footprintBytes: UInt64
    public let residentBytes: UInt64
    public let peakFootprintBytes: UInt64
    /// One fully used core is 100%. Multi-threaded work can exceed 100%.
    /// First sample, resumed sampling, and invalid counter deltas have no rate.
    public let cpuPercent: Double?
}

struct ProcessResourceAccumulator {
    private var previous: ProcessResourceCounters?
    mutating func resetInterval() { previous = nil }
    mutating func accept(_ value: ProcessResourceCounters) -> ProcessResourceSample {
        defer { previous = value }
        var percent: Double?
        if let previous, value.uptimeNanoseconds > previous.uptimeNanoseconds,
            value.cpuSeconds.isFinite, previous.cpuSeconds.isFinite,
            value.cpuSeconds >= previous.cpuSeconds
        {
            let elapsed = Double(value.uptimeNanoseconds - previous.uptimeNanoseconds) / 1_000_000_000
            let rate = (value.cpuSeconds - previous.cpuSeconds) / elapsed * 100
            if rate.isFinite { percent = rate }
        }
        return ProcessResourceSample(
            footprintBytes: value.footprintBytes, residentBytes: value.residentBytes,
            peakFootprintBytes: max(value.peakFootprintBytes, value.footprintBytes), cpuPercent: percent)
    }
}

/// Constant-sized state; the UI owns a cancellable 2-second polling loop. No
/// timer, retained history, process handle, or main-thread OS query lives here.
public actor ProcessResourceSampler {
    private var accumulator = ProcessResourceAccumulator()
    public init() {}
    public func resetInterval() { accumulator.resetInterval() }
    public func sample() throws -> ProcessResourceSample {
        do { return accumulator.accept(try .readSelf()) } catch {
            accumulator.resetInterval()
            throw error
        }
    }
}
