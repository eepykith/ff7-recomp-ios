import XCTest
@testable import FF7Recomp

/// The catalog reader and the download links, as 7th Heaven writes them.
final class ModCatalogTests: XCTestCase {
    func testResolvesCatalogLinks() {
        XCTAssertEqual(ModDownloader.resolve("iros://Url/https$qhimm.7thheaven.rocks/Catalog 4.0/Misc/JessieMod.7z"),
                       "https://qhimm.7thheaven.rocks/Catalog%204.0/Misc/JessieMod.7z")
        XCTAssertEqual(ModDownloader.resolve("iros://Url/https$x.net/%5bA%5d_[B].7z"), "https://x.net/%5bA%5d_%5BB%5D.7z")
        XCTAssertEqual(ModDownloader.resolve("iros://GDrive/abc123"), "https://docs.google.com/uc?id=abc123&export=download")
        XCTAssertEqual(ModDownloader.resolve("https://github.com/a/b.iro"), "https://github.com/a/b.iro")
        XCTAssertNil(ModDownloader.resolve("iros://ExternalUrl/https$forums.qhimm.com/index.php"))
        XCTAssertNil(ModDownloader.resolve("iros://MegaSharedFolder/xyz"))
        XCTAssertEqual(ModDownloader.browserURL("iros://ExternalUrl/https$forums.qhimm.com/x")?.absoluteString,
                       "https://forums.qhimm.com/x")
    }

    func testParsesCatalog() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <Catalog><Mods>
          <Mod>
            <ID>45f280cc-327f-4242-a77c-40e2241ad6d3</ID><Name>Jessie Mod</Name><Author>Grimmy</Author>
            <Category>Miscellaneous</Category><Description>Talk to Jessie.</Description>
            <Link>https://forums.qhimm.com/x</Link>
            <Tags><string>party</string><string>jessie</string></Tags>
            <Requirement><ModID>11111111-0000-0000-0000-000000000000</ModID><Description>Base</Description></Requirement>
            <LatestVersion>
              <Link>iros://Url/https$a.b/J.7z</Link><Link>iros://GDrive/zzz</Link>
              <Version>1,5</Version><DownloadSize>1980</DownloadSize><PreviewImage>https://a.b/p.png</PreviewImage>
            </LatestVersion>
          </Mod>
          <Mod><Name>No ID: skipped</Name></Mod>
        </Mods></Catalog>
        """
        let mods = try ModCatalog.parse(Data(xml.utf8), catalog: "Test")
        XCTAssertEqual(mods.count, 1)
        let m = mods[0]
        XCTAssertEqual(m.name, "Jessie Mod")
        XCTAssertEqual(m.tags, ["party", "jessie"])
        XCTAssertEqual(m.links.count, 2)
        XCTAssertEqual(m.version, 1.5)
        XCTAssertEqual(m.sizeKB, 1980)
        XCTAssertEqual(m.requirements.first?.id, "11111111-0000-0000-0000-000000000000")
        XCTAssertEqual(m.infoLink, "https://forums.qhimm.com/x")
        XCTAssertFalse(m.needsBrowser)
        XCTAssertThrowsError(try ModCatalog.parse(Data("<NotACatalog/>".utf8), catalog: "x"))
    }

    func testDriveWarningPage() {
        let html = """
        <form id="download-form" action="https://drive.usercontent.google.com/download" method="get">
        <input type="hidden" name="id" value="ABC"><input type="hidden" name="export" value="download">
        <input type="hidden" name="confirm" value="t"><input type="hidden" name="uuid" value="u-1">
        """
        XCTAssertEqual(ModDownloader.driveConfirm(html, page: URL(string: "https://docs.google.com/uc?id=ABC")!)?.absoluteString,
                       "https://drive.usercontent.google.com/download?id=ABC&export=download&confirm=t&uuid=u-1")
    }

    func testUnzip() throws {
        // a zip made by the system's zip tool is not available on iOS; ff7_unzip refuses a non-zip cleanly
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unzip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bogus = dir.appendingPathComponent("x.zip")
        try Data("not a zip at all, just some text".utf8).write(to: bogus)
        var err = [CChar](repeating: 0, count: 256)
        XCTAssertEqual(ff7_unzip(bogus.path, dir.path, &err, err.count), -1)
        XCTAssertTrue(String(cString: err).contains("not a zip"))
    }
}
