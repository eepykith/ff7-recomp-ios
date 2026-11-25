import Foundation

enum ModDownloadError: LocalizedError, Equatable {
    case message(String)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .cancelled: return "Cancelled."
        }
    }
}

/// Downloads a catalog mod into the mods folder, as 7th Heaven's catalog installs do
/// (AppCore/Install.cs, FileDownloadTask.cs). Mirrors the Android launcher's `ModDownloader.java`.
///
/// Links (7th Heaven's LocationType): iros://Url/https$host/path (plain HTTP(S), `$` = "://"),
/// iros://GDrive/<file id> (Google Drive, through its "can't scan for viruses" page),
/// iros://ExternalUrl/… (a web page: opened in Safari), plain http(s). A mod's links are
/// alternatives, tried in order. Downloads resume (`<root>/downloads/<id>.part`, HTTP Range)
/// and are checked against the free space first.
///
/// The download is recognised by its first bytes: an IRO ("IROS") is the mod; a .zip or .7z is
/// unpacked (src/ios_mods) and the .iro inside it, or else the folder with mod.xml (or the
/// whole archive), is the mod. RAR is reported as not supported.
final class ModDownloader: @unchecked Sendable {
    typealias Progress = @Sendable (_ phase: String, _ done: Int64, _ total: Int64) -> Void

    let modsDir: URL
    let downloads: URL
    private let cancelFlag = CancelFlag()

    init(paths: AppPaths) {
        modsDir = paths.mods
        downloads = paths.root.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    }

    // MARK: Links

    /// iros:// links to fetchable URLs (nil: needs a browser).
    static func resolve(_ link: String) -> String? {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = l.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return l.replacingOccurrences(of: " ", with: "%20") }
        if lower.hasPrefix("iros://url/") {
            let rest = String(l.dropFirst("iros://url/".count))
            let rl = rest.lowercased()
            var u: String
            if rl.hasPrefix("http://") || rl.hasPrefix("https://") {
                u = rest
            } else if rl.hasPrefix("http$") || rl.hasPrefix("https$"), let d = rest.firstIndex(of: "$") {
                u = rest[..<d] + "://" + rest[rest.index(after: d)...]
            } else {
                u = "https://" + rest
            }
            // catalog URLs can hold raw spaces and brackets
            return u.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "[", with: "%5B")
                .replacingOccurrences(of: "]", with: "%5D").replacingOccurrences(of: "&amp;", with: "&")
        }
        if lower.hasPrefix("iros://gdrive/") {
            let id = l.dropFirst("iros://gdrive/".count)
            return "https://docs.google.com/uc?id=\(id)&export=download"
        }
        return nil                                       // ExternalUrl, MegaSharedFolder, …
    }

    /// The web page for a link that needs a browser (ExternalUrl), or nil.
    static func browserURL(_ link: String) -> URL? {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard l.lowercased().hasPrefix("iros://externalurl/") else { return nil }
        let rest = String(l.dropFirst("iros://externalurl/".count))
        let rl = rest.lowercased()
        if (rl.hasPrefix("http$") || rl.hasPrefix("https$")), let d = rest.firstIndex(of: "$") {
            return URL(string: rest[..<d] + "://" + rest[rest.index(after: d)...])
        }
        return URL(string: rest)
    }

    static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let t = String(s.unicodeScalars.map { bad.contains($0) ? "_" : Character($0) }).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "mod" : String(t.prefix(80))
    }

    private static func host(_ link: String) -> String {
        let l = link.lowercased()
        if l.contains("mega") { return "Mega" }
        if l.hasPrefix("iros://"), let slash = l.dropFirst(7).firstIndex(of: "/") { return String(l[l.index(l.startIndex, offsetBy: 7)..<slash]) }
        return "a web page"
    }

    // MARK: Install

    /// Stop the running download or unpack (from any thread).
    func cancel() {
        cancelFlag.set()
        ff7_unzip_cancel()
        ff7_un7z_cancel()
    }

    /// Download the first link that works and install it as `baseName` (no extension).
    /// Returns the mod's name in the mods folder.
    func install(id: String, baseName: String, links: [String], expectedSize: Int64, progress: @escaping Progress) async throws -> String {
        cancelFlag.reset()
        let free = Self.freeSpace(at: modsDir)
        if expectedSize > 0, free > 0, free < expectedSize * 2 + (64 << 20) {
            throw ModDownloadError.message("Not enough free space: it needs about \(ByteFormat.human(expectedSize * 2)), \(ByteFormat.human(free)) is free.")
        }
        var lastError: Error = ModDownloadError.message("No usable download link.")
        for link in links {
            guard let s = Self.resolve(link), let url = URL(string: s) else {
                lastError = ModDownloadError.message("This mod's download needs a browser (\(Self.host(link))).")
                continue
            }
            let part = downloads.appendingPathComponent(Self.safe(id) + ".part")
            do {
                let name = try await fetch(url, to: part, progress: progress)
                progress("Installing", 0, 0)
                let file = try place(part, serverName: name, baseName: baseName, progress: progress)
                try? FileManager.default.removeItem(at: part)
                return file
            } catch {
                if cancelFlag.isSet { try? FileManager.default.removeItem(at: part); throw ModDownloadError.cancelled }
                lastError = error
            }
        }
        throw lastError
    }

    /// Drop a mod's partial download (a cancelled or abandoned install).
    func discard(id: String) {
        try? FileManager.default.removeItem(at: downloads.appendingPathComponent(Self.safe(id) + ".part"))
    }

    /// At start-up: unpack folders left by an install that did not finish, and partial
    /// downloads of mods no longer queued, take space for nothing. Returns the bytes freed.
    @discardableResult
    func sweep(keeping queuedIDs: Set<String>) -> Int64 {
        let fm = FileManager.default
        let keep = Set(queuedIDs.map { Self.safe($0) + ".part" })
        var freed: Int64 = 0
        for name in (try? fm.contentsOfDirectory(atPath: downloads.path)) ?? [] {
            let stale = name.hasSuffix(".unpack") || (name.hasSuffix(".part") && !keep.contains(name))
            guard stale else { continue }
            let u = downloads.appendingPathComponent(name)
            freed += Self.size(of: u)
            try? fm.removeItem(at: u)
        }
        return freed
    }

    static func freeSpace(at url: URL) -> Int64 {
        let v = try? url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0 }
        var n: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e { n += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return n
    }

    // MARK: HTTP

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.httpAdditionalHeaders = ["User-Agent": "FF7Recomp-Launcher"]
        return URLSession(configuration: c)
    }()

    /// A small file (a catalog).
    static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let h = response as? HTTPURLResponse, h.statusCode != 200 {
            throw ModDownloadError.message("HTTP \(h.statusCode)")
        }
        return data
    }

    /// Fetch url into part (resuming what is there); returns the server's file name.
    private func fetch(_ start: URL, to part: URL, progress: @escaping Progress) async throws -> String {
        var url = start
        var name: String?
        for _ in 0..<6 {
            let have = Self.size(of: part)
            let r = try await StreamingFetch(url: url, to: part, from: have, cancel: cancelFlag, progress: progress).run()
            if r.status == 416 { return name ?? Self.guessName(url) }          // already complete
            if name == nil { name = r.fileName ?? Self.guessName(r.finalURL ?? url) }
            if let html = r.html {
                // Google Drive's "can't scan this file for viruses" page: follow its download form
                if html.contains("Quota exceeded") {
                    throw ModDownloadError.message("Google Drive: this file's download quota is used up for today; try again later.")
                }
                guard let next = Self.driveConfirm(html, page: r.finalURL ?? url) else {
                    throw ModDownloadError.message(url.host?.contains("google") == true
                        ? "Google Drive did not offer the file (its sharing settings)."
                        : "The download link gave a web page, not the mod.")
                }
                url = next
                name = nil
                try? FileManager.default.removeItem(at: part)
                continue
            }
            if r.complete { return name ?? Self.guessName(url) }
            // cut off: go round again and resume
        }
        throw ModDownloadError.message("The download kept stopping; try again to resume.")
    }

    /// The download URL behind Google Drive's virus-scan warning page: its form (newer pages),
    /// or the page's own URL plus the confirm/uuid fields (as 7th Heaven does).
    static func driveConfirm(_ html: String, page: URL) -> URL? {
        func groups(_ pattern: String, _ s: String) -> [[String]] {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
                (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
            }
        }
        let base = groups("<form[^>]*id=\"download-form\"[^>]*action=\"([^\"]+)\"", html).first?.first?
            .replacingOccurrences(of: "&amp;", with: "&")
        var query: [String] = []
        var confirm = false
        for g in groups("<input[^>]*name=\"([^\"]+)\"[^>]*value=\"([^\"]*)\"", html) {
            if base == nil, g[0] != "confirm", g[0] != "uuid" { continue }
            if g[0] == "confirm" { confirm = true }
            query.append("\(g[0])=\(g[1])")
        }
        if let base {
            return URL(string: base + (base.contains("?") ? "&" : "?") + query.joined(separator: "&"))
        }
        if confirm { return URL(string: page.absoluteString + "&" + query.joined(separator: "&")) }
        if let href = groups("href=\"(/uc\\?export=download[^\"]+)\"", html).first?.first {
            return URL(string: "https://drive.google.com" + href.replacingOccurrences(of: "&amp;", with: "&"))
        }
        return nil
    }

    static func guessName(_ url: URL) -> String {
        let n = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return n.isEmpty || n == "/" ? "mod" : n
    }

    // MARK: Into the mods folder

    /// Move the download into the mods folder (unpacking archives). Returns the mod's name there.
    private func place(_ part: URL, serverName: String, baseName: String, progress: @escaping Progress) throws -> String {
        let base = Self.safe(baseName)
        let sig = (try? FileHandle(forReadingFrom: part)).flatMap { h -> Data? in defer { try? h.close() }; return try? h.read(upToCount: 6) } ?? Data()
        guard sig.count >= 4 else { throw ModDownloadError.message("The download is empty.") }
        let b = [UInt8](sig)
        if b[0] == 0x49, b[1] == 0x52, b[2] == 0x4F, b[3] == 0x53 { return try placeIRO(part, base: base) }   // IROS
        let zip = b[0] == 0x50 && b[1] == 0x4B && b[2] == 3 && b[3] == 4
        let sevenZ = b[0] == 0x37 && b[1] == 0x7A && b[2] == 0xBC && b[3] == 0xAF
        if b[0] == 0x52, b[1] == 0x61, b[2] == 0x72, b[3] == 0x21 {
            throw ModDownloadError.message("\(serverName): RAR archives are not supported yet.")
        }
        guard zip || sevenZ else {
            let head = String(decoding: sig, as: UTF8.self).lowercased()
            if head.hasPrefix("<!doc") || head.hasPrefix("<html") { throw ModDownloadError.message("The download link gave a web page, not the mod.") }
            throw ModDownloadError.message("\(serverName): not an .iro, .zip or .7z file.")
        }
        let fm = FileManager.default
        let tmp = downloads.appendingPathComponent(base + ".unpack", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }                  // a half-unpacked mod can be gigabytes
        try unpack(part, into: tmp, sevenZ: sevenZ, progress: progress)

        if let iro = Self.findFirst(in: tmp, where: { $0.pathExtension.lowercased() == "iro" }) {
            return try placeIRO(iro, base: base)
        }
        let root: URL
        if let xml = Self.findFirst(in: tmp, where: { $0.lastPathComponent.lowercased() == "mod.xml" }) {
            root = xml.deletingLastPathComponent()
        } else {
            let kids = (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            root = kids.count == 1 && (try? kids[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? kids[0] : tmp
        }
        let dst = modsDir.appendingPathComponent(base, isDirectory: true)
        try fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try fm.moveItem(at: root, to: dst)
        return dst.lastPathComponent
    }

    private func unpack(_ archive: URL, into dir: URL, sevenZ: Bool, progress: @escaping Progress) throws {
        let done = CancelFlag()
        let poll = Thread {
            while !done.isSet {
                Thread.sleep(forTimeInterval: 0.5)
                var d: UInt64 = 0, t: UInt64 = 0
                if sevenZ { ff7_un7z_progress(&d, &t) } else { ff7_unzip_progress(&d, &t) }
                if t > 0, !done.isSet { progress("Installing", Int64(d), Int64(t)) }
            }
        }
        poll.start()
        defer { done.set() }
        var err = [CChar](repeating: 0, count: 512)
        let rc = archive.path.withCString { a in
            dir.path.withCString { o in
                sevenZ ? ff7_un7z(a, o, &err, err.count) : ff7_unzip(a, o, &err, err.count)
            }
        }
        if cancelFlag.isSet { throw ModDownloadError.cancelled }
        if rc != 0 { throw ModDownloadError.message(String(cString: err)) }
    }

    private func placeIRO(_ src: URL, base: String) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
        let dst = modsDir.appendingPathComponent(base + ".iro")
        if fm.fileExists(atPath: dst.path) {
            _ = try fm.replaceItemAt(dst, withItemAt: src)
        } else {
            try fm.moveItem(at: src, to: dst)
        }
        return dst.lastPathComponent
    }

    private static func findFirst(in dir: URL, where match: (URL) -> Bool) -> URL? {
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        let sorted = kids.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for k in sorted where (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true && match(k) { return k }
        for k in sorted where (try? k.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let x = findFirst(in: k, where: match) { return x }
        }
        return nil
    }
}

/// One HTTP request streamed into a file (appending from `from` with a Range request), with
/// progress. An HTML answer is returned as text instead (Google Drive's warning page).
private final class StreamingFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result {
        var status: Int
        var fileName: String?
        var finalURL: URL?
        var html: String?
        var complete: Bool
    }

    private let url: URL
    private let part: URL
    private let from: Int64
    private let cancel: CancelFlag
    private let progress: ModDownloader.Progress
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Result, Error>?
    private var result = Result(status: 0, complete: false)
    private var total: Int64 = -1
    private var done: Int64 = 0
    private var lastShown: Int64 = 0
    private var html: Data?
    private var writeError: Error?

    init(url: URL, to part: URL, from: Int64, cancel: CancelFlag, progress: @escaping ModDownloader.Progress) {
        self.url = url
        self.part = part
        self.from = from
        self.cancel = cancel
        self.progress = progress
    }

    func run() async throws -> Result {
        var request = URLRequest(url: url)
        request.setValue("FF7Recomp-Launcher", forHTTPHeaderField: "User-Agent")
        if from > 0 { request.setValue("bytes=\(from)-", forHTTPHeaderField: "Range") }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { c in
            continuation = c
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let h = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        result.status = h.statusCode
        result.finalURL = h.url
        if h.statusCode == 416 { completionHandler(.cancel); return }
        guard h.statusCode == 200 || h.statusCode == 206 else {
            writeError = ModDownloadError.message("The download failed: HTTP \(h.statusCode).")
            completionHandler(.cancel)
            return
        }
        if let d = h.value(forHTTPHeaderField: "Content-Disposition") { result.fileName = Self.fileName(d) }
        if (h.mimeType ?? "").lowercased() == "text/html" {
            html = Data()
            completionHandler(.allow)
            return
        }
        let append = h.statusCode == 206 && from > 0
        let length = h.expectedContentLength
        total = length > 0 ? length + (append ? from : 0) : -1
        done = append ? from : 0
        do {
            if !append || !FileManager.default.fileExists(atPath: part.path) {
                FileManager.default.createFile(atPath: part.path, contents: nil)
                try FileHandle(forWritingTo: part).truncate(atOffset: 0)
            }
            let fh = try FileHandle(forWritingTo: part)
            try fh.seekToEnd()
            handle = fh
            completionHandler(.allow)
        } catch {
            writeError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if cancel.isSet { dataTask.cancel(); return }
        if html != nil {
            html?.append(data)
            if (html?.count ?? 0) > (4 << 20) { dataTask.cancel() }
            return
        }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            writeError = ModDownloadError.message("Could not save the download (is the phone full?).")
            dataTask.cancel()
            return
        }
        done += Int64(data.count)
        if done - lastShown > (1 << 20) {
            lastShown = done
            progress("Downloading", done, total)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        handle = nil
        if cancel.isSet { continuation?.resume(throwing: ModDownloadError.cancelled); continuation = nil; return }
        if let writeError { continuation?.resume(throwing: writeError); continuation = nil; return }
        if result.status == 416 { continuation?.resume(returning: result); continuation = nil; return }
        if let html {
            result.html = String(decoding: html, as: UTF8.self)
            continuation?.resume(returning: result)
            continuation = nil
            return
        }
        if let error {
            // a dropped connection: report what is there, the caller resumes
            if (error as NSError).domain == NSURLErrorDomain, done > from {
                result.complete = false
                continuation?.resume(returning: result)
            } else {
                continuation?.resume(throwing: ModDownloadError.message("The download failed: \(error.localizedDescription)"))
            }
            continuation = nil
            return
        }
        result.complete = total <= 0 || done >= total
        progress("Downloading", done, total)
        continuation?.resume(returning: result)
        continuation = nil
    }

    static func fileName(_ disposition: String) -> String? {
        if let r = disposition.range(of: "filename\\*=UTF-8''([^;]+)", options: [.regularExpression, .caseInsensitive]) {
            let v = disposition[r].replacingOccurrences(of: "filename*=UTF-8''", with: "", options: .caseInsensitive)
            return v.removingPercentEncoding ?? v
        }
        if let r = disposition.range(of: "filename=\"?[^\";]+\"?", options: [.regularExpression, .caseInsensitive]) {
            return disposition[r].replacingOccurrences(of: "filename=", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return nil
    }
}
