import Foundation
import Security

/// The player's Steam sign-in: a QR code approved in the Steam mobile app (no password is typed
/// here), as SteamKit2's QrAuthSession does. Steam answers with
/// a refresh token, kept in the Mac's Keychain; logons after that use it.
struct SteamAccount: Codable, Equatable {
    var accountName: String
    var refreshToken: String
}

enum SteamLogin {
    /// k_EAuthTokenPlatformType_SteamClient: its refresh token logs a client on.
    private static let platformSteamClient: UInt64 = 1
    /// EOSType MacOS14 (the Builder's oldest macOS).
    private static let osTypeMac: Int32 = -73
    /// Our own logon id, so a Steam client running on this Mac stays signed in.
    private static let loginID: UInt32 = 0x0F7F_B11D

    static var deviceName: String {
        "FF7Recomp Builder on " + (Host.current().localizedName ?? "a Mac")
    }

    struct QRSession {
        var clientID: UInt64
        let requestID: Data
        let interval: Double
        var challengeURL: String
    }

    static func beginQR(_ c: SteamConnection) async throws -> QRSession {
        var details = ProtoWriter()
        details.string(1, deviceName)
        details.uint(2, platformSteamClient)
        details.int32(3, osTypeMac)
        var req = ProtoWriter()
        req.string(1, deviceName)
        req.uint(2, platformSteamClient)
        req.message(3, details)
        req.string(4, "Client")
        let r = try await c.service("Authentication.BeginAuthSessionViaQR#1", req, authed: false)
        guard let id = r.uint(1), let url = r.string(2), let request = r.data(3) else {
            throw SteamConnection.Failure.timeout("the sign-in code")
        }
        return QRSession(clientID: id, requestID: request, interval: Double(r.float(4) ?? 5), challengeURL: url)
    }

    enum PollResult {
        case waiting(newChallengeURL: String?)
        case approved(SteamAccount)
    }

    static func poll(_ c: SteamConnection, _ s: inout QRSession) async throws -> PollResult {
        var req = ProtoWriter()
        req.uint(1, s.clientID)
        req.bytes(2, s.requestID)
        let r = try await c.service("Authentication.PollAuthSessionStatus#1", req, authed: false)
        if let newID = r.uint(1), newID != 0 { s.clientID = newID }
        let newURL = r.string(2).flatMap { $0.isEmpty ? nil : $0 }
        if let newURL { s.challengeURL = newURL }
        if let token = r.string(3), !token.isEmpty, let name = r.string(6) {
            return .approved(SteamAccount(accountName: name, refreshToken: token))
        }
        return .waiting(newChallengeURL: newURL)
    }

    enum LogOnError: Error, CustomStringConvertible {
        case refused(Int32)
        var needsNewSignIn: Bool {
            if case .refused(let r) = self { return [5, 15, 27, 18, 63, 65, 85, 88].contains(r) }
            return false
        }
        var description: String {
            switch self {
            case .refused(let r): return "Steam refused the sign-in (\(SteamConnection.resultName(r)))"
            }
        }
    }

    /// Logs the connection on as the account (CMsgClientLogon with the refresh token as its
    /// access token), then keeps it alive.
    static func logOn(_ c: SteamConnection, _ account: SteamAccount) async throws {
        var ip = ProtoWriter()
        ip.fixed32(1, loginID)
        var b = ProtoWriter()
        b.uint(1, SteamConnection.protocolVersion)
        b.uint(2, loginID)
        b.uint(3, UInt32(0))
        b.uint(5, UInt32(1771))
        b.string(6, "english")
        b.uint(7, UInt32(bitPattern: osTypeMac))
        b.bool(8, true)
        b.message(11, ip)
        b.bytes(30, machineID())
        b.string(50, account.accountName)
        b.string(96, deviceName)
        b.bool(102, true)
        b.string(108, account.refreshToken)
        // the individual account "0" in the public universe, desktop instance, until Steam
        // answers with the real one
        try await c.send(SteamConnection.EMsg.clientLogon, b, steamID: 0x0110_0001_0000_0000)
        let p = try await c.next(SteamConnection.EMsg.clientLogOnResponse, what: "the sign-in")
        let r = try ProtoMessage(p.body)
        let result = r.int32(1) ?? 2
        guard result == 1 else { throw LogOnError.refused(result) }
        c.steamID = p.header.uint(1)
        c.sessionID = p.header.int32(2) ?? 0
        c.cellID = UInt32(r.uint(7) ?? 0)
        c.startHeartbeat(seconds: Int(r.int32(3) ?? 9))
    }

    /// The machine id Steam clients send at logon: a binary KeyValues "MessageObject" with three
    /// hashes. This Mac's are made once and kept.
    private static func machineID() -> Data {
        let key = "steamMachineSeed"
        let seed = UserDefaults.standard.string(forKey: key) ?? {
            let s = UUID().uuidString
            UserDefaults.standard.set(s, forKey: key)
            return s
        }()
        func hex(_ s: String) -> String {
            SteamCodec.sha1(Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        var d = Data([0x00]) + Data("MessageObject".utf8) + Data([0])
        for (name, salt) in [("BB3", "bb3"), ("FF2", "ff2"), ("3B3", "3b3")] {
            d += Data([0x01]) + Data(name.utf8) + Data([0]) + Data(hex(seed + salt).utf8) + Data([0])
        }
        d += Data([0x08, 0x08])
        return d
    }
}

/// Where the sign-in is kept: the Keychain (the Builder), or a file (development).
protocol SteamAccountStore {
    func load() -> SteamAccount?
    func save(_ a: SteamAccount)
    func clear()
}

struct KeychainAccountStore: SteamAccountStore {
    private let service = "FF7Recomp Builder Steam sign-in"
    private let account = "steam"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> SteamAccount? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(SteamAccount.self, from: d)
    }

    func save(_ a: SteamAccount) {
        guard let d = try? JSONEncoder().encode(a) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = d
        q[kSecAttrLabel as String] = "FF7Recomp Builder: Steam sign-in (\(a.accountName))"
        SecItemAdd(q as CFDictionary, nil)
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}

struct FileAccountStore: SteamAccountStore {
    let url: URL
    func load() -> SteamAccount? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SteamAccount.self, from: $0) } }
    func save(_ a: SteamAccount) {
        try? JSONEncoder().encode(a).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func clear() { try? FileManager.default.removeItem(at: url) }
}
