import CryptoKit
import Foundation

/// Where things live in the app container. Mirrors the Android `files/` layout the core
/// expects: the game in `<root>/game`, mods next to it in `<root>/mods` with
/// `<root>/mods/profile.xml` (read by `ff7_mods_load` as `<game>/../mods/profile.xml`), and
/// IRO extraction cache in `<root>/modcache`.
struct AppPaths {
    let root: URL

    static var standard: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appendingPathComponent("FF7Recomp", isDirectory: true))
    }

    var game: URL { root.appendingPathComponent("game", isDirectory: true) }
    var mods: URL { root.appendingPathComponent("mods", isDirectory: true) }
    var modProfile: URL { mods.appendingPathComponent("profile.xml") }
    var modCache: URL { root.appendingPathComponent("modcache", isDirectory: true) }
    var importStaging: URL { root.appendingPathComponent(".import", isDirectory: true) }
}

/// File names inside a GamePackage.
enum GamePackageLayout {
    static let manifest = "manifest.json"
    /// The lifted, compiled and signed game (P3). Its absence makes a stub package.
    static let library = "libff7.dylib"
}

/// A validated, installed GamePackage.
struct GamePackage: Equatable {
    let rootURL: URL
    let manifest: GameManifest

    /// P0/P1 Mac CLI output: a manifest with no game code. Launching it shows the host's
    /// "no game" status rather than the game.
    var isStub: Bool { !manifest.files.contains { $0.path == GamePackageLayout.library } }
    var libraryURL: URL { rootURL.appendingPathComponent(GamePackageLayout.library) }
}

enum GamePackageError: Error, LocalizedError, Equatable {
    case missingManifest
    case manifest(GameManifestError)
    case missingFile(String)
    case sizeMismatch(String)
    case hashMismatch(String)
    case incompatibleCore(package: String, app: String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "This is not a GamePackage: manifest.json is missing."
        case .manifest(let e):
            return e.errorDescription
        case .missingFile(let p):
            return "The package is incomplete: \(p) is missing."
        case .sizeMismatch(let p), .hashMismatch(let p):
            return "\(p) does not match the package manifest (damaged or modified). Copy the package again from your Mac."
        case .incompatibleCore(let pkg, let app):
            return "The package was built for core \(pkg), but this app runs core \(app). Rebuild it with the matching Mac companion."
        }
    }
}

/// Checks a GamePackage directory: the manifest parses, its core version matches the app's,
/// and every file it lists is present with the listed size and SHA-256.
struct GamePackageValidator {
    /// The app's core version (`ff7_host_version()`); nil skips the compatibility check.
    var appCoreVersion: String?

    func validate(directory: URL, verifyHashes: Bool = true) throws -> GamePackage {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent(GamePackageLayout.manifest)
        guard let data = fm.contents(atPath: manifestURL.path) else { throw GamePackageError.missingManifest }

        let manifest: GameManifest
        do {
            manifest = try GameManifestParser.parse(data)
        } catch let error as GameManifestError {
            throw GamePackageError.manifest(error)
        }

        if let appCoreVersion, !CoreVersion.isCompatible(package: manifest.coreVersion, app: appCoreVersion) {
            throw GamePackageError.incompatibleCore(package: manifest.coreVersion, app: appCoreVersion)
        }

        for file in manifest.files {
            let url = directory.appendingPathComponent(file.path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                throw GamePackageError.missingFile(file.path)
            }
            if let size = file.size {
                let actual = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                guard actual == size else { throw GamePackageError.sizeMismatch(file.path) }
            }
            if verifyHashes {
                guard (try? Self.sha256(of: url)) == file.sha256 else { throw GamePackageError.hashMismatch(file.path) }
            }
        }
        return GamePackage(rootURL: directory, manifest: manifest)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Core compatibility: same major version, and for 0.x the same minor too (semver's
/// "anything may change" range). Pre-release / build suffixes are ignored.
enum CoreVersion {
    static func components(_ v: String) -> [Int] {
        let core = v.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? v
        return core.split(separator: ".").map { Int($0) ?? -1 }
    }

    static func isCompatible(package: String, app: String) -> Bool {
        let p = components(package), a = components(app)
        guard let pMajor = p.first, let aMajor = a.first, pMajor >= 0, pMajor == aMajor else { return false }
        if aMajor == 0 {
            return p.count > 1 && a.count > 1 && p[1] == a[1]
        }
        return true
    }
}
