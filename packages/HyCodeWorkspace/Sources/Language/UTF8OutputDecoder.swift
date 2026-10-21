import Foundation

/// Retains only a split UTF-8 scalar (at most three bytes), not the full log.
struct UTF8OutputDecoder {
    private var pending = Data()
    mutating func append(_ chunk: Data) -> String {
        pending.append(chunk)
        guard !pending.isEmpty else { return "" }
        var lead = pending.count - 1
        while lead > 0 && pending[lead] & 0xc0 == 0x80 && pending.count - lead < 4 { lead -= 1 }
        let byte = pending[lead]
        let expected = byte & 0xe0 == 0xc0 ? 2 : byte & 0xf0 == 0xe0 ? 3 : byte & 0xf8 == 0xf0 ? 4 : 1
        let end = pending.count - lead < expected ? lead : pending.count
        let text = String(decoding: pending.prefix(end), as: UTF8.self)
        pending = Data(pending.dropFirst(end))
        return text
    }
    mutating func finish() -> String {
        defer { pending = Data() }
        return String(decoding: pending, as: UTF8.self)
    }
}
