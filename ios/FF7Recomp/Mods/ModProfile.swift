import Foundation

/// The launcher's mod profile: `<root>/mods/profile.xml`, read by the core at boot
/// (`ff7_mods_load`, `src/mods/mods.h` in the engine core) and written in the shape it reads:
///
/// ```xml
/// <?xml version="1.0" encoding="utf-8"?>
/// <Profile Language="en">
///   <Mod Path="IFRIT.iro" Enabled="true">
///     <Option ID="someoption" Value="1"/>
///   </Mod>
///   <Mod Path="NinostyleChibi" Enabled="false"/>
/// </Profile>
/// ```
///
/// Mods are in priority order (the first that provides a file wins, as in 7th Heaven).
/// `Path` is relative to the profile's folder. Disabled mods stay listed so their order and
/// options survive.
struct ModProfile: Equatable {
    struct Option: Equatable {
        var id: String
        var value: Int
    }

    struct Entry: Equatable {
        var path: String
        var enabled: Bool
        var options: [Option] = []
    }

    var language: String = "en"
    var mods: [Entry] = []
}

enum ModProfileXML {
    static func serialize(_ profile: ModProfile) -> String {
        var out = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        out += "<Profile Language=\"\(escape(profile.language))\">\n"
        for mod in profile.mods {
            out += "  <Mod Path=\"\(escape(mod.path))\" Enabled=\"\(mod.enabled ? "true" : "false")\""
            if mod.options.isEmpty {
                out += "/>\n"
                continue
            }
            out += ">\n"
            for option in mod.options {
                out += "    <Option ID=\"\(escape(option.id))\" Value=\"\(option.value)\"/>\n"
            }
            out += "  </Mod>\n"
        }
        out += "</Profile>\n"
        return out
    }

    /// Reads a profile. Like the core: `Enabled` other than "false"/"0" (or
    /// absent) is enabled, option IDs are case-insensitive (kept lower case), backslashes
    /// in paths become '/'.
    static func parse(_ data: Data) throws -> ModProfile {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawProfile else {
            throw ModProfileError.unreadable(parser.parserError?.localizedDescription ?? "no <Profile> element")
        }
        return delegate.profile
    }

    /// Writes atomically (a half-written profile would drop every mod).
    static func write(_ profile: ModProfile, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(serialize(profile).utf8).write(to: url, options: .atomic)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var profile = ModProfile()
        var sawProfile = false
        private var depth = 0
        private var current: ModProfile.Entry?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            switch (depth, name) {
            case (1, "Profile"):
                sawProfile = true
                if let lang = attributes["Language"], !lang.isEmpty { profile.language = lang.lowercased() }
            case (2, "Mod"):
                let path = (attributes["Path"] ?? "").replacingOccurrences(of: "\\", with: "/")
                let en = (attributes["Enabled"] ?? "").lowercased()
                current = ModProfile.Entry(path: path, enabled: en != "false" && en != "0")
            case (3, "Option"):
                guard let id = attributes["ID"], let value = attributes["Value"].flatMap({ Int($0) }) else { return }
                current?.options.append(.init(id: id.lowercased(), value: value))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if depth == 2, name == "Mod", let mod = current {
                if !mod.path.isEmpty { profile.mods.append(mod) }
                current = nil
            }
            depth -= 1
        }
    }
}

enum ModProfileError: Error, LocalizedError {
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "profile.xml is unreadable: \(why)"
        }
    }
}
