import CryptoKit
import Foundation
import zlib

/// Where things live in the app container. Mirrors the Android `files/` layout the core
/// expects: the game in `<root>/game`, mods next to it in `<root>/mods` with
/// `<root>/mods/profile.xml` (read by `ff7_mods_load` as `<game>/../mods/profile.xml`), the IRO
/// extraction cache in `<root>/modcache` and save states in `<root>/savestates`.
///
/// The game files are in `<root>/game` (Library/Application Support/FF7Recomp/game): links to the
/// ones FF7Recomp Builder put in the app, or a copy made by Find my FF7 folder.
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
    var saveStates: URL { root.appendingPathComponent("savestates", isDirectory: true) }

    /// The app's Documents folder: "FF7Recomp" in the Files app (On My iPhone), where the
    /// player's own files live (UserFolders).
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

/// The player's files in the Files app's FF7Recomp folder (On My iPhone > FF7Recomp), so they
/// can be backed up, copied to another device or added to by hand:
///   Saves/        the game's own saves (save00.ff7 ...)
///   Save States/  the status panel's save states
///   Mods/         7th Heaven mods (.iro archives and folders) and the mod order (profile.xml)
/// The engine and the mods screen keep their paths: game/save, savestates and mods next to the
/// game are links to these folders. Files already in the old places move over once.
enum UserFolders {
    static let saves = "Saves", saveStates = "Save States", mods = "Mods"

    static func prepare(paths: AppPaths, documents: URL = AppPaths.documents) {
        let fm = FileManager.default
        var links: [(at: URL, to: URL)] = [
            (paths.saveStates, documents.appendingPathComponent(saveStates, isDirectory: true)),
            (paths.mods, documents.appendingPathComponent(mods, isDirectory: true)),
        ]
        // the game folder linked to a Mac folder (tools/ios_sim_link_game.sh): leave its saves
        if (try? fm.destinationOfSymbolicLink(atPath: paths.game.path)) == nil {
            links.insert((paths.game.appendingPathComponent("save", isDirectory: true),
                          documents.appendingPathComponent(saves, isDirectory: true)), at: 0)
        }
        for link in links { place(link.at, in: link.to) }
    }

    /// Makes `at` a link to `target`, moving anything already in a real folder at `at` into it.
    static func place(_ at: URL, in target: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        // relative, so it survives iOS moving the app's container (an update, a restore)
        let relative = relativePath(from: at.deletingLastPathComponent(), to: target)
        if let dest = try? fm.destinationOfSymbolicLink(atPath: at.path) {
            if dest == relative { return }
            try? fm.removeItem(at: at)                        // an old or absolute link
        } else {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: at.path, isDirectory: &isDir), isDir.boolValue {
                for name in (try? fm.contentsOfDirectory(atPath: at.path)) ?? [] {
                    let from = at.appendingPathComponent(name)
                    var to = target.appendingPathComponent(name)
                    if fm.fileExists(atPath: to.path) {         // keep both
                        to = target.appendingPathComponent("\((name as NSString).deletingPathExtension) (moved)"
                            + ((name as NSString).pathExtension.isEmpty ? "" : ".\((name as NSString).pathExtension)"))
                    }
                    try? fm.moveItem(at: from, to: to)
                }
                guard ((try? fm.contentsOfDirectory(atPath: at.path)) ?? []).isEmpty else { return }
                try? fm.removeItem(at: at)
            }
        }
        try? fm.createDirectory(at: at.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: at.path, withDestinationPath: relative)
    }

    /// "../../Documents/Mods" from a folder to a path in the same container.
    static func relativePath(from dir: URL, to target: URL) -> String {
        let a = dir.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let b = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < min(a.count, b.count), a[common] == b[common] { common += 1 }
        let up = Array(repeating: "..", count: a.count - common)
        return (up + b[common...]).joined(separator: "/")
    }
}

/// The game's files in the app (AppPaths.game), as the Android launcher keeps them: the 2026
/// Steam release's `ff7/resources/ff7_1.02/ff7_en` as `ff7_en.exe`, and its
/// `ff7/workingdir/data` (English, French, German and Spanish). They come from Steam
/// (SteamDownload) or from a copy of the install folder (importFolder). FFNx's own files
/// (settings and Metal shaders) come with the app and are copied in before each game.
struct GameFiles {
    /// SHA-1 of the Steam release's ff7/resources/ff7_1.02/ff7_en (1.02 US): the exe the game
    /// is built from (GameBuild.EXE_SHA1 in the Android launcher).
    static let exeSHA1 = "ac306ae92615af75ff36bba6347c67ca1284151d"
    static let languages = ["en", "fr", "de", "es"]

    enum State: Equatable {
        case missing
        /// The exe is there but is not the 1.02 US build (SHA-1 prefix).
        case wrongExe(String)
        case ready
    }

    struct ImportError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let whichFolder = "Pick the main FINAL FANTASY VII folder as Steam installs it today (\"FINAL FANTASY VII Steam Edition\", the one with ff7 inside), not ff7/workingdir. No patch or older version is needed; patched game files are not supported."

    let dir: URL
    private var fm: FileManager { .default }

    init(paths: AppPaths = .standard) { dir = paths.game }

    var exe: URL { dir.appendingPathComponent("ff7_en.exe") }
    var data: URL { dir.appendingPathComponent("data", isDirectory: true) }

    /// The game files built into the app by the Mac builder (FF7Recomp Builder: Resources/game,
    /// with ff7_en.exe and data/), or nil when they come from Find my FF7 folder.
    static var bundledGame: URL? {
        guard let url = Bundle.main.url(forResource: "game", withExtension: nil),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("ff7_en.exe").path)
        else { return nil }
        return url
    }

    /// Points the game folder at the game files inside the app: ff7_en.exe and data/ as links
    /// (the app bundle is read-only and moves when the app is updated, so this runs every
    /// launch); the folder itself stays writable for the engine's logs, saves and FFNx's files.
    func useBundledGame() {
        guard let src = Self.bundledGame else { return }
        if let link = try? fm.destinationOfSymbolicLink(atPath: dir.path), !link.isEmpty {
            try? fm.removeItem(at: dir)                 // a dev link (tools/ios_sim_link_game.sh)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["ff7_en.exe", "data"] {
            let at = dir.appendingPathComponent(name), to = src.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: at.path)) == to.path { continue }
            try? fm.removeItem(at: at)
            try? fm.createSymbolicLink(at: at, withDestinationURL: to)
        }
    }

    func state() -> State {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: exe.path),
              fm.fileExists(atPath: data.appendingPathComponent("field").path, isDirectory: &isDir), isDir.boolValue
        else { return .missing }
        guard let sha = try? Self.sha1(of: exe) else { return .missing }
        return sha == Self.exeSHA1 ? .ready : .wrongExe(String(sha.prefix(12)))
    }

    // MARK: Import from a folder

    /// Copies the game from a FINAL FANTASY VII install folder (from the phone, an SD card, a
    /// USB drive or iCloud Drive). Files already here with the same size are kept, so an import
    /// that stopped goes on where it was. Blocking: call off the main actor.
    func importFolder(_ picked: URL, progress: @escaping (String, Double) -> Void,
                      cancelled: @escaping () -> Bool) throws {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }

        progress("Looking at the folder", 0)
        let install = try Self.installRoot(in: picked)
        let srcExe = install.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en")
        let srcData = install.appendingPathComponent("ff7/workingdir/data", isDirectory: true)

        let sha = try Self.sha1(of: srcExe)
        guard sha == Self.exeSHA1 else {
            throw ImportError("This folder's ff7_en (SHA-1 \(sha.prefix(12))…) is not the 1.02 US build FF7Recomp is made from. " + Self.whichFolder)
        }

        // what to copy: the exe, and data/ without the languages the game does not use here
        var items: [(from: URL, to: URL, size: Int64)] = [(srcExe, exe, Self.size(of: srcExe))]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walk = fm.enumerator(at: srcData, includingPropertiesForKeys: keys) else {
            throw ImportError("Cannot read \(srcData.path).")
        }
        let base = srcData.standardizedFileURL.path
        for case let url as URL in walk {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if let lang = Self.languageFolder(rel), !Self.languages.contains(lang) { continue }
            items.append((url, data.appendingPathComponent(rel), Int64(values.fileSize ?? 0)))
        }

        let total = max(1, items.reduce(Int64(0)) { $0 + $1.size })
        var done: Int64 = 0
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let link = try? fm.destinationOfSymbolicLink(atPath: data.path), !link.isEmpty {
            try fm.removeItem(at: data)          // a dev link (tools/ios_sim_link_game.sh)
        }
        for item in items {
            if cancelled() { throw CancellationError() }
            if Self.size(of: item.to) != item.size || item.to == exe {
                try fm.createDirectory(at: item.to.deletingLastPathComponent(), withIntermediateDirectories: true)
                let part = item.to.appendingPathExtension("part")
                try? fm.removeItem(at: part)
                try fm.copyItem(at: item.from, to: part)
                try? fm.removeItem(at: item.to)
                try fm.moveItem(at: part, to: item.to)
            }
            done += item.size
            progress("Copying the game files", Double(done) / Double(total))
        }
        fixFontWidths()
        try? JSONSerialization.data(withJSONObject: ["release": "steam-2026", "steam_appid": 3837340, "from": "folder"])
            .write(to: dir.appendingPathComponent("source.json"))
    }

    /// The install folder in what was picked: the main folder (with ff7 inside) or ff7 itself.
    static func installRoot(in picked: URL) throws -> URL {
        let fm = FileManager.default
        func has(_ base: URL) -> Bool {
            fm.fileExists(atPath: base.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path)
                && fm.fileExists(atPath: base.appendingPathComponent("ff7/workingdir/data/field").path)
        }
        if has(picked) { return picked }
        if picked.lastPathComponent.lowercased() == "ff7", has(picked.deletingLastPathComponent()) {
            return picked.deletingLastPathComponent()
        }
        throw ImportError("That folder does not hold the game. " + whichFolder)
    }

    /// "lang-xx/..." -> "xx"
    static func languageFolder(_ rel: String) -> String? {
        let first = rel.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return first.lowercased().hasPrefix("lang-") ? String(first.dropFirst(5)).lowercased() : nil
    }

    func remove() throws {
        if fm.fileExists(atPath: dir.path) || (try? fm.destinationOfSymbolicLink(atPath: dir.path)) != nil {
            try fm.removeItem(at: dir)
        }
    }

    // MARK: FFNx's files

    /// Copies FFNx's run-time files that come with the app (Resources/ffnx: the Metal shaders
    /// and FFNx's .toml settings, staged by the Mac build) into the game folder: the shaders
    /// every time (they belong to this build of the engine), the settings only when missing.
    func installRuntime(from bundle: Bundle = .main) {
        guard let src = bundle.url(forResource: "ffnx", withExtension: nil) else { return }
        guard let names = try? fm.contentsOfDirectory(atPath: src.path) else { return }
        for name in names {
            let from = src.appendingPathComponent(name), to = dir.appendingPathComponent(name)
            if name == "shaders" {
                try? fm.removeItem(at: to)
                try? fm.copyItem(at: from, to: to)
            } else if !fm.fileExists(atPath: to.path) {
                try? fm.copyItem(at: from, to: to)
            }
        }
    }

    /// Sets `ff7_fps_limiter` in the game folder's FFNx.toml (FFNx reads it when the game starts).
    func setFrameRate(_ rate: FrameRate) {
        let url = dir.appendingPathComponent("FFNx.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        var found = false
        for i in lines.indices where lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("ff7_fps_limiter") {
            lines[i] = "ff7_fps_limiter = \(rate.rawValue)"
            found = true
        }
        if !found { lines.append("ff7_fps_limiter = \(rate.rawValue)") }
        let out = lines.joined(separator: "\n")
        if out != text { try? out.write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: Dialog font widths

    /// The current Steam release's kernel/window.bin (English, French, German, Spanish) gives
    /// M, W, m and w a width of 8 pixels where the font draws them 11 wide, so dialog runs them
    /// into the next letter ("C'mon newcom≡r"). Sets them back to 11 (tools/fix_font_widths.py,
    /// fixFontWidths() in the Android installer). Idempotent.
    func fixFontWidths() {
        for lang in Self.languages {
            let url = data.appendingPathComponent("lang-\(lang)/kernel/window.bin")
            guard let bytes = try? Data(contentsOf: url), let fixed = Self.patchWindowBin(bytes) else { continue }
            try? fixed.write(to: url, options: .atomic)
        }
    }

    /// The patched window.bin, or nil when nothing needs to change. Sections: u16 compressed
    /// size, u16 size, u16 type, then gzip data; the widths are the third section.
    static func patchWindowBin(_ data: Data) -> Data? {
        let b = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 }
        var at = 0
        for _ in 0..<2 {
            guard at + 6 <= b.count else { return nil }
            at += 6 + u16(at)
        }
        guard at + 6 <= b.count else { return nil }
        let csize = u16(at)
        guard at + 6 + csize <= b.count, var widths = gunzip(Array(b[(at + 6)..<(at + 6 + csize)])) else { return nil }
        let wide = [0x2D, 0x37, 0x4D, 0x57]          // M, W, m, w (FF7 text codes)
        guard let maxWide = wide.max(), maxWide < widths.count else { return nil }
        var changed = false
        for c in wide where widths[c] & 31 == 8 {
            widths[c] = (widths[c] & 0xE0) | 11
            changed = true
        }
        guard changed, let packed = gzip(widths), packed.count <= 0xFFFF else { return nil }
        var out = Array(b[0..<at])
        out += [UInt8(packed.count & 0xFF), UInt8(packed.count >> 8)]
        out += b[(at + 2)..<(at + 6)]
        out += packed
        out += b[(at + 6 + csize)...]
        return Data(out)
    }

    static func gunzip(_ input: [UInt8]) -> [UInt8]? {
        var stream = z_stream()
        guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var out = [UInt8]()
        var inBuf = input
        var chunk = [UInt8](repeating: 0, count: 4096)
        var status: Int32 = Z_OK
        inBuf.withUnsafeMutableBufferPointer { inPtr in
            stream.next_in = inPtr.baseAddress
            stream.avail_in = uInt(inPtr.count)
            repeat {
                chunk.withUnsafeMutableBufferPointer { c in
                    stream.next_out = c.baseAddress
                    stream.avail_out = uInt(c.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    out += c[0..<(c.count - Int(stream.avail_out))]
                }
            } while status == Z_OK
        }
        return status == Z_STREAM_END ? out : nil
    }

    /// gzip at level 9 with a zero mtime, as Python's gzip.compress(..., mtime=0).
    static func gzip(_ input: [UInt8]) -> [UInt8]? {
        var stream = z_stream()
        guard deflateInit2_(&stream, 9, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        var inBuf = input
        var out = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 32)
        var status: Int32 = Z_OK
        var produced = 0
        inBuf.withUnsafeMutableBufferPointer { inPtr in
            out.withUnsafeMutableBufferPointer { outPtr in
                stream.next_in = inPtr.baseAddress
                stream.avail_in = uInt(inPtr.count)
                stream.next_out = outPtr.baseAddress
                stream.avail_out = uInt(outPtr.count)
                status = deflate(&stream, Z_FINISH)
                produced = outPtr.count - Int(stream.avail_out)
            }
        }
        return status == Z_STREAM_END ? Array(out[0..<produced]) : nil
    }

    // MARK: Helpers

    static func sha1(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
    }
}
