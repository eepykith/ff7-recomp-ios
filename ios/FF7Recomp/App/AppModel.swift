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
    /// The game's frame rate: FFNx's ff7_fps_limiter, written into FFNx.toml at Play.
    @Published var frameRate: FrameRate = (UserDefaults.standard.object(forKey: FrameRate.key) as? Int).flatMap(FrameRate.init(rawValue:)) ?? .standard {
        didSet { UserDefaults.standard.set(frameRate.rawValue, forKey: FrameRate.key) }
    }
    /// 4:3 or 16:9: FFNx's aspect_ratio, written into FFNx.toml at Play; the play view sizes the
    /// picture to match (PlayLayout).
    @Published var aspect: AspectMode = AspectMode.current {
        didSet { UserDefaults.standard.set(aspect.rawValue, forKey: AspectMode.key) }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FF7Play") {
            DispatchQueue.main.async { [weak self] in self?.play() }
        }
        #endif
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
        files.setFrameRate(frameRate)
        files.setAspect(aspect)
        AspectMode.playing = aspect
        UserDefaults.standard.set(true, forKey: Self.confirmedKey)
        route = .home
        playing = true
    }

    /// Mods change the game's files as it loads them, so they open only once the game files
    /// are here and confirmed (the 1.02 US exe and its data).
    var modsUnlocked: Bool { hasFiles }
}

/// How fast the game runs: FFNx's `ff7_fps_limiter` (FFNx.toml), as FFNx's settings offer it.
/// The game's own rates are 30 FPS in the field and on the world map, 15 in battle, 60 in menus.
enum FrameRate: Int, CaseIterable, Identifiable {
    case original = 0
    case originalFixed = 1
    case battle30 = 2
    case all60 = 3
    /// The core's FFNx: field at 120, world map and battles at 60.
    case field120 = 4

    static let key = "ff7.frameRate"
    /// What FF7Recomp has run at so far.
    static let standard = FrameRate.originalFixed
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .original: return "Original"
        case .originalFixed: return "Original, fixed"
        case .battle30: return "30 FPS battles"
        case .all60: return "60 FPS"
        case .field120: return "120 FPS (experimental)"
        }
    }
    var detail: String {
        switch self {
        case .original: return "As shipped: 30 FPS in the field, 15 in battle, 60 in menus, with the game's own timing bugs."
        case .originalFixed: return "As shipped, with FFNx's fixes for the game's timing bugs."
        case .battle30: return "Battles at 30 FPS instead of 15; the rest as shipped."
        case .all60: return "Everything at 60 FPS: smoother, uses more battery."
        case .field120: return "Field at 120 FPS on a 120 Hz screen; world map and battles at 60. Uses the most battery."
        }
    }
}

/// The picture's shape: FFNx's `aspect_ratio`. 16:9 is FFNx's widescreen mode: battles,
/// the world map and wide field screens use the whole width, menus stay 4:3 in the middle; a field whose background is not wide
/// enough keeps side bars (a widescreen mod's backgrounds and config fill those in).
enum AspectMode: Int, CaseIterable, Identifiable {
    case original = 0
    case widescreen = 2

    static let key = "ff7.aspect"
    var id: Int { rawValue }
    /// The setting (16:9 unless the player chose 4:3).
    static var current: AspectMode {
        (UserDefaults.standard.object(forKey: key) as? Int).flatMap(AspectMode.init(rawValue:)) ?? .widescreen
    }
    /// What the running game was started with: FFNx reads aspect_ratio once, at boot, so the
    /// play view keeps to it even if the setting changes.
    static var playing: AspectMode = current

    /// Width over height of the game's picture.
    var ratio: CGFloat { self == .original ? 4.0 / 3.0 : 16.0 / 9.0 }
    var label: String { self == .original ? "4:3 (original)" : "16:9 widescreen" }
    var detail: String {
        switch self {
        case .original: return "The game as it was made, with bars at the sides."
        case .widescreen: return "Battles, the world map and wide field screens fill a 16:9 picture. Menus stay 4:3 in the middle, and field screens whose backgrounds are not wide enough keep narrow bars at the sides."
        }
    }
}

/// A flag one thread sets and another reads.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
    func reset() { lock.lock(); value = false; lock.unlock() }
}

extension UTType {
    static var iroArchive: UTType {
        UTType(importedAs: "com.ff7recomp.iro", conformingTo: .data)
    }
}
