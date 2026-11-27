import Foundation

/// A connection to Steam (a "CM" server) over a WebSocket, as SteamKit2's CMClient and
/// WebSocketConnection make it. Every message is an EMsg with the protobuf flag, a
/// CMsgProtoBufHeader and a protobuf body. A request carries a job id; its reply carries the
/// same id as its target. Bundles of messages (EMsg Multi, often gzipped) are unpacked.
final class SteamConnection: @unchecked Sendable {
    struct Packet {
        let emsg: UInt32
        let header: ProtoMessage
        let body: Data
    }

    enum Failure: Error, CustomStringConvertible {
        case noServers, closed(String), timeout(String), result(String, Int32)
        var description: String {
            switch self {
            case .noServers: return "could not reach Steam (no server answered)"
            case .closed(let why): return "the connection to Steam closed (\(why))"
            case .timeout(let what): return "Steam did not answer (\(what))"
            case .result(let what, let r): return "Steam refused \(what) (\(SteamConnection.resultName(r)))"
            }
        }
    }

    enum EMsg {
        static let multi: UInt32 = 1
        static let serviceMethodResponse: UInt32 = 147
        static let serviceMethodCallFromClient: UInt32 = 151
        static let clientHeartBeat: UInt32 = 703
        static let clientLogOnResponse: UInt32 = 751
        static let clientLoggedOff: UInt32 = 757
        static let clientGetDepotDecryptionKey: UInt32 = 5438
        static let clientGetDepotDecryptionKeyResponse: UInt32 = 5439
        static let clientLogon: UInt32 = 5514
        static let clientPICSProductInfoRequest: UInt32 = 8903
        static let clientPICSProductInfoResponse: UInt32 = 8904
        static let clientPICSAccessTokenRequest: UInt32 = 8905
        static let clientPICSAccessTokenResponse: UInt32 = 8906
        static let serviceMethodCallFromClientNonAuthed: UInt32 = 9804
        static let clientHello: UInt32 = 9805
    }

    /// SteamKit2's MsgClientLogon.CurrentProtocol.
    static let protocolVersion: UInt32 = 65581
    private static let protoFlag: UInt32 = 0x8000_0000

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private let lock = NSLock()
    /// A request waiting for replies: onPacket returns true when the job is finished.
    private struct Job { let onPacket: (Packet) -> Bool; let onFail: (Error) -> Void }
    private struct Waiter { let onPacket: (Packet) -> Void; let onFail: (Error) -> Void }
    private var jobs: [UInt64: Job] = [:]
    private var waiters: [UInt32: [Waiter]] = [:]
    private var nextJob: UInt64 = UInt64.random(in: 1...(1 << 40))
    private var closedReason: String?
    private var heartbeat: Task<Void, Never>?

    /// Set once logged on (SteamLogin.logOn).
    var steamID: UInt64?
    var sessionID: Int32 = 0
    var cellID: UInt32 = 0

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    deinit { close() }

    // MARK: connecting

    /// Steam's WebSocket servers for this place, from its directory, then the first that answers.
    static func connect() async throws -> SteamConnection {
        let url = URL(string: "https://api.steampowered.com/ISteamDirectory/GetCMListForConnect/v1/?cellid=0&cmtype=websockets")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct List: Decodable {
            struct Response: Decodable {
                struct Server: Decodable { let endpoint: String; let type: String }
                let serverlist: [Server]
            }
            let response: Response
        }
        let servers = try JSONDecoder().decode(List.self, from: data).response.serverlist
            .filter { $0.type == "websockets" }.map(\.endpoint)
        var lastError: Error = Failure.noServers
        for endpoint in servers.prefix(5) {
            let c = SteamConnection()
            do {
                try await c.open(endpoint)
                return c
            } catch {
                lastError = error
                c.close()
            }
        }
        throw lastError
    }

    private func open(_ endpoint: String) async throws {
        guard let url = URL(string: "wss://\(endpoint)/cmsocket/") else { throw Failure.noServers }
        let s = session.webSocketTask(with: url)
        s.maximumMessageSize = 64 << 20
        socket = s
        s.resume()
        receive()
        var hello = ProtoWriter()
        hello.uint(1, Self.protocolVersion)
        try await send(EMsg.clientHello, hello)
    }

    func close() {
        heartbeat?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        fail("closed")
    }

    /// Keeps the session alive after logon, every `seconds` as Steam asked.
    func startHeartbeat(seconds: Int) {
        heartbeat?.cancel()
        let interval = UInt64(max(5, seconds)) * 1_000_000_000
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard let self, !Task.isCancelled else { return }
                try? await self.send(EMsg.clientHeartBeat, ProtoWriter())
            }
        }
    }

    // MARK: sending

    func send(_ emsg: UInt32, _ body: ProtoWriter, job: UInt64? = nil, target: String? = nil,
              steamID overrideID: UInt64? = nil) async throws {
        var h = ProtoWriter()
        if let id = overrideID ?? steamID { h.fixed64(1, id) }
        if overrideID != nil || steamID != nil { h.int32(2, sessionID) }
        if let job { h.fixed64(10, job) }
        if let target { h.string(12, target) }
        var packet = Data()
        withUnsafeBytes(of: (emsg | Self.protoFlag).littleEndian) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(h.data.count).littleEndian) { packet.append(contentsOf: $0) }
        packet.append(h.data)
        packet.append(body.data)
        guard let socket else { throw Failure.closed("not connected") }
        try await socket.send(.data(packet))
    }

    private func newJob() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        nextJob += 1
        return nextJob
    }

    /// A request and every reply to it, until `finished` says the last one came.
    func request(_ emsg: UInt32, _ body: ProtoWriter, target: String? = nil, what: String,
                 timeout: Double = 30, finished: @escaping (Packet) -> Bool = { _ in true }) async throws -> [Packet] {
        let job = newJob()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[Packet], Error>) in
            var got: [Packet] = []
            var done = false
            let finish: (Result<[Packet], Error>) -> Void = { [weak self] r in
                guard let self else { return }
                self.lock.lock()
                if done { self.lock.unlock(); return }
                done = true
                self.jobs[job] = nil
                self.lock.unlock()
                c.resume(with: r)
            }
            lock.lock()
            if let why = closedReason {
                lock.unlock()
                c.resume(throwing: Failure.closed(why))
                return
            }
            jobs[job] = Job(onPacket: { p in
                got.append(p)
                guard finished(p) else { return false }
                DispatchQueue.global().async { finish(.success(got)) }
                return true
            }, onFail: { e in finish(.failure(e)) })
            lock.unlock()
            Task {
                do { try await self.send(emsg, body, job: job, target: target) } catch { finish(.failure(error)) }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                finish(.failure(Failure.timeout(what)))
            }
        }
    }

    /// A unified service method ("Authentication.BeginAuthSessionViaQR#1"): its reply's body.
    func service(_ method: String, _ body: ProtoWriter, authed: Bool = true) async throws -> ProtoMessage {
        let emsg = authed ? EMsg.serviceMethodCallFromClient : EMsg.serviceMethodCallFromClientNonAuthed
        guard let p = try await request(emsg, body, target: method, what: method).first else { throw Failure.timeout(method) }
        let result = p.header.int32(13) ?? 2
        guard result == 1 else { throw Failure.result(method, result) }
        return try ProtoMessage(p.body)
    }

    /// The next message of a kind that is not a reply to a job (the logon response).
    func next(_ emsg: UInt32, what: String, timeout: Double = 30) async throws -> Packet {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Packet, Error>) in
            var done = false
            let finish: (Result<Packet, Error>) -> Void = { [weak self] r in
                guard let self else { return }
                self.lock.lock()
                if done { self.lock.unlock(); return }
                done = true
                self.lock.unlock()
                c.resume(with: r)
            }
            lock.lock()
            if let why = closedReason {
                lock.unlock()
                c.resume(throwing: Failure.closed(why))
                return
            }
            waiters[emsg, default: []].append(Waiter(onPacket: { p in finish(.success(p)) },
                                                     onFail: { e in finish(.failure(e)) }))
            lock.unlock()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                finish(.failure(Failure.timeout(what)))
            }
        }
    }

    // MARK: receiving

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let d)):
                self.handle(d)
                self.receive()
            case .success:
                self.receive()
            case .failure(let e):
                self.fail(e.localizedDescription)
            }
        }
    }

    private func handle(_ data: Data) {
        guard data.count >= 8 else { return }
        let raw = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        guard raw & Self.protoFlag != 0 else { return }           // old-style messages: not used here
        let emsg = raw & ~Self.protoFlag
        let hlen = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian)
        guard 8 + hlen <= data.count, let header = try? ProtoMessage(data.subdata(in: 8..<(8 + hlen))) else { return }
        let packet = Packet(emsg: emsg, header: header, body: data.subdata(in: (8 + hlen)..<data.count))

        if emsg == EMsg.multi {
            unpackMulti(packet)
            return
        }
        if emsg == EMsg.clientLoggedOff {
            let r = (try? ProtoMessage(packet.body))?.int32(1) ?? 0
            fail("Steam signed this session out: \(Self.resultName(r))")
            return
        }
        lock.lock()
        if let target = header.uint(11), target != UInt64.max, let handler = jobs[target] {
            lock.unlock()
            if handler.onPacket(packet) { lock.lock(); jobs[target] = nil; lock.unlock() }
            return
        }
        if var list = waiters[emsg], !list.isEmpty {
            let w = list.removeFirst()
            waiters[emsg] = list
            lock.unlock()
            w.onPacket(packet)
            return
        }
        lock.unlock()
    }

    private func unpackMulti(_ p: Packet) {
        guard let m = try? ProtoMessage(p.body), var payload = m.data(2) else { return }
        let unzipped = Int(m.uint(1) ?? 0)
        if unzipped > 0 {
            guard let d = try? SteamCodec.gunzip(payload, size: unzipped) else { return }
            payload = d
        }
        var o = 0
        while o + 4 <= payload.count {
            let n = Int(payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }.littleEndian)
            o += 4
            guard o + n <= payload.count else { return }
            handle(payload.subdata(in: o..<(o + n)))
            o += n
        }
    }

    private func fail(_ why: String) {
        lock.lock()
        if closedReason == nil { closedReason = why }
        let pending = jobs
        jobs.removeAll()
        let waiting = waiters
        waiters.removeAll()
        lock.unlock()
        let error = Failure.closed(why)
        for j in pending.values { j.onFail(error) }
        for list in waiting.values { for w in list { w.onFail(error) } }
    }

    // MARK: results

    static func resultName(_ r: Int32) -> String {
        switch r {
        case 1: return "OK"
        case 2: return "failure"
        case 3: return "no connection"
        case 5: return "the sign-in is no longer valid"
        case 6: return "signed in elsewhere"
        case 8: return "invalid request"
        case 9: return "not found"
        case 15: return "access denied"
        case 16: return "timed out"
        case 20: return "Steam is busy"
        case 27: return "expired"
        case 84: return "too many attempts, try again later"
        default: return "code \(r)"
        }
    }
}
