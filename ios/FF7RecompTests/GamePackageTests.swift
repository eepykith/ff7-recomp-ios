import Compression
import CryptoKit
import XCTest
@testable import FF7Recomp

final class GamePackageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pkgtests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    static func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// Writes a package folder with the given files, listed (hash + size) in its manifest.
    @discardableResult
    func makePackage(_ name: String, files: [String: Data], core: String = "0.2.0",
                     mutate: ((inout [String: Any]) -> Void)? = nil) throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var listed: [[String: Any]] = []
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            listed.append(["path": path, "sha256": Self.sha(data), "size": data.count])
        }
        var manifest: [String: Any] = [
            "format": "ff7pkg-v1", "exe_sha256": String(repeating: "1", count: 64), "language": "en",
            "build_id": name, "core_version": core, "files": listed,
        ]
        mutate?(&manifest)
        try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("manifest.json"))
        return dir
    }

    func testValidPackage() throws {
        let dir = try makePackage("ok", files: ["libff7.dylib": Data("code".utf8), "data/a.bin": Data([1, 2, 3])])
        let pkg = try GamePackageValidator(appCoreVersion: "0.2.0-p1").validate(directory: dir)
        XCTAssertEqual(pkg.manifest.buildID, "ok")
        XCTAssertFalse(pkg.isStub)
        XCTAssertEqual(pkg.libraryURL.lastPathComponent, "libff7.dylib")
    }

    func testMissingManifest() {
        XCTAssertThrowsError(try GamePackageValidator().validate(directory: root)) {
            XCTAssertEqual($0 as? GamePackageError, .missingManifest)
        }
    }

    func testManifestErrorIsWrapped() throws {
        let dir = try makePackage("bad", files: [:]) { $0["format"] = "nope" }
        XCTAssertThrowsError(try GamePackageValidator().validate(directory: dir)) {
            XCTAssertEqual($0 as? GamePackageError, .manifest(.unsupportedFormat("nope")))
        }
    }

    func testMissingSizeAndHashMismatch() throws {
        let dir = try makePackage("tamper", files: ["libff7.dylib": Data("code".utf8), "b.bin": Data("bbbb".utf8)])
        let v = GamePackageValidator()

        try Data("CODE".utf8).write(to: dir.appendingPathComponent("libff7.dylib"))   // same size
        XCTAssertThrowsError(try v.validate(directory: dir)) {
            XCTAssertEqual($0 as? GamePackageError, .hashMismatch("libff7.dylib"))
        }
        XCTAssertNoThrow(try v.validate(directory: dir, verifyHashes: false))

        try Data("longer".utf8).write(to: dir.appendingPathComponent("b.bin"))
        XCTAssertThrowsError(try v.validate(directory: dir, verifyHashes: false)) {
            XCTAssertEqual($0 as? GamePackageError, .sizeMismatch("b.bin"))
        }

        try Data("bbbb".utf8).write(to: dir.appendingPathComponent("b.bin"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("libff7.dylib"))
        XCTAssertThrowsError(try v.validate(directory: dir, verifyHashes: false)) {
            XCTAssertEqual($0 as? GamePackageError, .missingFile("libff7.dylib"))
        }
    }

    func testIncompatibleCore() throws {
        let dir = try makePackage("old", files: [:], core: "0.1.0")
        XCTAssertThrowsError(try GamePackageValidator(appCoreVersion: "0.2.0-p1").validate(directory: dir)) {
            XCTAssertEqual($0 as? GamePackageError, .incompatibleCore(package: "0.1.0", app: "0.2.0-p1"))
        }
        XCTAssertNoThrow(try GamePackageValidator(appCoreVersion: nil).validate(directory: dir))
    }

    // MARK: Installer

    private func installer() -> LocalGameInstaller {
        LocalGameInstaller(paths: AppPaths(root: root.appendingPathComponent("app")),
                           validator: GamePackageValidator(appCoreVersion: "0.2.0"))
    }

    func testImportFolderThenZipReplacesIt() throws {
        let inst = installer()
        XCTAssertNil(inst.installedPackage())

        let folder = try makePackage("first", files: ["libff7.dylib": Data("one".utf8)])
        var stages: [GameImportStage] = []
        let first = try inst.importPackage(from: folder) { stages.append($0) }
        XCTAssertEqual(stages, [.copying, .verifying])
        XCTAssertEqual(first.rootURL.standardizedFileURL, inst.paths.game.standardizedFileURL)
        XCTAssertEqual(inst.installedPackage()?.manifest.buildID, "first")

        let second = try makePackage("second", files: ["libff7.dylib": Data(repeating: 7, count: 5000), "x/y.txt": Data("y".utf8)])
        let zip = root.appendingPathComponent("second.ff7pkg")
        try TestZip.write(folder: second, to: zip)
        stages = []
        _ = try inst.importPackage(from: zip) { stages.append($0) }
        XCTAssertEqual(stages, [.unpacking, .verifying])
        XCTAssertEqual(inst.installedPackage()?.manifest.buildID, "second")
        XCTAssertEqual(try Data(contentsOf: inst.paths.game.appendingPathComponent("x/y.txt")), Data("y".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inst.paths.importStaging.path))

        try inst.uninstall()
        XCTAssertNil(inst.installedPackage())
    }

    func testFailedImportKeepsInstalledPackage() throws {
        let inst = installer()
        _ = try inst.importPackage(from: try makePackage("good", files: [:])) { _ in }
        let bad = try makePackage("bad", files: ["libff7.dylib": Data("x".utf8)])
        try Data("y".utf8).write(to: bad.appendingPathComponent("libff7.dylib"))
        XCTAssertThrowsError(try inst.importPackage(from: bad) { _ in })
        XCTAssertEqual(inst.installedPackage()?.manifest.buildID, "good")

        let notZip = root.appendingPathComponent("junk.ff7pkg")
        try Data("hello".utf8).write(to: notZip)
        XCTAssertThrowsError(try inst.importPackage(from: notZip) { _ in }) {
            XCTAssertEqual($0 as? ZipExtractor.Failure, .notZip)
        }
        XCTAssertEqual(inst.installedPackage()?.manifest.buildID, "good")
    }

    func testZipRejectsPathTraversal() throws {
        let zip = root.appendingPathComponent("evil.zip")
        try TestZip.write(entries: [("../evil.txt", Data("x".utf8))], to: zip)
        XCTAssertThrowsError(try ZipExtractor.extract(archive: zip, to: root.appendingPathComponent("out"))) {
            XCTAssertEqual($0 as? ZipExtractor.Failure, .unsafePath("../evil.txt"))
        }
    }
}

/// Writes simple ZIPs for tests: small entries stored, larger ones deflated (as Python's
/// zipfile would). CRCs are left 0 (the extractor relies on the manifest hashes).
enum TestZip {
    static func write(folder: URL, to url: URL) throws {
        let fm = FileManager.default
        var entries: [(String, Data)] = []
        let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let file as URL in e {
            guard try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == false else { continue }
            let rel = String(file.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
            entries.append((rel, try Data(contentsOf: file)))
        }
        try write(entries: entries, to: url)
    }

    static func write(entries: [(String, Data)], to url: URL) throws {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func u32(_ v: Int, _ d: inout Data) { for s in [0, 8, 16, 24] { d.append(UInt8(v >> s & 0xFF)) } }
        for (name, data) in entries {
            var payload = data
            var method = 0
            if data.count > 64 {
                var dst = [UInt8](repeating: 0, count: data.count + 1024)
                let n = data.withUnsafeBytes { src in
                    compression_encode_buffer(&dst, dst.count, src.bindMemory(to: UInt8.self).baseAddress!,
                                              data.count, nil, COMPRESSION_ZLIB)
                }
                if n > 0 { payload = Data(dst[0..<n]); method = 8 }
            }
            let nameBytes = Data(name.utf8)
            let offset = out.count
            u32(0x0403_4B50, &out); u16(20, &out); u16(0, &out); u16(method, &out); u16(0, &out); u16(0, &out)
            u32(0, &out); u32(payload.count, &out); u32(data.count, &out); u16(nameBytes.count, &out); u16(0, &out)
            out.append(nameBytes); out.append(payload)

            u32(0x0201_4B50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(method, &central)
            u16(0, &central); u16(0, &central); u32(0, &central); u32(payload.count, &central); u32(data.count, &central)
            u16(nameBytes.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(offset, &central); central.append(nameBytes)
        }
        let cdOffset = out.count
        out.append(central)
        u32(0x0605_4B50, &out); u16(0, &out); u16(0, &out); u16(entries.count, &out); u16(entries.count, &out)
        u32(central.count, &out); u32(cdOffset, &out); u16(0, &out)
        try out.write(to: url)
    }
}
