import Foundation

/// 7th Heaven's mod catalogs: subscriptions, the merged list of catalog mods, and which of them
/// are installed at which version (for "update available").
///
/// Catalog XML (7th Heaven's AppCore/Catalog.cs, Mod.cs, ModVersion.cs): Catalog > Mods > Mod
/// with ID (GUID), Name, Author, Category, Description, Link (info page), Tags/string,
/// Requirement (ModID, Description), MetaVersion, and LatestVersion with repeated Link
/// (download alternatives), Version, ReleaseDate, ReleaseNotes, PreviewImage, DownloadSize (KB).
/// Catalogs are downloaded again after a day (as 7th Heaven does) or on request, cached in
/// `<root>/catalogs`, and merged by ID (the higher version wins).
struct CatalogMod: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var author = ""
    var category = ""
    var description = ""
    var infoLink = ""
    var catalog = ""
    var tags: [String] = []
    var links: [String] = []
    var requirements: [(id: String, description: String)] = []
    var versionText = ""
    var version: Double = 0
    var releaseDate = ""
    var releaseNotes = ""
    var preview = ""
    var sizeKB: Int64 = 0
    var metaVersion: Double = 0

    var key: String { id.lowercased() }
    var sizeText: String { sizeKB > 0 ? ByteFormat.human(sizeKB * 1024) : "" }
    /// None of its links downloads directly (Mega, a web page): it needs a browser.
    var needsBrowser: Bool { !links.contains { ModDownloader.resolve($0) != nil } }
    var browserLink: URL? {
        for l in links { if let u = ModDownloader.browserURL(l) { return u } }
        return URL(string: infoLink)
    }

    static func == (a: CatalogMod, b: CatalogMod) -> Bool {
        a.id == b.id && a.versionText == b.versionText && a.catalog == b.catalog
    }
}

enum ByteFormat {
    static func human(_ bytes: Int64) -> String {
        if bytes >= 1 << 30 { return String(format: "%.1f GB", Double(bytes) / Double(1 << 30)) }
        if bytes >= 1 << 20 { return String(format: "%.0f MB", Double(bytes) / Double(1 << 20)) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

final class ModCatalog: @unchecked Sendable {
    struct Subscription: Codable, Equatable, Identifiable {
        var name: String
        var url: String
        var lastCheck: Date?
        var error: String?
        var count = 0
        var id: String { name.lowercased() }
    }

    struct Installed: Codable, Equatable {
        var id: String
        var file: String
        var version: String
        var name: String
        var versionNumber: Double { ModCatalog.number(version) }
    }

    static let defaults: [(name: String, url: String)] = [
        ("Qhimm Catalog", "iros://Url/https$github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/qhimm.xml"),
        ("Sega Catalog", "iros://Url/https$github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/sega.xml"),
    ]

    /// 7th Heaven's categories in its load order (AppCore/ModLoadOrder.cs): a new mod goes
    /// after the mods of its own and earlier categories.
    static let categories = [
        "Miscellaneous", "Animations", "Battle Models", "Battle Textures", "Field Models", "Field Textures", "Gameplay",
        "Media", "Minigames", "Spell Textures", "User Interface", "World Models", "World Textures", "Shaders",
    ]

    let dir: URL
    private let installedFile: URL
    private let lock = NSLock()
    private var _subs: [Subscription] = []
    private var _mods: [CatalogMod] = []
    private var _installed: [String: Installed] = [:]

    var subscriptions: [Subscription] { lock.withLock { _subs } }
    var mods: [CatalogMod] { lock.withLock { _mods } }
    var installed: [String: Installed] { lock.withLock { _installed } }

    init(paths: AppPaths) {
        dir = paths.root.appendingPathComponent("catalogs", isDirectory: true)
        installedFile = paths.mods.appendingPathComponent("catalog_installed.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadSubs()
        loadInstalled()
        rebuild()
    }

    // MARK: Subscriptions

    private var subsFile: URL { dir.appendingPathComponent("subscriptions.json") }

    private func loadSubs() {
        var subs = (try? Data(contentsOf: subsFile)).flatMap { try? JSONDecoder().decode([Subscription].self, from: $0) } ?? []
        // the defaults are always there, at their built-in address (as 7th Heaven does)
        for d in Self.defaults {
            if let i = subs.firstIndex(where: { $0.name.caseInsensitiveCompare(d.name) == .orderedSame }) {
                subs[i].url = d.url
            } else {
                subs.append(Subscription(name: d.name, url: d.url))
            }
        }
        lock.withLock { _subs = subs }
    }

    private func saveSubs() {
        let subs = subscriptions
        if let data = try? JSONEncoder().encode(subs) { try? data.write(to: subsFile, options: .atomic) }
    }

    func isDefault(_ s: Subscription) -> Bool {
        Self.defaults.contains { $0.name.caseInsensitiveCompare(s.name) == .orderedSame }
    }

    /// A catalog link someone pasted (iros:// or https). Returns the problem, or nil.
    func addSubscription(name: String, link: String) -> String? {
        guard let url = ModDownloader.resolve(link) else { return "Not a catalog link (iros://Url/… or https://…)." }
        if let had = subscriptions.first(where: { ModDownloader.resolve($0.url) == url }) {
            return "Already subscribed: \(had.name)."
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let s = Subscription(name: trimmed.isEmpty ? (URL(string: url)?.host ?? "Catalog") : trimmed,
                             url: link.trimmingCharacters(in: .whitespaces))
        lock.withLock { _subs.append(s) }
        saveSubs()
        return nil
    }

    func removeSubscription(_ s: Subscription) {
        guard !isDefault(s) else { return }
        lock.withLock { _subs.removeAll { $0.id == s.id } }
        try? FileManager.default.removeItem(at: cacheFile(s))
        saveSubs()
        rebuild()
    }

    // MARK: Refresh and parse

    private func cacheFile(_ s: Subscription) -> URL {
        dir.appendingPathComponent(ModDownloader.safe(s.name).replacingOccurrences(of: " ", with: "_") + ".xml")
    }

    /// Download catalogs older than a day (or all, if forced), then rebuild the list.
    /// Returns a summary of problems, or nil.
    func refresh(force: Bool) async -> String? {
        var problems: [String] = []
        let now = Date()
        for s in subscriptions {
            let cache = cacheFile(s)
            if !force, FileManager.default.fileExists(atPath: cache.path),
               let last = s.lastCheck, now.timeIntervalSince(last) < 24 * 3600 { continue }
            var updated = s
            do {
                guard let url = ModDownloader.resolve(s.url).flatMap(URL.init(string:)) else {
                    throw ModDownloadError.message("not a downloadable link")
                }
                let xml = try await ModDownloader.get(url)
                _ = try Self.parse(xml, catalog: s.name)          // check it before replacing the cache
                try xml.write(to: cache, options: .atomic)
                updated.lastCheck = now
                updated.error = nil
            } catch {
                updated.error = error.localizedDescription
                problems.append("\(s.name): \(error.localizedDescription)")
            }
            lock.withLock {
                if let i = _subs.firstIndex(where: { $0.id == s.id }) { _subs[i] = updated }
            }
        }
        rebuild()
        saveSubs()
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    /// The merged list from the cached catalogs (no network).
    func rebuild() {
        var byID: [String: CatalogMod] = [:]
        var subs = subscriptions
        for i in subs.indices {
            guard let data = try? Data(contentsOf: cacheFile(subs[i])) else { continue }
            guard let list = try? Self.parse(data, catalog: subs[i].name) else {
                subs[i].error = "The cached catalog is unreadable."
                continue
            }
            subs[i].count = list.count
            for m in list {
                if let had = byID[m.key],
                   !(m.version > had.version || (m.version == had.version && m.metaVersion > had.metaVersion)) { continue }
                byID[m.key] = m
            }
        }
        let sorted = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lock.withLock {
            _mods = sorted
            _subs = subs
        }
    }

    static func parse(_ xml: Data, catalog: String) throws -> [CatalogMod] {
        let delegate = CatalogParser(catalog: catalog)
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.sawCatalog else {
            throw ModDownloadError.message(delegate.sawCatalog ? "the catalog is damaged" : "not a 7th Heaven catalog")
        }
        return delegate.mods
    }

    static func number(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: Installed

    private func loadInstalled() {
        let map = (try? Data(contentsOf: installedFile))
            .flatMap { try? JSONDecoder().decode([String: Installed].self, from: $0) } ?? [:]
        var byKey: [String: Installed] = [:]
        for (k, v) in map { byKey[k.lowercased()] = v }
        lock.withLock { _installed = byKey }
    }

    private func saveInstalled() {
        let map = installed
        try? FileManager.default.createDirectory(at: installedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: installedFile, options: .atomic) }
    }

    func markInstalled(_ m: CatalogMod, file: String) {
        lock.withLock { _installed[m.key] = Installed(id: m.id, file: file, version: m.versionText, name: m.name) }
        saveInstalled()
    }

    /// Entries whose library file was deleted are dropped.
    func prune(modsDir: URL) {
        var changed = false
        lock.withLock {
            for (k, v) in _installed where !FileManager.default.fileExists(atPath: modsDir.appendingPathComponent(v.file).path) {
                _installed[k] = nil
                changed = true
            }
        }
        if changed { saveInstalled() }
    }

    func installedOf(_ m: CatalogMod) -> Installed? { installed[m.key] }

    /// The catalog entry for a library file, if it came from a catalog.
    func installedByFile(_ file: String) -> Installed? {
        installed.values.first { $0.file.caseInsensitiveCompare(file) == .orderedSame }
    }

    func byID(_ id: String) -> CatalogMod? {
        let k = id.lowercased()
        return mods.first { $0.key == k }
    }

    func updateAvailable(_ m: CatalogMod) -> Bool {
        guard let i = installedOf(m) else { return false }
        return m.version > i.versionNumber
    }

    var updates: [CatalogMod] { mods.filter(updateAvailable) }

    /// Search: every word must appear in the name, author, category, tags or description.
    func search(_ query: String, category: String?, installedOnly: Bool) -> [CatalogMod] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let inst = installed
        return mods.filter { m in
            if let category, m.category.caseInsensitiveCompare(category) != .orderedSame { return false }
            if installedOnly, inst[m.key] == nil { return false }
            let hay = ([m.name, m.author, m.category] + m.tags + [m.description]).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}

/// Reads Catalog > Mods > Mod elements (only direct children of <Mods>: a Requirement holds
/// <ModID>, not <Mod>).
private final class CatalogParser: NSObject, XMLParserDelegate {
    let catalog: String
    var mods: [CatalogMod] = []
    var sawCatalog = false
    private var stack: [String] = []
    private var text = ""
    private var mod: CatalogMod?
    private var requirement: (id: String, description: String)?

    init(catalog: String) { self.catalog = catalog }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if stack.isEmpty, name == "Catalog" { sawCatalog = true }
        if name == "Mod", stack.last == "Mods" { mod = CatalogMod(id: "", name: "", catalog: catalog) }
        if name == "Requirement", mod != nil { requirement = ("", "") }
        stack.append(name)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stack.removeLast()
        let parent = stack.last ?? ""
        if name == "Mod", parent == "Mods", var m = mod {
            if !m.id.isEmpty {
                if m.name.isEmpty { m.name = m.id }
                mods.append(m)
            }
            mod = nil
        } else if mod != nil {
            switch (parent, name) {
            case ("Mod", "ID"): mod?.id = value
            case ("Mod", "Name"): mod?.name = value
            case ("Mod", "Author"): mod?.author = value
            case ("Mod", "Category"): mod?.category = value
            case ("Mod", "Description"): mod?.description = value
            case ("Mod", "Link"): mod?.infoLink = value
            case ("Mod", "MetaVersion"): mod?.metaVersion = ModCatalog.number(value)
            case ("Tags", "string"): if !value.isEmpty { mod?.tags.append(value) }
            case ("Requirement", "ModID"): requirement?.id = value
            case ("Requirement", "Description"): requirement?.description = value
            case ("Mod", "Requirement"):
                if let r = requirement, !r.id.isEmpty { mod?.requirements.append(r) }
                requirement = nil
            case ("LatestVersion", "Link"): if !value.isEmpty { mod?.links.append(value) }
            case ("LatestVersion", "Version"):
                mod?.versionText = value
                mod?.version = ModCatalog.number(value)
            case ("LatestVersion", "ReleaseDate"): mod?.releaseDate = value
            case ("LatestVersion", "ReleaseNotes"): mod?.releaseNotes = value
            case ("LatestVersion", "PreviewImage"): mod?.preview = value
            case ("LatestVersion", "DownloadSize"): mod?.sizeKB = Int64(ModCatalog.number(value))
            default: break
            }
        }
        text = ""
    }
}
