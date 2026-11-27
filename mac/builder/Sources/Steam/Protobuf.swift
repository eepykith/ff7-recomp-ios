import Foundation

/// Just enough protobuf for Steam's messages: fields are written and read by number (the
/// numbers come from SteamDatabase/Protobufs, the definitions SteamKit2 and JavaSteam use).
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ v: UInt64) {
        var v = v
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wire: Int) { varint(UInt64(field << 3 | wire)) }

    mutating func uint(_ field: Int, _ v: UInt64) { tag(field, 0); varint(v) }
    mutating func uint(_ field: Int, _ v: UInt32) { uint(field, UInt64(v)) }
    mutating func int32(_ field: Int, _ v: Int32) { uint(field, UInt64(bitPattern: Int64(v))) }
    mutating func bool(_ field: Int, _ v: Bool) { uint(field, UInt64(v ? 1 : 0)) }

    mutating func fixed64(_ field: Int, _ v: UInt64) {
        tag(field, 1)
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func fixed32(_ field: Int, _ v: UInt32) {
        tag(field, 5)
        withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func bytes(_ field: Int, _ v: Data) {
        tag(field, 2)
        varint(UInt64(v.count))
        data.append(v)
    }

    mutating func string(_ field: Int, _ v: String) { bytes(field, Data(v.utf8)) }
    mutating func message(_ field: Int, _ m: ProtoWriter) { bytes(field, m.data) }
}

enum ProtoError: Error, CustomStringConvertible {
    case truncated, badWireType(Int)
    var description: String {
        switch self {
        case .truncated: return "a Steam message ended early"
        case .badWireType(let w): return "a Steam message had an unknown field type (\(w))"
        }
    }
}

/// A decoded message: each field number's values, in order (repeated fields have several).
struct ProtoMessage {
    enum Value {
        case varint(UInt64), fixed64(UInt64), fixed32(UInt32), bytes(Data)
    }

    private(set) var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        let b = [UInt8](data)
        var i = 0
        func varint() throws -> UInt64 {
            var v: UInt64 = 0, shift: UInt64 = 0
            while true {
                guard i < b.count else { throw ProtoError.truncated }
                let byte = b[i]; i += 1
                v |= UInt64(byte & 0x7F) << shift
                if byte < 0x80 { return v }
                shift += 7
                if shift > 63 { throw ProtoError.truncated }
            }
        }
        func le(_ n: Int) throws -> UInt64 {
            guard i + n <= b.count else { throw ProtoError.truncated }
            var v: UInt64 = 0
            for k in 0..<n { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }
        while i < b.count {
            let key = try varint()
            let field = Int(key >> 3), wire = Int(key & 7)
            let value: Value
            switch wire {
            case 0: value = .varint(try varint())
            case 1: value = .fixed64(try le(8))
            case 5: value = .fixed32(UInt32(try le(4)))
            case 2:
                let n = Int(try varint())
                guard n >= 0, i + n <= b.count else { throw ProtoError.truncated }
                value = .bytes(Data(b[i..<(i + n)]))
                i += n
            default: throw ProtoError.badWireType(wire)
            }
            fields[field, default: []].append(value)
        }
    }

    func uint(_ f: Int) -> UInt64? {
        switch fields[f]?.last {
        case .varint(let v)?, .fixed64(let v)?: return v
        case .fixed32(let v)?: return UInt64(v)
        default: return nil
        }
    }

    func int32(_ f: Int) -> Int32? { uint(f).map { Int32(truncatingIfNeeded: Int64(bitPattern: $0)) } }
    func bool(_ f: Int) -> Bool { (uint(f) ?? 0) != 0 }

    func float(_ f: Int) -> Float? {
        if case .fixed32(let v)? = fields[f]?.last { return Float(bitPattern: v) }
        return nil
    }

    func data(_ f: Int) -> Data? {
        if case .bytes(let d)? = fields[f]?.last { return d }
        return nil
    }

    func string(_ f: Int) -> String? { data(f).map { String(decoding: $0, as: UTF8.self) } }
    func message(_ f: Int) -> ProtoMessage? { data(f).flatMap { try? ProtoMessage($0) } }

    func messages(_ f: Int) -> [ProtoMessage] {
        (fields[f] ?? []).compactMap {
            if case .bytes(let d) = $0 { return try? ProtoMessage(d) }
            return nil
        }
    }

    /// A repeated integer field, packed or not.
    func uints(_ f: Int) -> [UInt64] {
        var out: [UInt64] = []
        for v in fields[f] ?? [] {
            switch v {
            case .varint(let x), .fixed64(let x): out.append(x)
            case .fixed32(let x): out.append(UInt64(x))
            case .bytes(let d):           // a packed run of varints
                let b = [UInt8](d)
                var j = 0
                while j < b.count {
                    var v: UInt64 = 0, s: UInt64 = 0
                    while j < b.count {
                        let byte = b[j]; j += 1
                        v |= UInt64(byte & 0x7F) << s
                        if byte < 0x80 { break }
                        s += 7
                    }
                    out.append(v)
                }
            }
        }
        return out
    }
}
