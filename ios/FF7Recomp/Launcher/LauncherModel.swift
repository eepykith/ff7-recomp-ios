import Foundation
import UniformTypeIdentifiers

@MainActor
final class LauncherModel: ObservableObject {
    @Published var packagePath: String?
    @Published var statusMessage: String?
    @Published var showImporter = false
    @Published var targetFPS: Int = 60

    var engineVersion: String {
        EngineBridge.version()
    }

    var canAttemptPlay: Bool {
        true // Always allow opening GameHost; host reports missing package.
    }

    var packageLabel: String {
        guard let packagePath else { return "None imported" }
        return URL(fileURLWithPath: packagePath).lastPathComponent
    }

    func refresh() {
        packagePath = PackageStore.shared.currentPackagePath()
        let state = EngineBridge.probe(width: 1280, height: 720, fps: Int32(targetFPS))
        statusMessage = state.message
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            statusMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let dest = try PackageStore.shared.importPackage(from: url)
                packagePath = dest.path
                statusMessage = "Imported \(dest.lastPathComponent)"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}

extension UTType {
    static var ff7Package: UTType {
        UTType(filenameExtension: "ff7pkg") ?? .data
    }
}
