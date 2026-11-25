import AVFoundation
import Foundation

/// A short log of what happens to the app around the game: leaving and coming back, calls and
/// other audio interruptions, pause and resume, the audio route. iOS keeps no stderr, so this
/// is how a test on a phone is read afterwards:
///
///     xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///       --domain-identifier com.ff7recomp.ios \
///       --source "Library/Application Support/FF7Recomp/events.log" --destination events.log
///
/// Kept to the last ~256 KB (the older half is dropped).
enum EventLog {
    private static let queue = DispatchQueue(label: "com.ff7recomp.eventlog")
    private static let url = AppPaths.standard.root.appendingPathComponent("events.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 256 << 10,
               let data = try? Data(contentsOf: url) {
                try? data.suffix(size / 2).write(to: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// The audio session as the game hears it: category (ambient follows the silent switch),
    /// whether other audio plays, the output route.
    static func audioState() -> String {
        let s = AVAudioSession.sharedInstance()
        let outputs = s.currentRoute.outputs.map { "\($0.portType.rawValue)" }.joined(separator: ",")
        return "category=\(s.category.rawValue) otherAudio=\(s.isOtherAudioPlaying) "
            + "silenceHint=\(s.secondaryAudioShouldBeSilencedHint) volume=\(String(format: "%.2f", s.outputVolume)) "
            + "route=\(outputs)"
    }
}
