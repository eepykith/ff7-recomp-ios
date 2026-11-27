import Foundation

/// FINAL FANTASY VII's files from Steam (the steps FF7Recomp for Android takes with JavaSteam):
/// the app's info (PICS), each depot's key and current manifest, the manifest from Steam's
/// content servers, then every file the Builder needs, chunk by chunk. Only
/// ff7/resources/ff7_1.02/ff7_en and ff7/workingdir/data are fetched, laid out as Steam installs
/// them, so the folder is one the Builder takes like any Steam install.
///
/// Files already there with Steam's size and SHA-1 are kept: a download stopped half way goes on
/// where it was, and running it again repairs damaged files.
final class SteamGameDownload: @unchecked Sendable {
    /// FINAL FANTASY VII as Steam sells it today (the re-release, which carries the 1.02 exe).
    static let appID: UInt32 = 3837340
    /// Development (Tools/ff7steam info): list what would be fetched, fetch nothing.
    nonisolated(unsafe) static var infoOnly = false

    struct Progress {
        var phase: String
        var done: Int64 = 0
        var total: Int64 = 0
        var files = 0
        var filesTotal = 0
    }

    enum Failure: Error, CustomStringConvertible {
        case notOwned, noDepots, noServers, noExe, http(Int, String), mismatch(String)
        var description: String {
            switch self {
            case .notOwned: return "this Steam account does not own FINAL FANTASY VII (the version on sale today)"
            case .noDepots: return "Steam listed no game files for FINAL FANTASY VII"
            case .noServers: return "no Steam download server answered"
            case .noExe: return "Steam's copy of the game has no ff7/resources/ff7_1.02/ff7_en"
            case .http(let code, let what): return "a Steam download server answered \(code) for \(what)"
            case .mismatch(let f): return "\(f) did not match Steam's checksum after downloading"
            }
        }
    }

    /// A depot file to fetch.
    struct Want {
        let depot: UInt32
        let path: String          // as in the depot, with forward slashes
        let size: Int64
        let sha: Data
        let chunks: [Chunk]
    }

    struct Chunk {
        let id: Data
        let offset: Int64
        let size: Int
        let packed: Int
        let adler: UInt32
    }

    struct Server {
        let host: String
        let https: Bool
    }

    let connection: SteamConnection
    let destination: URL
    private let urls: URLSession
    private var keys: [UInt32: Data] = [:]
    private var servers: [Server] = []
    private var nextServer = 0
    private let lock = NSLock()

    init(connection: SteamConnection, destination: URL) {
        self.connection = connection
        self.destination = destination
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpMaximumConnectionsPerHost = 8
        urls = URLSession(configuration: config)
    }

    /// Whether a depot path is one the Builder uses (ff7_en and the data folder).
    static func wanted(_ path: String) -> Bool {
        let l = path.lowercased()
        return l == "ff7/resources/ff7_1.02/ff7_en" || l.hasPrefix("ff7/workingdir/data/")
    }

    // MARK: running

    func run(progress: @escaping (Progress) -> Void) async throws {
        progress(Progress(phase: "Asking Steam for the game…"))
        let depots = try await depotsAndManifests()
        servers = try await contentServers()

        progress(Progress(phase: "Reading the list of game files…"))
        var wants: [Want] = []
        for (depot, manifest) in depots {
            guard let key = keys[depot] else { continue }
            let code = try await manifestRequestCode(depot: depot, manifest: manifest)
            let files = try await manifestFiles(depot: depot, manifest: manifest, code: code, key: key)
            wants += files.filter { Self.wanted($0.path) }
        }
        guard wants.contains(where: { $0.path.lowercased() == "ff7/resources/ff7_1.02/ff7_en" }) else { throw Failure.noExe }
        wants.sort { $0.path < $1.path }
        if Self.infoOnly {
            let size = wants.reduce(Int64(0)) { $0 + $1.size }
            let chunks = wants.reduce(0) { $0 + $1.chunks.count }
            progress(Progress(phase: "depots \(depots.map { "\($0.0)/\($0.1)" }) servers \(servers.count) (\(servers.first?.host ?? "-")): \(wants.count) files, \(chunks) chunks, \(size) bytes; first \(wants.first?.path ?? "-")"))
            return
        }

        var p = Progress(phase: "Checking files already here…")
        p.total = wants.reduce(0) { $0 + $1.size }
        p.filesTotal = wants.count
        progress(p)
        for w in wants {
            try Task.checkCancellation()
            let dst = destination.appendingPathComponent(w.path)
            if intact(dst, w) {
                p.done += w.size
            } else {
                p.phase = "Downloading \(w.path)"
                progress(p)
                try await fetch(w, to: dst) { bytes in
                    p.done += Int64(bytes)
                    progress(p)
                }
            }
            p.files += 1
            progress(p)
        }
        p.phase = "Done"
        progress(p)
    }

    private func intact(_ url: URL, _ w: Want) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
              size == w.size else { return false }
        return (try? SteamCodec.sha1(file: url)) == w.sha
    }

    // MARK: app info, keys, servers

    /// Each depot the account can open, with its current public manifest.
    private func depotsAndManifests() async throws -> [(UInt32, UInt64)] {
        let c = connection
        var tokReq = ProtoWriter()
        tokReq.uint(2, Self.appID)
        let tokReply = try await c.request(SteamConnection.EMsg.clientPICSAccessTokenRequest, tokReq, what: "the game's access")
        var token: UInt64 = 0
        if let r = try tokReply.first.map({ try ProtoMessage($0.body) }) {
            for t in r.messages(3) where t.uint(1) == UInt64(Self.appID) { token = t.uint(2) ?? 0 }
        }

        var app = ProtoWriter()
        app.uint(1, Self.appID)
        app.uint(2, token)
        var infoReq = ProtoWriter()
        infoReq.message(2, app)
        infoReq.bool(3, false)
        let replies = try await c.request(SteamConnection.EMsg.clientPICSProductInfoRequest, infoReq, what: "the game's info") { p in
            !((try? ProtoMessage(p.body))?.bool(6) ?? false)          // response_pending
        }
        var buffer: Data?
        for p in replies {
            let r = try ProtoMessage(p.body)
            for a in r.messages(1) where a.uint(1) == UInt64(Self.appID) { buffer = a.data(5) ?? buffer }
        }
        guard let buffer, let info = KeyValues.parse(String(decoding: buffer, as: UTF8.self)),
              let depots = info["depots"] else { throw Failure.noDepots }

        var out: [(UInt32, UInt64)] = []
        for d in depots.children {
            guard let id = UInt32(d.key), d["depotfromapp"] == nil, d["sharedinstall"] == nil else { continue }
            if let os = d["config"]?["oslist"]?.value, !os.isEmpty, !os.contains("windows") { continue }
            guard let pub = d["manifests"]?["public"] else { continue }
            guard let gidText = pub.value ?? pub["gid"]?.value, let gid = UInt64(gidText) else { continue }
            guard let key = try await depotKey(id) else { continue }
            keys[id] = key
            out.append((id, gid))
        }
        guard !out.isEmpty else { throw Failure.notOwned }
        return out
    }

    private func depotKey(_ depot: UInt32) async throws -> Data? {
        var b = ProtoWriter()
        b.uint(1, depot)
        b.uint(2, Self.appID)
        guard let p = try await connection.request(SteamConnection.EMsg.clientGetDepotDecryptionKey, b,
                                                   what: "the game's key").first else { return nil }
        let r = try ProtoMessage(p.body)
        guard r.int32(1) == 1, let key = r.data(3), key.count == 32 else { return nil }
        return key
    }

    private func manifestRequestCode(depot: UInt32, manifest: UInt64) async throws -> UInt64 {
        var b = ProtoWriter()
        b.uint(1, Self.appID)
        b.uint(2, depot)
        b.uint(3, manifest)
        b.string(4, "public")
        let r = try await connection.service("ContentServerDirectory.GetManifestRequestCode#1", b)
        return r.uint(1) ?? 0
    }

    private func contentServers() async throws -> [Server] {
        var b = ProtoWriter()
        b.uint(1, connection.cellID)
        b.uint(2, UInt32(20))
        let r = try await connection.service("ContentServerDirectory.GetServersForSteamPipe#1", b)
        let list = r.messages(1).compactMap { s -> Server? in
            guard let type = s.string(1), type == "CDN" || type == "SteamCache" else { return nil }
            guard let host = s.string(9) ?? s.string(8), !host.isEmpty else { return nil }
            let https = s.string(12) ?? ""
            return Server(host: host, https: https == "mandatory" || https == "optional")
        }
        guard !list.isEmpty else { throw Failure.noServers }
        return list.sorted { $0.https && !$1.https }
    }

    private func server(_ attempt: Int) -> Server {
        lock.lock(); defer { lock.unlock() }
        if attempt > 0 { nextServer += 1 }
        return servers[nextServer % servers.count]
    }

    private func get(_ path: String, what: String) async throws -> Data {
        var lastError: Error = Failure.noServers
        for attempt in 0..<4 {
            let s = server(attempt)
            let url = URL(string: "\(s.https ? "https" : "http")://\(s.host)/\(path)")!
            do {
                let (data, response) = try await urls.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { lastError = Failure.http(code, what); continue }
                return data
            } catch {
                if error is CancellationError { throw error }
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: the manifest

    private func manifestFiles(depot: UInt32, manifest: UInt64, code: UInt64, key: Data) async throws -> [Want] {
        let path = "depot/\(depot)/manifest/\(manifest)/5" + (code > 0 ? "/\(code)" : "")
        let zip = try await get(path, what: "the list of game files")
        let raw = try SteamCodec.unzipSingle(zip)
        var payload: ProtoMessage?
        var encrypted = false
        var o = 0
        func u32(_ at: Int) -> UInt32 { raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) }.littleEndian }
        while o + 4 <= raw.count {
            let magic = u32(o); o += 4
            if magic == 0x32C4_15AB { break }                                 // end of manifest
            guard o + 4 <= raw.count else { break }
            let n = Int(u32(o)); o += 4
            guard o + n <= raw.count else { throw SteamCodec.Failure.zip("short manifest") }
            let section = raw.subdata(in: o..<(o + n)); o += n
            switch magic {
            case 0x71F6_17D0: payload = try ProtoMessage(section)            // payload
            case 0x1F48_12BE: encrypted = (try ProtoMessage(section)).bool(4) // metadata
            default: break                                                     // signature
            }
        }
        guard let payload else { throw SteamCodec.Failure.zip("no file list") }

        var out: [Want] = []
        for f in payload.messages(1) {
            let flags = f.uint(3) ?? 0
            if flags & 64 != 0 { continue }                                    // a directory
            guard var name = f.string(1) else { continue }
            if encrypted {
                // base64 that Foundation's strict decoder rejects for some names (line breaks)
                guard let enc = Data(base64Encoded: name, options: .ignoreUnknownCharacters),
                      var plain = try? SteamCodec.symmetricDecrypt(enc, key: key) else { continue }
                if plain.last == 0 { plain.removeLast() }
                name = String(decoding: plain, as: UTF8.self)
            }
            name = name.replacingOccurrences(of: "\\", with: "/")
            let chunks = f.messages(6).compactMap { c -> Chunk? in
                guard let id = c.data(1) else { return nil }
                return Chunk(id: id, offset: Int64(c.uint(3) ?? 0), size: Int(c.uint(4) ?? 0),
                             packed: Int(c.uint(5) ?? 0), adler: UInt32(truncatingIfNeeded: c.uint(2) ?? 0))
            }
            out.append(Want(depot: depot, path: name, size: Int64(f.uint(2) ?? 0), sha: f.data(5) ?? Data(), chunks: chunks))
        }
        return out
    }

    // MARK: files

    /// One file: its chunks (eight at a time) into a .part file at their offsets, its SHA-1,
    /// then the file in place.
    private func fetch(_ w: Want, to dst: URL, onBytes: @escaping (Int) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = dst.appendingPathExtension("part")
        try? fm.removeItem(at: part)
        fm.createFile(atPath: part.path, contents: nil)
        let h = try FileHandle(forWritingTo: part)
        defer { try? h.close() }
        try h.truncate(atOffset: UInt64(w.size))
        guard let key = keys[w.depot] else { throw Failure.notOwned }

        try await withThrowingTaskGroup(of: (Int64, Data).self) { group in
            var pending = w.chunks[...]
            func start() {
                guard let c = pending.popFirst() else { return }
                group.addTask { [self] in
                    let hex = c.id.map { String(format: "%02x", $0) }.joined()
                    var lastError: Error = SteamCodec.Failure.checksum
                    for _ in 0..<3 {                      // a damaged chunk is fetched again
                        try Task.checkCancellation()
                        let data = try await get("depot/\(w.depot)/chunk/\(hex)", what: w.path)
                        do { return (c.offset, try SteamCodec.chunk(data, key: key, size: c.size, adler: c.adler)) }
                        catch { lastError = error }
                    }
                    throw lastError
                }
            }
            for _ in 0..<8 { start() }
            for try await (offset, data) in group {
                try h.seek(toOffset: UInt64(offset))
                try h.write(contentsOf: data)
                onBytes(data.count)
                start()
            }
        }
        try h.synchronize()
        try h.close()
        guard try SteamCodec.sha1(file: part) == w.sha else {
            try? fm.removeItem(at: part)
            throw Failure.mismatch(w.path)
        }
        try? fm.removeItem(at: dst)
        try fm.moveItem(at: part, to: dst)
    }
}
