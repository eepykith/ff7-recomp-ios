import XCTest
@testable import FF7Recomp

final class GameManifestParserTests: XCTestCase {
    static let sha = String(repeating: "ab", count: 32)

    static func json(_ overrides: [String: Any?] = [:]) -> Data {
        var obj: [String: Any] = [
            "format": "ff7pkg-v1",
            "exe_sha256": sha,
            "language": "en",
            "build_id": "abc123-20261123",
            "core_version": "0.2.0",
        ]
        for (k, v) in overrides {
            if let v { obj[k] = v } else { obj.removeValue(forKey: k) }
        }
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    private func assertError(_ data: Data, _ expected: GameManifestError, line: UInt = #line) {
        XCTAssertThrowsError(try GameManifestParser.parse(data), line: line) { error in
            XCTAssertEqual(error as? GameManifestError, expected, line: line)
        }
    }

    func testMinimalManifestUsesDefaults() throws {
        let m = try GameManifestParser.parse(Self.json())
        XCTAssertEqual(m.format, "ff7pkg-v1")
        XCTAssertEqual(m.exeSHA256, Self.sha)
        XCTAssertEqual(m.language, "en")
        XCTAssertEqual(m.buildID, "abc123-20261123")
        XCTAssertEqual(m.coreVersion, "0.2.0")
        XCTAssertEqual(m.platform, "ios-arm64")
        XCTAssertEqual(m.files, [])
        XCTAssertNil(m.exeName)
        XCTAssertNil(m.exeSize)
        XCTAssertEqual(m.exeFingerprint, "abababababab")
    }

    /// The exact shape `mac/ff7recomp_mac build-package` writes.
    func testParsesMacCompanionOutput() throws {
        let text = """
        {
          "format": "ff7pkg-v1",
          "tool_version": "0.1.0",
          "created_at": "2026-11-23T17:53:45Z",
          "exe_name": "ff7_en.exe",
          "exe_sha256": "da4ec5670090861a305ca2215e0565e698fe789348772ae1d934d7072ab00112",
          "exe_size": 1000,
          "language": "en",
          "build_id": "da4ec5670090-20261123175345",
          "core_version": "0.2.0",
          "platform": "ios-arm64",
          "notes": "P0 stub package",
          "files": []
        }
        """
        let m = try GameManifestParser.parse(Data(text.utf8))
        XCTAssertEqual(m.exeName, "ff7_en.exe")
        XCTAssertEqual(m.exeSize, 1000)
        XCTAssertEqual(m.toolVersion, "0.1.0")
        XCTAssertEqual(m.createdAt, "2026-11-23T17:53:45Z")
        XCTAssertEqual(m.notes, "P0 stub package")
        XCTAssertTrue(GamePackage(rootURL: URL(fileURLWithPath: "/"), manifest: m).isStub)
    }

    func testFilesListAndNormalization() throws {
        let fileSHA = String(repeating: "C", count: 64)
        let m = try GameManifestParser.parse(Self.json([
            "exe_sha256": Self.sha.uppercased(),
            "language": " FR ",
            "files": [["path": "libff7.dylib", "sha256": fileSHA, "size": 42],
                      ["path": "data/field/flevel.lgp", "sha256": fileSHA]],
        ]))
        XCTAssertEqual(m.exeSHA256, Self.sha)
        XCTAssertEqual(m.language, "fr")
        XCTAssertEqual(m.files, [
            .init(path: "libff7.dylib", sha256: fileSHA.lowercased(), size: 42),
            .init(path: "data/field/flevel.lgp", sha256: fileSHA.lowercased(), size: nil),
        ])
        XCTAssertFalse(GamePackage(rootURL: URL(fileURLWithPath: "/"), manifest: m).isStub)
    }

    func testRequiredFields() {
        for key in ["format", "exe_sha256", "language", "build_id", "core_version"] {
            assertError(Self.json([key: nil]), .missingField(key))
        }
        assertError(Self.json(["build_id": "   "]), .missingField("build_id"))
    }

    func testRejectsBadValues() {
        assertError(Data("not json".utf8), .notJSON)
        assertError(Data("[1,2]".utf8), .notJSON)
        assertError(Self.json(["format": "ff7pkg-v2"]), .unsupportedFormat("ff7pkg-v2"))
        assertError(Self.json(["exe_sha256": "abc"]), .invalidSHA256(field: "exe_sha256"))
        assertError(Self.json(["exe_sha256": String(repeating: "zz", count: 32)]), .invalidSHA256(field: "exe_sha256"))
        assertError(Self.json(["language": "xx"]), .unsupportedLanguage("xx"))
        assertError(Self.json(["platform": "android-arm64"]), .unsupportedPlatform("android-arm64"))
        assertError(Self.json(["build_id": 12]), .wrongType("build_id"))
        assertError(Self.json(["exe_size": true]), .wrongType("exe_size"))
        assertError(Self.json(["files": "libff7.dylib"]), .wrongType("files"))
    }

    func testRejectsUnsafeOrBadFileEntries() {
        let ok = String(repeating: "0", count: 64)
        for path in ["../escape", "/abs/path", "a/../../b", "a\\b", "a//b", "dir/"] {
            assertError(Self.json(["files": [["path": path, "sha256": ok]]]), .invalidFilePath(path))
        }
        assertError(Self.json(["files": [["sha256": ok]]]), .missingField("files[].path"))
        assertError(Self.json(["files": [["path": "libff7.dylib", "sha256": "nope"]]]),
                    .invalidSHA256(field: "files[libff7.dylib].sha256"))
    }

    func testCoreVersionCompatibility() {
        XCTAssertTrue(CoreVersion.isCompatible(package: "0.2.0", app: "0.2.0-p1"))
        XCTAssertTrue(CoreVersion.isCompatible(package: "0.2.7", app: "0.2.0"))
        XCTAssertFalse(CoreVersion.isCompatible(package: "0.3.0", app: "0.2.0-p1"))
        XCTAssertFalse(CoreVersion.isCompatible(package: "0", app: "0.2.0"))
        XCTAssertTrue(CoreVersion.isCompatible(package: "1.4.0", app: "1.0.2"))
        XCTAssertFalse(CoreVersion.isCompatible(package: "2.0.0", app: "1.9.0"))
        XCTAssertFalse(CoreVersion.isCompatible(package: "garbage", app: "1.0.0"))
    }
}
