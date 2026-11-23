import Foundation

/// Display metadata from a mod's `mod.xml` (`<ModInfo>`: ID, Name, Author, Version,
/// Category, Description). Read for folder mods only; IRO archives are read by the C++ mod
/// layer once it is bridged (P4).
struct ModInfo: Equatable {
    var id: String?
    var name: String?
    var author: String?
    var version: String?
    var category: String?
    var description: String?

    static func parse(_ data: Data) -> ModInfo? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let delegate = Delegate()
        let parser = XMLParser(data: Data(bytes))
        parser.delegate = delegate
        guard parser.parse(), delegate.sawRoot else { return nil }
        return delegate.info
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var info = ModInfo()
        var sawRoot = false
        private var depth = 0
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            if depth == 1, name == "ModInfo" { sawRoot = true }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if depth == 2 {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = value.isEmpty ? nil : value
                switch name {
                case "ID": info.id = v
                case "Name": info.name = v
                case "Author": info.author = v
                case "Version": info.version = v
                case "Category": info.category = v
                case "Description": info.description = v
                default: break
                }
            }
            text = ""
            depth -= 1
        }
    }
}

/// One mod in the library: a `.iro` archive or a folder in `AppPaths.mods`.
struct ModItem: Identifiable, Equatable {
    enum Kind: String { case iro = "IRO archive", folder = "Folder" }

    /// File or folder name inside the mods folder; also the profile's `Path`.
    var fileName: String
    var kind: Kind
    var enabled: Bool
    var options: [ModProfile.Option]
    var info: ModInfo?

    var id: String { fileName.lowercased() }
    var displayName: String {
        if let name = info?.name { return name }
        return kind == .iro ? String(fileName.dropLast(4)) : fileName
    }
}

enum ModLibraryError: Error, LocalizedError, Equatable {
    case notAMod(String)
    var errorDescription: String? {
        switch self {
        case .notAMod(let name):
            return "\(name) is not a mod. Import a 7th Heaven .iro archive or a mod folder."
        }
    }
}

/// The mods folder and its profile: scanning, importing, removing and saving the order.
/// Mirrors Android's `ModLibrary.java`.
final class ModLibrary {
    let paths: AppPaths
    private let fm = FileManager.default

    init(paths: AppPaths = .standard) {
        self.paths = paths
    }

    static func isIRO(_ name: String) -> Bool { name.lowercased().hasSuffix(".iro") }

    /// The saved profile's mods that are still present, in saved order, then any new ones
    /// found in the folder (disabled, sorted by name). Returns the profile language too.
    func load() -> (language: String?, mods: [ModItem]) {
        let profile = (try? Data(contentsOf: paths.modProfile)).flatMap { try? ModProfileXML.parse($0) }
        let present = presentEntries()
        var byKey: [String: (name: String, kind: ModItem.Kind)] = [:]
        for p in present { byKey[p.name.lowercased()] = p }

        var items: [ModItem] = []
        var used = Set<String>()
        for entry in profile?.mods ?? [] {
            let key = entry.path.lowercased()
            guard let found = byKey[key], !used.contains(key) else { continue }
            used.insert(key)
            items.append(ModItem(fileName: found.name, kind: found.kind, enabled: entry.enabled,
                                 options: entry.options, info: info(for: found.name, kind: found.kind)))
        }
        for p in present where !used.contains(p.name.lowercased()) {
            items.append(ModItem(fileName: p.name, kind: p.kind, enabled: false, options: [],
                                 info: info(for: p.name, kind: p.kind)))
        }
        return (profile?.language, items)
    }

    func save(_ mods: [ModItem], language: String) throws {
        let profile = ModProfile(
            language: language,
            mods: mods.map { .init(path: $0.fileName, enabled: $0.enabled, options: $0.options) }
        )
        try ModProfileXML.write(profile, to: paths.modProfile)
    }

    /// Copies a `.iro` file or a mod folder into the mods folder, replacing one of the same
    /// name (an update keeps its place in the profile). Returns the stored name.
    @discardableResult
    func importMod(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let name = url.lastPathComponent
        guard isDir.boolValue || Self.isIRO(name), name != "profile.xml", !name.hasPrefix(".") else {
            throw ModLibraryError.notAMod(name)
        }
        try fm.createDirectory(at: paths.mods, withIntermediateDirectories: true)
        // Same mod under different case: replace it.
        let existing = (try? fm.contentsOfDirectory(atPath: paths.mods.path)) ?? []
        for e in existing where e.lowercased() == name.lowercased() {
            try fm.removeItem(at: paths.mods.appendingPathComponent(e))
        }
        try fm.copyItem(at: url, to: paths.mods.appendingPathComponent(name))
        return name
    }

    func remove(_ fileName: String) throws {
        let url = paths.mods.appendingPathComponent(fileName)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    private func presentEntries() -> [(name: String, kind: ModItem.Kind)] {
        let names = (try? fm.contentsOfDirectory(atPath: paths.mods.path)) ?? []
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            if name.hasPrefix(".") { return nil }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: paths.mods.appendingPathComponent(name).path, isDirectory: &isDir) else { return nil }
            if isDir.boolValue { return (name, .folder) }
            return Self.isIRO(name) ? (name, .iro) : nil
        }
    }

    private func info(for name: String, kind: ModItem.Kind) -> ModInfo? {
        guard kind == .folder else { return nil }
        let dir = paths.mods.appendingPathComponent(name)
        // mod.xml's name is case-insensitive in the core (resolve_ci).
        let file = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).first { $0.lowercased() == "mod.xml" }
        guard let file, let data = fm.contents(atPath: dir.appendingPathComponent(file).path) else { return nil }
        return ModInfo.parse(data)
    }
}
