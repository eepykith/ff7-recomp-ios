import AppKit
import CryptoKit
import Foundation

/// Builds FF7Recomp.ipa: runs build_ipa.py (in the app's Resources, with the kit) on the Mac's
/// python3 and follows its STEP / PROGRESS / ERROR / DONE lines.
@MainActor
final class Builder: ObservableObject {
    enum GameCheck: Equatable {
        case none
        case ok(URL)
        case problem(String)
    }

    enum Phase: Equatable {
        case idle
        case building
        case done(URL)
        case failed(String)
    }

    static let exeSHA1 = "ac306ae92615af75ff36bba6347c67ca1284151d"   // ff7/resources/ff7_1.02/ff7_en
    static let steamDefault = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam/steamapps/common/FINAL FANTASY VII Steam Edition")

    @Published var gameFolder: URL?
    @Published private(set) var game: GameCheck = .none
    @Published private(set) var xcode: String?          // the iOS SDK path, or nil
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var step = ""
    @Published private(set) var progress = 0.0
    @Published private(set) var log: [String] = []
    private var process: Process?

    var kit: URL? { Bundle.main.url(forResource: "kit", withExtension: nil) }
    var script: URL? { Bundle.main.url(forResource: "build_ipa", withExtension: "py") }
    var canBuild: Bool {
        if case .ok = game, xcode != nil, kit != nil, phase != .building { return true }
        return false
    }

    init() {
        if FileManager.default.fileExists(atPath: Self.steamDefault.path) { choose(Self.steamDefault) }
        checkXcode()
    }

    // MARK: Checks

    func choose(_ url: URL) {
        gameFolder = url
        game = .none
        Task.detached(priority: .userInitiated) {
            let result = Self.check(url)
            await MainActor.run { self.game = result }
        }
    }

    nonisolated static func check(_ picked: URL) -> GameCheck {
        let fm = FileManager.default
        func has(_ base: URL) -> Bool {
            fm.fileExists(atPath: base.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path)
                && fm.fileExists(atPath: base.appendingPathComponent("ff7/workingdir/data/field").path)
        }
        var root = picked
        if !has(root) {
            if picked.lastPathComponent.lowercased() == "ff7", has(picked.deletingLastPathComponent()) {
                root = picked.deletingLastPathComponent()
            } else {
                return .problem("This folder does not hold the game. Pick \"FINAL FANTASY VII Steam Edition\", the folder with ff7 inside (not ff7/workingdir).")
            }
        }
        let exe = root.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en")
        guard let data = try? Data(contentsOf: exe, options: .mappedIfSafe) else {
            return .problem("Cannot read \(exe.path).")
        }
        let sha = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard sha == exeSHA1 else {
            return .problem("This ff7_en (SHA-1 \(sha.prefix(12))…) is patched or from another release. FF7Recomp is made from the one in today's Steam install (ff7/resources/ff7_1.02): no patch or older version is needed. Verify the game's files in Steam (Properties → Installed Files) and choose the folder again.")
        }
        return .ok(root)
    }

    func checkXcode() {
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["--sdk", "iphoneos", "--show-sdk-path"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            var sdk: String?
            if (try? p.run()) != nil {
                p.waitUntilExit()
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if p.terminationStatus == 0, !text.isEmpty { sdk = text }
            }
            await MainActor.run { self.xcode = sdk }
        }
    }

    // MARK: Build

    func build(to out: URL) {
        guard case .ok(let root) = game, let kit, let script else { return }
        let work = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FF7Recomp Builder/work", isDirectory: true)
        phase = .building
        step = "Starting"
        progress = 0
        log = []

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-u", script.path, "--kit", kit.path, "--game", root.path, "--out", out.path,
                       "--work", work.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        var pending = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            pending += chunk
            var lines = pending.components(separatedBy: "\n")
            pending = lines.removeLast()
            Task { @MainActor in lines.forEach { self?.handle($0) } }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self else { return }
                if case .building = self.phase {
                    self.phase = proc.terminationStatus == 0 ? .done(out)
                        : .failed(self.log.last(where: { $0.hasPrefix("ERROR") }).map { String($0.dropFirst(6)) }
                                  ?? "The build stopped (exit \(proc.terminationStatus)).")
                }
                self.process = nil
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            phase = .failed("Cannot run python3: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        phase = .failed("Stopped. Build again to go on: what was done is kept.")
    }

    private func handle(_ line: String) {
        if line.hasPrefix("STEP ") {
            let rest = line.dropFirst(5)
            step = rest.split(separator: " ", maxSplits: 1).last.map(String.init) ?? String(rest)
            log.append("— " + step)
        } else if line.hasPrefix("PROGRESS ") {
            progress = Double(line.dropFirst(9)) ?? progress
        } else if line.hasPrefix("ERROR ") {
            log.append(line)
            phase = .failed(String(line.dropFirst(6)))
        } else if line.hasPrefix("DONE ") {
            progress = 1
        } else if !line.isEmpty {
            log.append(line)
        }
    }
}
