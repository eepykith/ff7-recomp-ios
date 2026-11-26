import Foundation
import UIKit

/// The player's way to send us what happened: the game's logs, the device and the mods, in one
/// zip for a GitHub issue (Settings > Share logs, or offered after a crash).
///
/// The logs also sit in the Files app's FF7Recomp folder (On My iPhone > FF7Recomp > Logs),
/// refreshed at every launch and every share:
///   engine.log, engine.prev.log   the engine's output, this session and the one before
///                                 (a crash report ends the session it happened in)
///   events.log                    leaving the app, calls, pause and resume, the audio session
///   FFNx.log                      FFNx's own log (game modes, graphics, music)
///   info.txt                      app version, device, iOS, mods in load order
enum LogBundle {
    static let folderName = "Logs"
    static let issuesURL = URL(string: "https://github.com/eepykith/ff7-recomp-ios/issues")!

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (build \(b))"
    }

    /// The device's model identifier ("iPhone19,4"); the simulator reports the one it runs.
    static var deviceModel: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim + " (simulator)" }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// The previous session ended in a crash: its engine log carries the crash handler's report.
    static func lastSessionCrashed(paths: AppPaths = .standard) -> Bool {
        let prev = paths.root.appendingPathComponent("engine.prev.log")
        guard let h = try? FileHandle(forReadingFrom: prev) else { return false }
        defer { try? h.close() }
        // the report is at the end; the last 64 KB is plenty
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65536 ? size - 65536 : 0)
        let tail = String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
        return tail.contains("[ff7] FAULT") || tail.contains("FATAL:")
    }

    /// A short id of the crashed session (the first line of engine.prev.log, its start time), so
    /// the after-crash offer is made once per crash.
    static func crashID(paths: AppPaths = .standard) -> String? {
        let prev = paths.root.appendingPathComponent("engine.prev.log")
        guard let h = try? FileHandle(forReadingFrom: prev) else { return nil }
        defer { try? h.close() }
        let head = String(decoding: (try? h.read(upToCount: 200)) ?? Data(), as: UTF8.self)
        return head.split(separator: "\n").first.map(String.init)
    }

    /// Copies the logs into Files > FF7Recomp > Logs and writes info.txt. Returns the folder.
    @discardableResult
    static func refreshFolder(paths: AppPaths = .standard, documents: URL = AppPaths.documents) -> URL {
        let fm = FileManager.default
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let sources: [(URL, String)] = [
            (paths.root.appendingPathComponent("engine.log"), "engine.log"),
            (paths.root.appendingPathComponent("engine.prev.log"), "engine.prev.log"),
            (paths.root.appendingPathComponent("events.log"), "events.log"),
            (paths.game.appendingPathComponent("FFNx.log"), "FFNx.log"),
        ]
        for (src, name) in sources {
            let dst = folder.appendingPathComponent(name)
            try? fm.removeItem(at: dst)
            if fm.fileExists(atPath: src.path) { try? fm.copyItem(at: src, to: dst) }
        }
        try? Data(info(paths: paths).utf8).write(to: folder.appendingPathComponent("info.txt"), options: .atomic)
        return folder
    }

    /// What the logs can't say: the app, the device, the mods in load order.
    static func info(paths: AppPaths = .standard) -> String {
        var s = "FF7Recomp \(appVersion), engine \(EngineBridge.version())\n"
        s += "Device: \(deviceModel), \(systemVersion)\n"
        s += "Written: \(ISO8601DateFormatter().string(from: Date()))\n"
        s += "Last session crashed: \(lastSessionCrashed(paths: paths) ? "yes" : "no")\n\n"
        let loaded = ModLibrary(paths: paths).load()
        s += "Mods (load order, the first wins), language \(loaded.language ?? "en"):\n"
        if loaded.mods.isEmpty { s += "  none\n" }
        for (i, m) in loaded.mods.enumerated() {
            var line = "  \(i + 1). [\(m.enabled ? "on" : "off")] \(m.displayName)"
            if let v = m.info?.version { line += " v\(v)" }
            line += " (\(m.fileName))"
            if !m.options.isEmpty { line += " options: " + m.options.map { "\($0.id)=\($0.value)" }.joined(separator: ", ") }
            s += line + "\n"
        }
        return s
    }

    /// The Logs folder zipped (FF7Recomp-logs-<date>.zip in the temporary folder), for sharing.
    static func makeZip(paths: AppPaths = .standard) throws -> URL {
        let folder = refreshFolder(paths: paths)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("FF7Recomp-logs-\(stamp.string(from: Date())).zip")
        try? FileManager.default.removeItem(at: out)
        // reading a folder "for uploading" hands back a zip of it (the system's own zipper)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            do { try FileManager.default.copyItem(at: zip, to: out) } catch { copyError = error }
        }
        if let e = coordinatorError ?? copyError as NSError? { throw e }
        return out
    }

    /// A new GitHub issue with the version and device filled in (the player attaches the zip).
    static func reportURL() -> URL {
        var c = URLComponents(url: issuesURL.appendingPathComponent("new"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "app", value: appVersion),
            URLQueryItem(name: "device", value: "\(deviceModel), \(systemVersion)"),
        ]
        return c.url!
    }
}
