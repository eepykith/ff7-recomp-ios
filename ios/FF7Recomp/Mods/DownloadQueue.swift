import Foundation
import UIKit

extension Notification.Name {
    /// The mods folder changed (a download finished): the Mods screen reloads.
    static let ff7ModsChanged = Notification.Name("ff7ModsChanged")
}

/// The download queue: catalog mods are installed one at a time, in the order they were added,
/// while the app stays usable. Mirrors the Android launcher's `DownloadQueue.java`.
///
/// Waiting and running items are kept in `<root>/downloads/queue.json`, so a queue cut short
/// (the app closed or stopped by iOS) carries on the next time the app opens; the running
/// download resumes from its .part file. Leaving the app asks iOS for time to finish.
@MainActor
final class DownloadQueue: ObservableObject {
    enum State: Equatable { case queued, running, done, failed(String), cancelled }

    struct Item: Identifiable, Equatable {
        let mod: CatalogMod
        let update: Bool
        var state: State = .queued
        var phase = "Waiting"
        var done: Int64 = 0
        var total: Int64 = 0
        var id: String { mod.key }

        /// 0…1, or nil when the size is unknown.
        var fraction: Double? {
            let t = total > 0 ? total : mod.sizeKB * 1024
            return t > 0 ? min(1, Double(done) / Double(t)) : nil
        }
        var finished: Bool {
            switch state {
            case .done, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    @Published private(set) var items: [Item] = []

    let catalog: ModCatalog
    let library: ModLibrary
    private let downloader: ModDownloader
    private let saveFile: URL
    private var worker: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    static let shared = DownloadQueue(paths: .standard)

    init(paths: AppPaths) {
        catalog = ModCatalog(paths: paths)
        library = ModLibrary(paths: paths)
        downloader = ModDownloader(paths: paths)
        saveFile = downloader.downloads.appendingPathComponent("queue.json")
        restore()
    }

    var active: [Item] { items.filter { !$0.finished } }
    var isBusy: Bool { !active.isEmpty }

    func item(for mod: CatalogMod) -> Item? { items.last { $0.id == mod.key } }

    /// Queue a mod (and the catalog mods it requires that are not installed yet, first).
    func add(_ mod: CatalogMod) {
        for need in requirements(of: mod) where catalog.installedOf(need) == nil && !isQueued(need) {
            enqueue(need, update: false)
        }
        if !isQueued(mod) { enqueue(mod, update: catalog.installedOf(mod) != nil) }
        save()
        start()
    }

    /// The catalog mods `mod` needs (its Requirement entries), for the confirmation.
    func requirements(of mod: CatalogMod) -> [CatalogMod] {
        mod.requirements.compactMap { catalog.byID($0.id) }
    }

    func cancel(_ item: Item) {
        guard let i = items.firstIndex(where: { $0.id == item.id && !$0.finished }) else { return }
        if items[i].state == .running {
            downloader.cancel()                // the worker marks it cancelled
        } else {
            items[i].state = .cancelled
            downloader.discard(id: item.mod.id)
        }
        save()
    }

    /// The mods folder changed outside a download (a mod deleted in the app or in Files): mods
    /// that are gone stop counting as installed.
    func libraryChanged() {
        catalog.prune(modsDir: library.paths.mods)
        objectWillChange.send()
    }

    func clearFinished() {
        items.removeAll { $0.finished }
    }

    private func isQueued(_ m: CatalogMod) -> Bool { items.contains { $0.id == m.key && !$0.finished } }

    private func enqueue(_ m: CatalogMod, update: Bool) {
        items.removeAll { $0.id == m.key && $0.finished }
        items.append(Item(mod: m, update: update))
    }

    // MARK: Worker

    private func start() {
        guard worker == nil, items.contains(where: { $0.state == .queued }) else { return }
        beginBackground()
        worker = Task { [weak self] in
            await self?.runQueue()
            self?.worker = nil
            self?.endBackground()
        }
    }

    private func runQueue() async {
        while let i = items.firstIndex(where: { $0.state == .queued }) {
            items[i].state = .running
            items[i].phase = "Starting"
            let item = items[i]
            let id = item.id
            let downloader = downloader
            let mod = item.mod
            let base = catalog.installedOf(mod).map { ($0.file as NSString).deletingPathExtension } ?? mod.name
            do {
                let file = try await downloader.install(id: mod.id, baseName: base, links: mod.links,
                                                        expectedSize: mod.sizeKB * 1024) { phase, done, total in
                    Task { @MainActor [weak self] in self?.progress(id, phase, done, total) }
                }
                catalog.markInstalled(mod, file: file)
                if !item.update { enableNew(file) }
                setState(id, .done)
                NotificationCenter.default.post(name: .ff7ModsChanged, object: nil)
            } catch ModDownloadError.cancelled {
                downloader.discard(id: mod.id)
                setState(id, .cancelled)
            } catch {
                setState(id, .failed(error.localizedDescription))
            }
            save()
        }
    }

    private func progress(_ id: String, _ phase: String, _ done: Int64, _ total: Int64) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        items[i].phase = phase
        items[i].done = done
        items[i].total = total
    }

    private func setState(_ id: String, _ state: State) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        items[i].state = state
        items[i].phase = ""
    }

    /// A new mod is switched on (the library lists new files last, off); an update keeps its
    /// place, state and options.
    private func enableNew(_ file: String) {
        var loaded = library.load()
        for i in loaded.mods.indices where loaded.mods[i].fileName.caseInsensitiveCompare(file) == .orderedSame {
            loaded.mods[i].enabled = true
        }
        try? library.save(loaded.mods, language: loaded.language ?? "en")
    }

    // MARK: Saved queue

    private struct Saved: Codable { var id: String; var update: Bool }

    private func save() {
        let waiting = items.filter { !$0.finished }.map { Saved(id: $0.mod.id, update: $0.update) }
        if let data = try? JSONEncoder().encode(waiting) { try? data.write(to: saveFile, options: .atomic) }
    }

    /// The queue left from last time (downloads resume), and the clutter of ones that ended.
    private func restore() {
        let saved = (try? Data(contentsOf: saveFile)).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
        for s in saved {
            guard let m = catalog.byID(s.id) else { continue }
            items.append(Item(mod: m, update: s.update))
        }
        downloader.sweep(keeping: Set(items.map { $0.mod.id }))
        catalog.prune(modsDir: library.paths.mods)
        start()
    }

    // MARK: Leaving the app

    private func beginBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Mod download") { [weak self] in
            // out of time: the download stops here and resumes from its .part file next time
            Task { @MainActor in self?.endBackground() }
        }
    }

    private func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
