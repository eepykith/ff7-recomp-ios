import Foundation

enum GameImportStage: String {
    case copying = "Copying package…"
    case unpacking = "Unpacking…"
    case verifying = "Verifying files…"
}

/// Installs, finds and removes the GamePackage. The UI only talks to this protocol.
protocol GameInstalling: AnyObject {
    /// The installed package (manifest checked, files not re-hashed), or nil.
    func installedPackage() -> GamePackage?
    /// Imports a `.ff7pkg` archive or an unpacked package folder, verifies it fully, and
    /// replaces the installed one. Blocking; call off the main actor.
    func importPackage(from url: URL, progress: @escaping (GameImportStage) -> Void) throws -> GamePackage
    func uninstall() throws
}

/// What the play view needs to start the game.
struct GameLaunchConfiguration: Equatable {
    /// Passed to `ff7_host_boot` (see `GameHostView`).
    var packagePath: String
    var language: String
}

/// Turns an installed package into something the host can boot. P3 replaces the stub with a
/// launcher that verifies the dylib signature and loads it.
protocol GameLaunching {
    func prepareLaunch(_ package: GamePackage) throws -> GameLaunchConfiguration
}

/// Placeholder until P3: hands the package folder to the existing host, which reports what
/// it finds there.
struct StubGameLauncher: GameLaunching {
    func prepareLaunch(_ package: GamePackage) throws -> GameLaunchConfiguration {
        GameLaunchConfiguration(packagePath: package.rootURL.path, language: package.manifest.language)
    }
}

/// Filesystem-backed installer: the package lives unpacked in `AppPaths.game`.
final class LocalGameInstaller: GameInstalling {
    let paths: AppPaths
    let validator: GamePackageValidator
    private let fm = FileManager.default

    init(paths: AppPaths = .standard, validator: GamePackageValidator) {
        self.paths = paths
        self.validator = validator
    }

    func installedPackage() -> GamePackage? {
        try? validator.validate(directory: paths.game, verifyHashes: false)
    }

    func importPackage(from url: URL, progress: @escaping (GameImportStage) -> Void) throws -> GamePackage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let staging = paths.importStaging
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        var isDir: ObjCBool = false
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            progress(.copying)
            try fm.copyItem(at: url, to: staging)
        } else {
            progress(.unpacking)
            try ZipExtractor.extract(archive: url, to: staging)
        }

        progress(.verifying)
        _ = try validator.validate(directory: staging)

        if fm.fileExists(atPath: paths.game.path) {
            try fm.removeItem(at: paths.game)
        }
        try fm.moveItem(at: staging, to: paths.game)
        return try validator.validate(directory: paths.game, verifyHashes: false)
    }

    func uninstall() throws {
        if fm.fileExists(atPath: paths.game.path) {
            try fm.removeItem(at: paths.game)
        }
    }
}
