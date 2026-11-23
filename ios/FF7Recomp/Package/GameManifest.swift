import Foundation

/// `manifest.json` at the root of a GamePackage (`.ff7pkg`), written by the Mac companion
/// (`mac/ff7recomp_mac build-package`). Format `ff7pkg-v1`:
///
/// ```json
/// {
///   "format": "ff7pkg-v1",
///   "exe_sha256": "<64 hex: the player's ff7_en.exe the package was lifted from>",
///   "language": "en",
///   "build_id": "<opaque id of this lift/compile>",
///   "core_version": "0.2.0",
///   "platform": "ios-arm64",
///   "exe_name": "ff7_en.exe", "exe_size": 1234, "tool_version": "0.1.0",
///   "created_at": "2026-11-23T10:00:00Z", "notes": "...",
///   "files": [ { "path": "libff7.dylib", "sha256": "<64 hex>", "size": 1234 } ]
/// }
/// ```
///
/// Required: format, exe_sha256, language, build_id, core_version. `platform` defaults to
/// `ios-arm64`; `files` (the package layout, each checked by `GamePackageValidator`) defaults
/// to none, which is a stub package (P0/P1 Mac CLI output: manifest + fingerprint only).
struct GameManifest: Equatable, Codable {
    static let supportedFormat = "ff7pkg-v1"
    static let supportedPlatform = "ios-arm64"
    /// Steam edition languages (data/lang-<code>).
    static let supportedLanguages: Set<String> = ["en", "fr", "de", "es", "ja"]

    struct FileEntry: Equatable, Codable {
        var path: String
        var sha256: String
        var size: Int64?
    }

    var format: String
    var exeSHA256: String
    var language: String
    var buildID: String
    var coreVersion: String
    var platform: String
    var exeName: String?
    var exeSize: Int64?
    var toolVersion: String?
    var createdAt: String?
    var notes: String?
    var files: [FileEntry]

    enum CodingKeys: String, CodingKey {
        case format
        case exeSHA256 = "exe_sha256"
        case language
        case buildID = "build_id"
        case coreVersion = "core_version"
        case platform
        case exeName = "exe_name"
        case exeSize = "exe_size"
        case toolVersion = "tool_version"
        case createdAt = "created_at"
        case notes
        case files
    }

    /// Short form of the exe hash for display.
    var exeFingerprint: String { String(exeSHA256.prefix(12)) }
}

enum GameManifestError: Error, Equatable, LocalizedError {
    case notJSON
    case missingField(String)
    case wrongType(String)
    case unsupportedFormat(String)
    case invalidSHA256(field: String)
    case unsupportedLanguage(String)
    case unsupportedPlatform(String)
    case invalidFilePath(String)

    var errorDescription: String? {
        switch self {
        case .notJSON: return "manifest.json is not a JSON object."
        case .missingField(let f): return "manifest.json is missing \"\(f)\"."
        case .wrongType(let f): return "manifest.json field \"\(f)\" has the wrong type."
        case .unsupportedFormat(let f):
            return "Package format \"\(f)\" is not supported by this app (expects \(GameManifest.supportedFormat)). Rebuild it with a matching Mac companion."
        case .invalidSHA256(let f): return "manifest.json \"\(f)\" is not a SHA-256 hex digest."
        case .unsupportedLanguage(let l): return "Game language \"\(l)\" is not supported."
        case .unsupportedPlatform(let p): return "This package was built for \(p), not iOS (\(GameManifest.supportedPlatform))."
        case .invalidFilePath(let p): return "manifest.json lists an unsafe file path: \(p)"
        }
    }
}

enum GameManifestParser {
    static func parse(_ data: Data) throws -> GameManifest {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            throw GameManifestError.notJSON
        }

        func string(_ key: String, required: Bool = true) throws -> String? {
            guard let raw = json[key], !(raw is NSNull) else {
                if required { throw GameManifestError.missingField(key) }
                return nil
            }
            guard let value = raw as? String else { throw GameManifestError.wrongType(key) }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if required && trimmed.isEmpty { throw GameManifestError.missingField(key) }
            return trimmed
        }

        func int64(_ key: String, in dict: [String: Any]) throws -> Int64? {
            guard let raw = dict[key], !(raw is NSNull) else { return nil }
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                throw GameManifestError.wrongType(key)
            }
            return number.int64Value
        }

        let format = try string("format")!
        guard format == GameManifest.supportedFormat else {
            throw GameManifestError.unsupportedFormat(format)
        }

        let sha = try string("exe_sha256")!.lowercased()
        guard isSHA256(sha) else { throw GameManifestError.invalidSHA256(field: "exe_sha256") }

        let language = try string("language")!.lowercased()
        guard GameManifest.supportedLanguages.contains(language) else {
            throw GameManifestError.unsupportedLanguage(language)
        }

        let buildID = try string("build_id")!
        let coreVersion = try string("core_version")!

        let platform = try string("platform", required: false) ?? GameManifest.supportedPlatform
        guard platform == GameManifest.supportedPlatform else {
            throw GameManifestError.unsupportedPlatform(platform)
        }

        var files: [GameManifest.FileEntry] = []
        if let rawFiles = json["files"], !(rawFiles is NSNull) {
            guard let list = rawFiles as? [[String: Any]] else { throw GameManifestError.wrongType("files") }
            for entry in list {
                guard let path = entry["path"] as? String, !path.isEmpty else {
                    throw GameManifestError.missingField("files[].path")
                }
                guard isSafeRelativePath(path) else { throw GameManifestError.invalidFilePath(path) }
                guard let fileSHA = (entry["sha256"] as? String)?.lowercased(), isSHA256(fileSHA) else {
                    throw GameManifestError.invalidSHA256(field: "files[\(path)].sha256")
                }
                files.append(.init(path: path, sha256: fileSHA, size: try int64("size", in: entry)))
            }
        }

        return GameManifest(
            format: format,
            exeSHA256: sha,
            language: language,
            buildID: buildID,
            coreVersion: coreVersion,
            platform: platform,
            exeName: try string("exe_name", required: false),
            exeSize: try int64("exe_size", in: json),
            toolVersion: try string("tool_version", required: false),
            createdAt: try string("created_at", required: false),
            notes: try string("notes", required: false),
            files: files
        )
    }

    static func isSHA256(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { $0.isHexDigit }
    }

    /// Relative, '/'-separated, no `..`, no leading '/', no backslashes.
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0.isEmpty }
    }
}
