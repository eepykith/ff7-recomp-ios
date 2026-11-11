import Foundation

/// Owns imported GamePackage files under Application Support.
final class PackageStore {
    static let shared = PackageStore()

    private let fm = FileManager.default
    private let bookmarkKey = "ff7.currentPackagePath"

    private var packagesDirectory: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FF7Recomp/packages", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func currentPackagePath() -> String? {
        UserDefaults.standard.string(forKey: bookmarkKey)
    }

    @discardableResult
    func importPackage(from url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let dest = packagesDirectory.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: url, to: dest)
        UserDefaults.standard.set(dest.path, forKey: bookmarkKey)
        return dest
    }
}
