import XCTest
@testable import FF7Recomp

final class ModProfileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("modtests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Writer

    /// Byte-for-byte the shape ff7_mods_load reads.
    func testSerializeMatchesCoreFormat() {
        let profile = ModProfile(language: "en", mods: [
            .init(path: "IFRIT.iro", enabled: true, options: [.init(id: "someoption", value: 1), .init(id: "other", value: -2)]),
            .init(path: "NinostyleChibi", enabled: false),
            .init(path: "Reunion.iro", enabled: true),
        ])
        XCTAssertEqual(ModProfileXML.serialize(profile), """
        <?xml version="1.0" encoding="utf-8"?>
        <Profile Language="en">
          <Mod Path="IFRIT.iro" Enabled="true">
            <Option ID="someoption" Value="1"/>
            <Option ID="other" Value="-2"/>
          </Mod>
          <Mod Path="NinostyleChibi" Enabled="false"/>
          <Mod Path="Reunion.iro" Enabled="true"/>
        </Profile>

        """)
    }

    func testSerializeEmptyAndEscaping() {
        XCTAssertEqual(ModProfileXML.serialize(ModProfile(language: "fr")),
                       "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Profile Language=\"fr\">\n</Profile>\n")
        let xml = ModProfileXML.serialize(ModProfile(mods: [.init(path: #"A&B "<x>".iro"#, enabled: true)]))
        XCTAssertTrue(xml.contains(#"<Mod Path="A&amp;B &quot;&lt;x&gt;&quot;.iro" Enabled="true"/>"#), xml)
    }

    func testRoundTrip() throws {
        let profile = ModProfile(language: "de", mods: [
            .init(path: "A&B.iro", enabled: false, options: [.init(id: "opt", value: 3)]),
            .init(path: "Folder Mod", enabled: true),
        ])
        XCTAssertEqual(try ModProfileXML.parse(Data(ModProfileXML.serialize(profile).utf8)), profile)
    }

    func testWriteIsAtomicFileInModsFolder() throws {
        let paths = AppPaths(root: root)
        try ModProfileXML.write(ModProfile(mods: [.init(path: "X.iro", enabled: true)]), to: paths.modProfile)
        XCTAssertEqual(paths.modProfile.path, root.appendingPathComponent("mods/profile.xml").path)
        let text = try String(contentsOf: paths.modProfile, encoding: .utf8)
        XCTAssertTrue(text.contains(#"<Mod Path="X.iro" Enabled="true"/>"#))
        // The core finds the game at <profile dir>/../game.
        XCTAssertEqual(paths.modProfile.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("game").path, paths.game.path)
    }

    // MARK: Reader (same rules as the core)

    func testParseLenientForms() throws {
        let xml = """
        <?xml version="1.0"?>
        <Profile Language="EN">
          <Mod Path="mods\\IFRIT.iro"> <Option ID="SomeOption" Value="1"/> <Option ID="bad" Value="x"/> </Mod>
          <Mod Path="Off.iro" Enabled="0"/>
          <Mod Path="Off2.iro" Enabled="FALSE"/>
          <Mod Path="On.iro" Enabled="1"/>
          <Mod Path=""/>
        </Profile>
        """
        let p = try ModProfileXML.parse(Data(xml.utf8))
        XCTAssertEqual(p.language, "en")
        XCTAssertEqual(p.mods, [
            .init(path: "mods/IFRIT.iro", enabled: true, options: [.init(id: "someoption", value: 1)]),
            .init(path: "Off.iro", enabled: false),
            .init(path: "Off2.iro", enabled: false),
            .init(path: "On.iro", enabled: true),
        ])
    }

    func testParseRejectsGarbage() {
        XCTAssertThrowsError(try ModProfileXML.parse(Data("<Profile><Mod".utf8)))
        XCTAssertThrowsError(try ModProfileXML.parse(Data("<Other/>".utf8)))
    }

    // MARK: Library

    private func makeFolderMod(_ name: String, modXML: String? = nil) throws -> URL {
        let dir = root.appendingPathComponent("src/\(name)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let modXML { try Data(modXML.utf8).write(to: dir.appendingPathComponent("MOD.XML")) }
        return dir
    }

    private func makeIRO(_ name: String, in folder: String = "src") throws -> URL {
        let url = root.appendingPathComponent("\(folder)/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("IROS".utf8).write(to: url)
        return url
    }

    func testLibraryMergesProfileOrderWithFolder() throws {
        let paths = AppPaths(root: root.appendingPathComponent("app"))
        let lib = ModLibrary(paths: paths)
        for n in ["B.iro", "a.iro", "Zeta.iro"] { try lib.importMod(from: makeIRO(n)) }
        try lib.importMod(from: makeFolderMod("Chibi", modXML: "\u{FEFF}<ModInfo><Name> Chibi Party </Name><Author>Nino</Author><Category>Characters</Category><Version>1.2</Version></ModInfo>"))
        try FileManager.default.createDirectory(at: paths.modCache, withIntermediateDirectories: true)
        try Data().write(to: paths.mods.appendingPathComponent("hext_status.txt"))   // not a mod

        // Saved: Zeta first (disabled, with options), b (case differs), a mod no longer present.
        try ModProfileXML.write(ModProfile(language: "fr", mods: [
            .init(path: "Zeta.iro", enabled: false, options: [.init(id: "o", value: 2)]),
            .init(path: "b.iro", enabled: true),
            .init(path: "Gone.iro", enabled: true),
        ]), to: paths.modProfile)

        let (language, mods) = lib.load()
        XCTAssertEqual(language, "fr")
        XCTAssertEqual(mods.map(\.fileName), ["Zeta.iro", "B.iro", "a.iro", "Chibi"])
        XCTAssertEqual(mods.map(\.enabled), [false, true, false, false])
        XCTAssertEqual(mods[0].options, [.init(id: "o", value: 2)])
        XCTAssertEqual(mods[3].kind, .folder)
        XCTAssertEqual(mods[3].displayName, "Chibi Party")
        XCTAssertEqual(mods[3].info?.author, "Nino")
        XCTAssertEqual(mods[1].displayName, "B")

        // Reorder + toggle + save, then reload.
        var edited = mods
        edited.move(fromOffsets: [3], toOffset: 0)
        edited[0].enabled = true
        try lib.save(edited, language: "fr")
        XCTAssertEqual(try String(contentsOf: paths.modProfile, encoding: .utf8), """
        <?xml version="1.0" encoding="utf-8"?>
        <Profile Language="fr">
          <Mod Path="Chibi" Enabled="true"/>
          <Mod Path="Zeta.iro" Enabled="false">
            <Option ID="o" Value="2"/>
          </Mod>
          <Mod Path="B.iro" Enabled="true"/>
          <Mod Path="a.iro" Enabled="false"/>
        </Profile>

        """)
        XCTAssertEqual(lib.load().mods.map(\.fileName), ["Chibi", "Zeta.iro", "B.iro", "a.iro"])

        try lib.remove("Zeta.iro")
        XCTAssertEqual(lib.load().mods.map(\.fileName), ["Chibi", "B.iro", "a.iro"])
    }

    func testImportRejectsNonModsAndReplacesSameName() throws {
        let lib = ModLibrary(paths: AppPaths(root: root.appendingPathComponent("app")))
        let txt = root.appendingPathComponent("readme.txt")
        try Data().write(to: txt)
        XCTAssertThrowsError(try lib.importMod(from: txt)) {
            XCTAssertEqual($0 as? ModLibraryError, .notAMod("readme.txt"))
        }

        try lib.importMod(from: makeIRO("Mod.iro"))
        let upper = try makeIRO("MOD.IRO", in: "src2")   // the volume may be case-insensitive
        try Data("IROS v2".utf8).write(to: upper)
        XCTAssertEqual(try lib.importMod(from: upper), "MOD.IRO")
        let mods = lib.load().mods
        XCTAssertEqual(mods.map(\.fileName), ["MOD.IRO"])
        XCTAssertEqual(mods[0].kind, .iro)
    }
}
