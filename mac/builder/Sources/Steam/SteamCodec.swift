import CommonCrypto
import Compression
import CryptoKit
import Foundation

/// Steam's encryption, checksums and packing: the parts of SteamKit2's CryptoHelper,
/// DepotChunk, VZipUtil, VZstdUtil and ZipUtil the download needs.
enum SteamCodec {
    enum Failure: Error, CustomStringConvertible {
        case decrypt, decompress(String), checksum, zip(String)
        var description: String {
            switch self {
            case .decrypt: return "a file from Steam could not be decrypted"
            case .decompress(let s): return "a file from Steam could not be unpacked (\(s))"
            case .checksum: return "a piece of a file from Steam did not match its checksum"
            case .zip(let s): return "Steam sent a damaged archive (\(s))"
            }
        }
    }

    // MARK: AES (SteamKit2 SymmetricDecrypt: the first 16 bytes are the IV, AES-ECB encrypted;
    // the rest is AES-CBC with PKCS#7 padding)

    static func symmetricDecrypt(_ data: Data, key: Data) throws -> Data {
        guard data.count > 16, key.count == 32 else { throw Failure.decrypt }
        let iv = try aes(data.prefix(16), key: key, options: CCOptions(kCCOptionECBMode), iv: nil)
        return try aes(data.dropFirst(16), key: key, options: CCOptions(kCCOptionPKCS7Padding), iv: iv)
    }

    private static func aes(_ input: Data, key: Data, options: CCOptions, iv: Data?) throws -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                key.withUnsafeBytes { k in
                    (iv ?? Data()).withUnsafeBytes { v in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                                k.baseAddress, key.count, iv == nil ? nil : v.baseAddress,
                                i.baseAddress, input.count, o.baseAddress, o.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.decrypt }
        out.count = written
        return out
    }

    // MARK: checksums

    static func sha1(_ data: Data) -> Data { Data(Insecure.SHA1.hash(data: data)) }

    static func sha1(file url: URL) throws -> Data {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = Insecure.SHA1()
        while let block = try h.read(upToCount: 4 << 20), !block.isEmpty { hasher.update(data: block) }
        return Data(hasher.finalize())
    }

    /// Adler-32 from a seed of 0 (not 1), as Steam's chunk checksums are.
    static func adler(_ data: Data) -> UInt32 {
        var a: UInt32 = 0, b: UInt32 = 0
        data.withUnsafeBytes { raw in
            var p = raw.bindMemory(to: UInt8.self)[...]
            while !p.isEmpty {
                let n = min(p.count, 5552)
                for x in p.prefix(n) { a &+= UInt32(x); b &+= a }
                a %= 65521; b %= 65521
                p = p.dropFirst(n)
            }
        }
        return b << 16 | a
    }

    // MARK: depot chunks

    /// A chunk as downloaded: decrypted, unpacked, checked. `size` and `adler` are from the
    /// manifest.
    static func chunk(_ data: Data, key: Data, size: Int, adler expected: UInt32) throws -> Data {
        let plain = try symmetricDecrypt(data, key: key)
        let out: Data
        if plain.starts(with: [0x56, 0x53, 0x5A, 0x61]) {          // "VSZa": zstd
            // magic, crc32 | zstd frame | crc32, size, 3 unknown bytes, "zsv"
            guard plain.count > 8 + 15 else { throw Failure.decompress("short zstd") }
            out = try decode(plain.subdata(in: 8..<(plain.count - 15)), size: size) { s, sl, d, dl in
                ff7_zstd_decode(s, sl, d, dl)
            }
        } else if plain.starts(with: [0x56, 0x5A, 0x61]) {          // "VZa": LZMA
            // magic, crc32/time, 5 bytes of LZMA properties | stream | crc32, size, "zv"
            guard plain.count > 7 + 5 + 10 else { throw Failure.decompress("short LZMA") }
            let props = plain.subdata(in: 7..<12)
            out = try decode(plain.subdata(in: 12..<(plain.count - 10)), size: size) { s, sl, d, dl in
                props.withUnsafeBytes { ff7_lzma_decode($0.bindMemory(to: UInt8.self).baseAddress, s, sl, d, dl) }
            }
        } else if plain.starts(with: [0x50, 0x4B, 0x03, 0x04]) {    // zip with one file
            out = try unzipSingle(plain)
        } else {
            throw Failure.decompress("unknown packing \(plain.prefix(4).map { String(format: "%02X", $0) }.joined())")
        }
        guard out.count == size, adler(out) == expected else { throw Failure.checksum }
        return out
    }

    private static func decode(_ src: Data, size: Int,
                               _ f: (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<UInt8>, Int) -> Int) throws -> Data {
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { d in
            src.withUnsafeBytes { s in
                f(s.bindMemory(to: UInt8.self).baseAddress!, src.count, d.bindMemory(to: UInt8.self).baseAddress!, size)
            }
        }
        guard n == size else { throw Failure.decompress("got \(n) of \(size) bytes") }
        return out
    }

    // MARK: zip and gzip (deflate through the Compression framework)

    /// The single file in a zip (a depot manifest, a zipped chunk): stored or deflated.
    static func unzipSingle(_ zip: Data) throws -> Data {
        let b = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        // the end of central directory record, then the first entry's sizes and local header
        var eocd = b.count - 22
        while eocd >= 0, !(b[eocd] == 0x50 && b[eocd + 1] == 0x4B && b[eocd + 2] == 5 && b[eocd + 3] == 6) { eocd -= 1 }
        guard eocd >= 0 else { throw Failure.zip("no directory") }
        let cd = u32(eocd + 16)
        guard cd + 46 <= b.count, u32(cd) == 0x02014B50 else { throw Failure.zip("bad directory") }
        let method = u16(cd + 10), packed = u32(cd + 20), size = u32(cd + 24), local = u32(cd + 42)
        guard local + 30 <= b.count, u32(local) == 0x04034B50 else { throw Failure.zip("bad entry") }
        let start = local + 30 + u16(local + 26) + u16(local + 28)
        guard start + packed <= b.count else { throw Failure.zip("short entry") }
        let body = zip.subdata(in: start..<(start + packed))
        switch method {
        case 0: return body
        case 8: return try inflate(body, size: size)
        default: throw Failure.zip("packing method \(method)")
        }
    }

    /// A gzip stream (Steam's bundled messages).
    static func gunzip(_ gz: Data, size: Int) throws -> Data {
        let b = [UInt8](gz)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw Failure.zip("not gzip") }
        let flags = b[3]
        var o = 10
        if flags & 4 != 0 { o += 2 + (Int(b[o]) | Int(b[o + 1]) << 8) }
        if flags & 8 != 0 { while o < b.count, b[o] != 0 { o += 1 }; o += 1 }
        if flags & 16 != 0 { while o < b.count, b[o] != 0 { o += 1 }; o += 1 }
        if flags & 2 != 0 { o += 2 }
        guard o < b.count - 8 else { throw Failure.zip("short gzip") }
        return try inflate(gz.subdata(in: o..<(b.count - 8)), size: size)
    }

    /// Raw deflate (COMPRESSION_ZLIB is raw DEFLATE, no zlib header).
    static func inflate(_ src: Data, size: Int) throws -> Data {
        var out = Data(count: max(size, 1))
        let n = out.withUnsafeMutableBytes { d in
            src.withUnsafeBytes { s in
                compression_decode_buffer(d.bindMemory(to: UInt8.self).baseAddress!, size,
                                          s.bindMemory(to: UInt8.self).baseAddress!, src.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard n == size else { throw Failure.zip("inflated \(n) of \(size) bytes") }
        out.count = n
        return out
    }
}
