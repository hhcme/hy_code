import Darwin
import Dispatch
import Foundation

/// Pipes and waitid can wait indefinitely. They must not occupy Swift's bounded
/// cooperative executor, especially when several language servers are active.
enum ToolBlockingIO {
    static func read(_ handle: FileHandle, capacity: Int) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var bytes = [UInt8](repeating: 0, count: capacity)
                var count: Int
                repeat {
                    count = bytes.withUnsafeMutableBytes {
                        Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
                    }
                } while count < 0 && errno == EINTR
                continuation.resume(returning: count > 0 ? Data(bytes.prefix(count)) : Data())
            }
        }
    }
    static func wait(_ child: OwnedToolProcess) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: child.wait()) }
        }
    }
}
