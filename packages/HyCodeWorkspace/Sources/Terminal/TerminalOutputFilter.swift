import Foundation

/// A bounded streaming gate in front of the third-party VT parser. Graphic
/// DCS/APC payloads are not part of the editor terminal's contract. Retain at
/// most 8 KiB of an OSC or 256 bytes of a CSI; incomplete strings cannot grow
/// an emulator allocation. UTF-8 continuation bytes are never mistaken for C1.
public struct TerminalOutputFilter: Sendable {
    private enum Mode: Sendable {
        case ground, escape, escapeIntermediate, csi, osc, discardString, discardCSI, discardEscape
    }
    private var mode = Mode.ground
    private var pending: [UInt8] = []
    private var stringEscape = false
    private var oscString = false
    private var utf8Remaining = 0
    private var unicodeBytes: [UInt8] = []
    private var currentCluster = ""
    public private(set) var oversizedSequences = 0
    public private(set) var unicodeReplacements = 0
    public init() {}

    public mutating func append(_ data: Data) -> Data {
        var output = Data()
        output.reserveCapacity(data.count + pending.count)
        for byte in data {
            let continuation = utf8Remaining > 0 && (0x80...0xbf).contains(byte)
            if continuation {
                utf8Remaining -= 1
            } else {
                utf8Remaining =
                    (0xc2...0xdf).contains(byte)
                    ? 1 : (0xe0...0xef).contains(byte) ? 2 : (0xf0...0xf4).contains(byte) ? 3 : 0
            }
            if mode == .ground, !continuation, !unicodeBytes.isEmpty {
                output.append(contentsOf: [0xef, 0xbf, 0xbd])
                unicodeBytes.removeAll(keepingCapacity: true)
            }
            if !continuation, byte == 0x18 || byte == 0x1a {
                mode = .ground
                pending.removeAll(keepingCapacity: true)
                stringEscape = false
                continue
            }
            switch mode {
            case .ground:
                if byte == 0x1b {
                    mode = .escape
                    pending = [0x1b]
                } else if !continuation, byte == 0x9b {
                    beginCSI()
                } else if !continuation, byte == 0x9d {
                    beginOSC()
                } else if !continuation, [0x90, 0x98, 0x9e, 0x9f].contains(byte) {
                    beginDiscard(osc: false)
                } else {
                    appendGround(byte, continuation: continuation, output: &output)
                }
            case .escape:
                switch byte {
                case 0x5b, 0x9b: beginCSI()
                case 0x5d, 0x9d: beginOSC()
                case 0x50, 0x58, 0x5e, 0x5f, 0x90, 0x98, 0x9e, 0x9f: beginDiscard(osc: false)
                case 0x1b: pending = [0x1b]
                case 0x20...0x2f:
                    pending.append(byte)
                    mode = .escapeIntermediate
                case 0x30...0x7e:
                    output.append(contentsOf: [0x1b, byte])
                    pending.removeAll(keepingCapacity: true)
                    mode = .ground
                default: break
                }
            case .escapeIntermediate:
                if byte == 0x1b {
                    mode = .escape
                    pending = [0x1b]
                } else if (0x20...0x2f).contains(byte) {
                    pending.append(byte)
                    if pending.count > 16 {
                        oversizedSequences += 1
                        pending.removeAll(keepingCapacity: true)
                        mode = .discardEscape
                    }
                } else if (0x30...0x7e).contains(byte) {
                    pending.append(byte)
                    output.append(contentsOf: pending)
                    pending.removeAll(keepingCapacity: true)
                    mode = .ground
                }
            case .csi:
                if byte == 0x1b {
                    pending = [0x1b]
                    mode = .escape
                    continue
                }
                pending.append(byte)
                if pending.count > 256 {
                    oversizedSequences += 1
                    pending.removeAll(keepingCapacity: true)
                    mode = (0x40...0x7e).contains(byte) ? .ground : .discardCSI
                } else if (0x40...0x7e).contains(byte) {
                    if safeCSI() { output.append(contentsOf: pending) }
                    pending.removeAll(keepingCapacity: true)
                    mode = .ground
                }
            case .osc, .discardString:
                let terminated =
                    (!continuation && byte == 0x9c) || (oscString && byte == 7) || (stringEscape && byte == 0x5c)
                if mode == .osc, !terminated,
                    stringEscape || (!continuation && (0x80...0x9f).contains(byte)) || (byte < 0x20 && byte != 0x1b)
                {
                    // Do not forward an OSC containing an embedded escape/C1
                    // introducer which the emulator could reinterpret as DCS.
                    mode = .discardString
                    pending.removeAll(keepingCapacity: true)
                }
                if mode == .osc { pending.append(byte) }
                if terminated {
                    if mode == .osc, safeOSC() { output.append(contentsOf: pending) }
                    pending.removeAll(keepingCapacity: true)
                    mode = .ground
                    stringEscape = false
                } else if pending.count > 8192 {
                    oversizedSequences += 1
                    pending.removeAll(keepingCapacity: true)
                    mode = .discardString
                    stringEscape = byte == 0x1b
                } else {
                    stringEscape = byte == 0x1b
                }
            case .discardCSI:
                if byte == 0x1b {
                    mode = .escape
                    pending = [0x1b]
                } else if (0x40...0x7e).contains(byte) {
                    mode = .ground
                }
            case .discardEscape:
                if byte == 0x1b {
                    mode = .escape
                    pending = [0x1b]
                } else if (0x30...0x7e).contains(byte) {
                    mode = .ground
                }
            }
        }
        return output
    }
    private mutating func beginCSI() {
        mode = .csi
        pending = [0x1b, 0x5b]
    }
    private mutating func beginOSC() {
        mode = .osc
        pending = [0x1b, 0x5d]
        stringEscape = false
        oscString = true
    }
    private mutating func beginDiscard(osc: Bool) {
        mode = .discardString
        pending.removeAll(keepingCapacity: true)
        oscString = osc
        stringEscape = false
    }
    private mutating func appendGround(_ byte: UInt8, continuation: Bool, output: inout Data) {
        if continuation || utf8Remaining > 0 {
            unicodeBytes.append(byte)
            guard utf8Remaining == 0 else { return }
            let text = String(decoding: unicodeBytes, as: UTF8.self)
            if let scalar = text.unicodeScalars.first {
                let character = String(scalar)
                let candidate = currentCluster + character
                if candidate.count == 1, candidate.unicodeScalars.count > 32 {
                    output.append(contentsOf: [0xef, 0xbf, 0xbd])
                    unicodeReplacements += 1
                    currentCluster = "�"
                } else {
                    currentCluster = candidate.count == 1 ? candidate : character
                    output.append(contentsOf: unicodeBytes)
                }
            }
            unicodeBytes.removeAll(keepingCapacity: true)
        } else {
            output.append(byte)
            if (0x20...0x7e).contains(byte) {
                currentCluster = String(UnicodeScalar(byte))
            }
        }
    }
    private func safeOSC() -> Bool {
        // Basic metadata plus bounded HyCode shell reports. The application
        // validates the per-session token before consuming code 7777.
        let digits = pending.dropFirst(2).prefix { (0x30...0x39).contains($0) }
        guard !digits.isEmpty, digits.count <= 4, let code = Int(String(decoding: digits, as: UTF8.self)) else {
            return false
        }
        return [0, 1, 2, 7, 8, 10, 11, 12, 104, 110, 111, 112, 7777].contains(code)
    }
    private func safeCSI() -> Bool {
        var digits = 0
        var value = 0
        var maximum = 0
        for byte in pending.dropFirst(2).dropLast() {
            guard (0x20...0x3f).contains(byte) else { return false }
            if (0x30...0x39).contains(byte) {
                digits += 1
                guard digits <= 6 else { return false }
                value = value * 10 + Int(byte - 0x30)
                maximum = max(maximum, value)
            } else {
                digits = 0
                value = 0
            }
        }
        // Counted screen operations must not expand one short chunk into huge work.
        if let last = pending.last, [0x40, 0x4c, 0x4d, 0x50, 0x53, 0x54, 0x58, 0x62].contains(last) {
            return maximum <= 500
        }
        return true
    }
}
