import Foundation

/// Do mods get in each other's way?
///
/// Before a download only the catalog is known (no file lists), so `beforeInstall` guesses from
/// what the mods are: the same kind of replacement (two field model packs, two soundtracks, two
/// gameplay overhauls, …), and the catalog's requirements. After a download the real answer
/// comes from `report`: the profile loaded exactly as the game loads it (src/mods,
/// ff7_mods_conflicts_json), listing the game files two enabled mods both replace (the one
/// higher in the list wins, as in the game and in 7th Heaven) and the mods' own Compatibility
/// Require/Forbid declarations.
enum ModConflicts {
    struct Warning: Identifiable, Hashable {
        let text: String
        /// Declared incompatible, missing a required mod, or two gameplay overhauls.
        let serious: Bool
        var id: String { text }
    }

    // MARK: Before downloading

    private struct Who {
        var id = "", name = "", category = ""
        var tags: [String] = []
        var needs = Set<String>()
    }

    private static func who(_ m: CatalogMod) -> Who {
        Who(id: m.key, name: m.name, category: m.category, tags: m.tags, needs: Set(m.requirements.map { $0.id.lowercased() }))
    }

    private static func who(_ m: ModItem, catalog: ModCatalog) -> Who {
        var w = Who(id: m.info?.id?.lowercased() ?? "", name: m.displayName, category: m.info?.category ?? "")
        if let inst = catalog.installedByFile(m.fileName), let cm = catalog.byID(inst.id) {
            if w.id.isEmpty { w.id = cm.key }
            if w.category.isEmpty { w.category = cm.category }
            w.tags = cm.tags
            w.needs = Set(cm.requirements.map { $0.id.lowercased() })
        }
        return w
    }

    /// What a mod replaces, as far as its category, tags and name say.
    private static func slots(_ w: Who) -> Set<String> {
        var s = Set<String>()
        let cat = w.category.lowercased()
        let k = ([w.name] + w.tags).joined(separator: " ").lowercased()
        func has(_ pattern: String) -> Bool { k.range(of: "\\b(\(pattern))\\b", options: .regularExpression) != nil }
        switch cat {
        case "gameplay": s.insert("gameplay")
        case "field models": s.insert("field models")
        case "battle models": s.insert("battle models")
        case "animations": s.insert("animations")
        case "field textures": s.insert("field textures")
        case "world textures": s.insert("world map textures")
        case "battle textures": s.insert("battle textures")
        case "spell textures": s.insert(k.contains("limit") ? "limit break effects" : "spell effects")
        case "minigames": s.insert("minigames")
        case "shaders": s.insert("shaders")
        default: break
        }
        if ["media", "miscellaneous", "user interface"].contains(cat) {
            if has("music|soundtrack|ost|arranged|remake|orchestra") { s.insert("music") }
            if has("fmv|movies?|videos?|cutscenes?") { s.insert("movies") }
            if has("voice|voices|voiced") { s.insert("voices") }
            if has("sfx|sounds?") { s.insert("sound effects") }
            if has("avatars?") { s.insert("character portraits") }
            if has("fonts?") { s.insert("the font") }
            if cat == "user interface", has("backgrounds?|menu") { s.insert("menu graphics") }
        }
        return s
    }

    /// Warnings for installing `wanted` (requirements included) next to the enabled mods. A new
    /// mod goes to the bottom of the Mods list, so where files overlap the mods already there win.
    static func beforeInstall(_ wanted: [CatalogMod], library: [ModItem], catalog: ModCatalog) -> [Warning] {
        var have = library.filter(\.enabled).map { who($0, catalog: catalog) }
        var out: [Warning] = []
        var said = Set<String>()
        for cm in wanted {
            let c = who(cm)
            if have.contains(where: { !$0.id.isEmpty && $0.id == c.id }) { continue }   // an update replaces itself
            for h in have {
                if h.needs.contains(c.id) || c.needs.contains(h.id) { continue }       // meant to go together
                for slot in slots(c).intersection(slots(h)).sorted() where said.insert(slot + h.id + c.id).inserted {
                    if slot == "gameplay" {
                        out.append(Warning(text: "\(c.name) and \(h.name) both change the game data (stats, enemies, items). Two gameplay mods usually replace the same files, so one of them will mostly not apply: use one unless \(c.name)'s page says it works with \(h.name).", serious: true))
                    } else {
                        out.append(Warning(text: "\(c.name) and \(h.name) both replace \(slot). \(c.name) goes to the bottom of your Mods list, so \(h.name)'s files win where they overlap (move \(c.name) up to prefer it).", serious: false))
                    }
                }
            }
            have.append(c)                                     // the rest of the batch sees it
        }
        return out
    }

    // MARK: After downloading: the real overlaps

    private struct Json: Decodable {
        struct Mod: Decodable { var file: String?; var id: String?; var name: String? }
        struct Area: Decodable { var area: String? }
        struct Overlap: Decodable { var winner: Int; var loser: Int; var files: Int?; var conditional: Bool?; var areas: [Area]? }
        struct Forbid: Decodable { var mod: Int; var other: Int; var why: String? }
        struct Require: Decodable { var mod: Int; var id: String?; var why: String? }
        struct Reordered: Decodable { var mod: Int; var other: Int; var below: Bool? }
        struct Setting: Decodable { var mod: Int; var option: String?; var value: String? }
        var mods: [Mod]?
        var overlaps: [Overlap]?
        var forbids: [Forbid]?
        var requires: [Require]?
        var reordered: [Reordered]?
        var settings: [Setting]?
    }

    struct Report {
        var lines: [Warning] = []
        var overlaps = 0
        var problems = 0
        /// Short notes for each mod's row, by file name (lower case).
        var perMod: [String: [String]] = [:]
        mutating func note(_ file: String, _ s: String) { perMod[file.lowercased(), default: []].append(s) }
    }

    /// Friendly names for the folders the game's files live in.
    static func area(_ a: String) -> String {
        switch a.lowercased() {
        case "char": return "field models"
        case "battle": return "battle models and data"
        case "flevel": return "field maps"
        case "field": return "field files"
        case "kernel": return "game data"
        case "vgmstream", "music": return "music"
        case "movies": return "movies"
        case "magic": return "spell effects"
        case "wm", "world": return "world map"
        case "menu": return "menus"
        case "cr": return "credits"
        case "disc": return "disc change screens"
        case "sfx": return "sound effects"
        case "voice": return "voice acting"
        case "ambient": return "ambient sound"
        case "textures": return "textures"
        case "high", "chocobo", "condor", "coaster", "snowboard", "sub", "minigame", "snowboard-us", "high-us": return "minigames"
        case "exe": return "engine data"
        case "time": return "day/night"
        case "shaders": return "shaders"
        case "(root)": return "game folder files"
        default: return a
        }
    }

    /// The enabled mods checked as the game loads them. Empty in the launcher alone (no mod
    /// layer linked).
    static func report(profile: URL, catalog: ModCatalog) -> Report {
        var r = Report()
        guard let cstr = profile.path.withCString({ ff7_ios_mods_conflicts_json($0) }) else { return r }
        let data = Data(String(cString: cstr).utf8)
        free(cstr)
        guard let j = try? JSONDecoder().decode(Json.self, from: data), let mods = j.mods else { return r }
        let file = mods.map { $0.file ?? "" }
        let name = mods.map { $0.name ?? $0.file ?? "?" }
        func ok(_ i: Int) -> Bool { i >= 0 && i < mods.count }

        for f in j.forbids ?? [] where ok(f.mod) && ok(f.other) {
            let why = f.why ?? ""
            r.lines.append(Warning(text: "\(name[f.mod]) says it does not work with \(name[f.other])\(why.isEmpty ? "." : ": \(why)")", serious: true))
            r.note(file[f.mod], "Does not work with \(name[f.other])")
            r.note(file[f.other], "\(name[f.mod]) does not work with it")
            r.problems += 1
        }
        for q in j.requires ?? [] where ok(q.mod) {
            let needName = q.id.flatMap { catalog.byID($0)?.name } ?? "another mod (\(q.id ?? "?"))"
            let why = q.why ?? ""
            r.lines.append(Warning(text: "\(name[q.mod]) needs \(needName), which is not enabled\(why.isEmpty ? "." : ": \(why)")", serious: true))
            r.note(file[q.mod], "Needs \(needName)")
            r.problems += 1
        }
        for o in j.reordered ?? [] where ok(o.mod) && ok(o.other) {
            let where_ = o.below == true ? "below" : "above"
            r.lines.append(Warning(text: "\(name[o.mod]) must be \(where_) \(name[o.other]) (its own load order), so the game loads it there. Move it \(where_) \(name[o.other]) in the list to match.", serious: false))
            r.note(file[o.mod], "Loaded \(where_) \(name[o.other]) (its load order)")
        }
        for s in j.settings ?? [] where ok(s.mod) {
            r.lines.append(Warning(text: "\(name[s.mod]): \"\(s.option ?? "")\" is set to \"\(s.value ?? "")\" in game, as another enabled mod asks for compatibility.", serious: false))
            r.note(file[s.mod], "\(s.option ?? ""): \(s.value ?? "") (set by another mod)")
        }
        for o in j.overlaps ?? [] where ok(o.winner) && ok(o.loser) {
            let n = o.files ?? 0
            var areas: [String] = []
            for a in o.areas ?? [] { let f = area(a.area ?? ""); if !areas.contains(f) { areas.append(f) } }
            let where_ = areas.isEmpty ? "" : " (\(areas.joined(separator: ", ")))"
            let files = n == 1 ? "game file" : "game files"
            r.lines.append(Warning(text: "\(name[o.winner]) and \(name[o.loser]) both replace \(n) \(files)\(where_). \(name[o.winner]) is higher in the list, so its version is used\(o.conditional == true ? " (some only at certain times)" : "").", serious: false))
            r.note(file[o.winner], "Overrides \(name[o.loser]) in \(n) \(n == 1 ? "file" : "files")")
            r.note(file[o.loser], "\(n) \(n == 1 ? "file" : "files") overridden by \(name[o.winner])")
            r.overlaps += 1
        }
        return r
    }
}
