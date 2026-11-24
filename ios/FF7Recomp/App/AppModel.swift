import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// App-wide state: are the game files here, is the game built into this app, and the
/// services behind setup / launch / mods.
///
/// Setup: the game is built into the app by FF7Recomp Builder on a Mac, usually with the game
/// files too; without them the app asks for them (Find my FF7 folder). It confirms them, then Play.
@MainActor
final class AppModel: ObservableObject {
    enum Route { case setup, home }

    /// A long job on the game files (import, download, repair).
    struct Job: Equatable {
        var title: String
        var detail: String
        var fraction: Double?
    }

    @Published var route: Route
    @Published private(set) var filesState: GameFiles.State = .missing
    @Published private(set) var job: Job?
    @Published var message: String?
    /// The play view is up (LauncherHomeView pushes GameHostView while this is true).
    @Published var playing = false
    @Published var targetFPS: Int = UserDefaults.standard.object(forKey: "ff7.targetFPS") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(targetFPS, forKey: "ff7.targetFPS") }
    }

    let paths: AppPaths
    let files: GameFiles
    let modLibrary: ModLibrary
    private var cancelFlag = CancelFlag()

    var engineVersion: String { EngineBridge.version() }
    /// The game is compiled into this app (the Mac build).
    var hasGameCode: Bool { EngineBridge.hasGameCode }
    var hasFiles: Bool { filesState == .ready }
    var canPlay: Bool { hasFiles && hasGameCode }
    var isWorking: Bool { job != nil }
    /// The game files came inside the app (the Mac builder put them in the IPA).
    let filesBuiltIn = GameFiles.bundledGame != nil

    init(paths: AppPaths = .standard) {
        self.paths = paths
        files = GameFiles(paths: paths)
        modLibrary = ModLibrary(paths: paths)
        route = .setup
        #if DEBUG
        SampleData.applyLaunchArguments(paths: paths, library: modLibrary)
        #endif
        UserFolders.prepare(paths: paths)
        refresh()
        // the first time, the setup screen shows the game files confirmed and Play
        route = canPlay && UserDefaults.standard.bool(forKey: Self.confirmedKey) ? .home : .setup
    }

    private static let confirmedKey = "ff7.gameFilesConfirmed"

    func refresh() {
        if filesBuiltIn { files.useBundledGame() }
        filesState = files.state()
    }

    // MARK: Game files

    /// Find my FF7 folder…
    func importFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            run(title: "Importing the game files") { files, progress, cancelled in
                try files.importFolder(url, progress: progress, cancelled: cancelled)
            }
        }
    }

    func cancelJob() { cancelFlag.set() }

    func removeFiles() {
        do { try files.remove() } catch { message = error.localizedDescription }
        refresh()
        route = .setup
    }

    /// Runs a job on the game files off the main actor, with its progress on the setup screen.
    func run(title: String, _ work: @escaping @Sendable (GameFiles, @escaping (String, Double) -> Void, @escaping () -> Bool) throws -> Void) {
        guard job == nil else { return }
        message = nil
        job = Job(title: title, detail: "", fraction: nil)
        let flag = CancelFlag()
        cancelFlag = flag
        let files = files
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                try work(files, { detail, fraction in
                    Task { @MainActor [weak self] in
                        guard self?.job != nil else { return }
                        self?.job?.detail = detail
                        self?.job?.fraction = fraction
                    }
                }, { flag.isSet })
            } catch is CancellationError {
                failure = "Stopped. Start it again to go on where it was."
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                self.job = nil
                self.message = failure
                self.refresh()
            }
        }
    }

    func continueToLauncher() {
        guard canPlay else { return }
        route = .home
    }

    func showSetup() {
        refresh()
        route = .setup
    }

    /// Play: FFNx's files from the app go into the game folder, then the play view opens.
    func play() {
        refresh()
        guard canPlay else { route = .setup; return }
        UserFolders.prepare(paths: paths)
        files.installRuntime()
        UserDefaults.standard.set(true, forKey: Self.confirmedKey)
        route = .home
        playing = true
    }

    /// Mods change the game's files as it loads them, so they open only once the game files
    /// are here and confirmed (the 1.02 US exe and its data).
    var modsUnlocked: Bool { hasFiles }
}

/// A flag one thread sets and another reads.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

extension UTType {
    static var iroArchive: UTType {
        UTType(importedAs: "com.ff7recomp.iro", conformingTo: .data)
    }
}
