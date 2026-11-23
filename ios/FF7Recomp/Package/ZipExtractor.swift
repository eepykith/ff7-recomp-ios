import Compression
import Foundation

/// Minimal ZIP reader for `.ff7pkg` files (Python `zipfile` output: stored or deflated
/// entries, no ZIP64, no encryption). iOS has no public unzip API; integrity is checked
/// afterwards against the manifest's SHA-256s, so CRCs are not verified here.
enum ZipExtractor {
    enum Failure: Error, LocalizedError, Equatable {
        case notZip
        case truncated
        case unsupported(String)
        case unsafePath(String)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notZip: return "The file is not a GamePackage archive (.ff7pkg / zip)."
            case .truncated: return "The package archive is truncated."
            case .unsupported(let why): return "Unsupported package archive: \(why)."
            case .unsafePath(let p): return "The package contains an unsafe path: \(p)"
            case .corrupt(let name): return "Could not unpack \(name) from the package."
            }
        }
    }

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    /// Lists the archive's entries (central directory order).
    static func entries(of data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw Failure.notZip }
        // End of central directory: scan back over a possible comment (max 64 KiB). Only the
        // tail and the central directory are copied out; entry payloads stay mapped.
        let tail = [UInt8](data.suffix(22 + 0xFFFF))
        var eocd = -1
        var i = tail.count - 22
        while i >= 0 {
            if u32(tail, i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = Int(u16(tail, eocd + 10))
        let cdSize = Int(u32(tail, eocd + 12))
        let cdOffset = Int(u32(tail, eocd + 16))
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF { throw Failure.unsupported("ZIP64") }
        guard cdOffset + cdSize <= data.count else { throw Failure.truncated }
        let bytes = [UInt8](data[(data.startIndex + cdOffset)..<(data.startIndex + cdOffset + cdSize)])

        var result: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x0201_4B50 else { throw Failure.truncated }
            let flags = u16(bytes, p + 8)
            let method = u16(bytes, p + 10)
            let csize = Int(u32(bytes, p + 20))
            let usize = Int(u32(bytes, p + 24))
            let nameLen = Int(u16(bytes, p + 28))
            let extraLen = Int(u16(bytes, p + 30))
            let commentLen = Int(u16(bytes, p + 32))
            let local = Int(u32(bytes, p + 42))
            guard p + 46 + nameLen <= bytes.count else { throw Failure.truncated }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            if flags & 0x1 != 0 { throw Failure.unsupported("encrypted entry \(name)") }
            result.append(Entry(name: name, method: method, compressedSize: csize,
                                uncompressedSize: usize, localHeaderOffset: local))
            p += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    /// Extracts every entry under `destination` (created if needed). Returns the relative
    /// paths of the files written.
    @discardableResult
    static func extract(archive url: URL, to destination: URL) throws -> [String] {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let list = try entries(of: data)
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var written: [String] = []
        for entry in list {
            let trimmed = entry.isDirectory ? String(entry.name.dropLast()) : entry.name
            if trimmed.isEmpty { continue }
            guard GameManifestParser.isSafeRelativePath(trimmed) else { throw Failure.unsafePath(entry.name) }
            let target = destination.appendingPathComponent(trimmed, isDirectory: entry.isDirectory)
            if entry.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents(of: entry, in: data).write(to: target, options: .atomic)
            written.append(trimmed)
        }
        return written
    }

    static func contents(of entry: Entry, in data: Data) throws -> Data {
        let base = data.startIndex
        let lh = entry.localHeaderOffset
        guard lh + 30 <= data.count else { throw Failure.truncated }
        let header = [UInt8](data[(base + lh)..<(base + lh + 30)])
        guard u32(header, 0) == 0x0403_4B50 else { throw Failure.corrupt(entry.name) }
        let start = lh + 30 + Int(u16(header, 26)) + Int(u16(header, 28))
        guard start + entry.compressedSize <= data.count else { throw Failure.truncated }
        let payload = data[(base + start)..<(base + start + entry.compressedSize)]

        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            if entry.uncompressedSize == 0 { return Data() }
            var out = Data(count: entry.uncompressedSize)
            let produced = out.withUnsafeMutableBytes { dst -> Int in
                payload.withUnsafeBytes { src -> Int in
                    // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what ZIP stores.
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, entry.uncompressedSize,
                        src.bindMemory(to: UInt8.self).baseAddress!, entry.compressedSize,
                        nil, COMPRESSION_ZLIB)
                }
            }
            guard produced == entry.uncompressedSize else { throw Failure.corrupt(entry.name) }
            return out
        default:
            throw Failure.unsupported("compression method \(entry.method) for \(entry.name)")
        }
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
