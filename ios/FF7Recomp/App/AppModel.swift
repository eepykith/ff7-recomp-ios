import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// App-wide state: is a game installed, and the services behind setup / launch / mods.
@MainActor
final class AppModel: ObservableObject {
    enum Route { case setup, home }

    enum SetupStatus: Equatable {
        case notInstalled
        case working(GameImportStage)
        case ready(GamePackage)
        case failed(String)
    }

    @Published var route: Route
    @Published var setupStatus: SetupStatus
    @Published private(set) var package: GamePackage?
    @Published var targetFPS: Int = UserDefaults.standard.object(forKey: "ff7.targetFPS") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(targetFPS, forKey: "ff7.targetFPS") }
    }

    let paths: AppPaths
    let installer: GameInstalling
    let launcher: GameLaunching
    let modLibrary: ModLibrary
    /// FF7RecompBundled dev builds: the game folder at Documents/game that the linked-in game
    /// boots when no real package is chosen (EngineBridge.boot(packagePath: nil)).
    let bundledGameDir: String?

    var engineVersion: String { EngineBridge.version() }

    init(paths: AppPaths = .standard,
         installer: GameInstalling? = nil,
         launcher: GameLaunching = StubGameLauncher()) {
        self.paths = paths
        self.installer = installer ?? LocalGameInstaller(
            paths: paths, validator: GamePackageValidator(appCoreVersion: EngineBridge.version()))
        self.launcher = launcher
        self.modLibrary = ModLibrary(paths: paths)
        self.bundledGameDir = EngineBridge.bundledGameDir()

        #if DEBUG
        SampleData.applyLaunchArguments(paths: paths, installer: self.installer, library: modLibrary)
        #endif

        let installed = self.installer.installedPackage()
        package = installed
        route = installed == nil && bundledGameDir == nil ? .setup : .home
        setupStatus = installed.map { .ready($0) } ?? .notInstalled
    }

    var isWorking: Bool {
        if case .working = setupStatus { return true }
        return false
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            setupStatus = .failed(error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            importPackage(from: url)
        }
    }

    func importPackage(from url: URL) {
        setupStatus = .working(.copying)
        let installer = installer
        Task.detached(priority: .userInitiated) {
            do {
                let pkg = try installer.importPackage(from: url) { stage in
                    Task { @MainActor [weak self] in
                        if case .working = self?.setupStatus { self?.setupStatus = .working(stage) }
                    }
                }
                await MainActor.run {
                    self.package = pkg
                    self.setupStatus = .ready(pkg)
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    // A failed import leaves an earlier install in place.
                    self.package = installer.installedPackage()
                    self.setupStatus = .failed(message)
                }
            }
        }
    }

    /// A real package, or the bundled dev game.
    var canPlay: Bool { package != nil || bundledGameDir != nil }

    func continueToLauncher() {
        guard canPlay else { return }
        route = .home
    }

    func showSetup() {
        setupStatus = package.map { .ready($0) } ?? .notInstalled
        route = .setup
    }

    func removeGame() {
        do {
            try installer.uninstall()
        } catch {
            setupStatus = .failed(error.localizedDescription)
        }
        package = nil
        setupStatus = .notInstalled
        route = bundledGameDir == nil ? .setup : .home
    }

    func launchConfiguration() -> GameLaunchConfiguration? {
        guard let package else { return nil }
        return try? launcher.prepareLaunch(package)
    }

    /// What Play hands to GameHostView. nil lets EngineBridge fall back to the bundled dev
    /// game, which also wins over a stub package (no game code of its own).
    var playPackagePath: String? {
        if bundledGameDir != nil, package == nil || package?.isStub == true { return nil }
        return launchConfiguration()?.packagePath
    }

    #if DEBUG
    func installSamplePackage() {
        do {
            importPackage(from: try SampleData.makeSamplePackageFolder())
        } catch {
            setupStatus = .failed(error.localizedDescription)
        }
    }
    #endif
}

extension UTType {
    static var ff7Package: UTType {
        UTType(exportedAs: "com.ff7recomp.gamepackage", conformingTo: .archive)
    }

    static var iroArchive: UTType {
        UTType(importedAs: "com.ff7recomp.iro", conformingTo: .data)
    }
}
