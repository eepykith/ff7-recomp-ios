#if DEBUG
import Foundation

/// Stub data so the mods flow can be exercised in the simulator without real mods.
/// Everything goes through the real library code.
///
/// Launch arguments (Xcode scheme or `simctl launch … -FF7Reset`):
///   -FF7Reset        delete the game files, mods and profile first
///   -FF7SampleMods   import three sample mods (two folders with mod.xml, one .iro)
///   -FF7Play         start the game at once (AppModel)
enum SampleData {
    static func applyLaunchArguments(paths: AppPaths, library: ModLibrary) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-FF7Reset") {
            try? FileManager.default.removeItem(at: paths.root)
        }
        if args.contains("-FF7SampleMods") {
            try? importSampleMods(into: library)
        }
    }

    private static func scratch(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ff7-sample-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importSampleMods(into library: ModLibrary) throws {
        let mods: [(folder: String, name: String, author: String, category: String)] = [
            ("SampleFieldTextures", "Sample Field Textures", "FF7Recomp", "Backgrounds"),
            ("SampleMenuOverhaul", "Sample Menu Overhaul", "FF7Recomp", "User Interface"),
        ]
        for mod in mods {
            let dir = try scratch(mod.folder)
            let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <ModInfo>
              <ID>\(UUID().uuidString.lowercased())</ID>
              <Name>\(mod.name)</Name>
              <Author>\(mod.author)</Author>
              <Version>1.0</Version>
              <Category>\(mod.category)</Category>
              <Description>Placeholder mod for testing the launcher.</Description>
            </ModInfo>
            """
            try Data(xml.utf8).write(to: dir.appendingPathComponent("mod.xml"))
            try library.importMod(from: dir)
        }
        let iro = try scratch("iro").appendingPathComponent("SampleArchive.iro")
        try Data("IROS".utf8).write(to: iro)
        try library.importMod(from: iro)
    }
}
#endif
