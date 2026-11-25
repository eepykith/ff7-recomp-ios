import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ModsModel: ObservableObject {
    @Published private(set) var mods: [ModItem] = []
    @Published var errorMessage: String?
    @Published private(set) var importing = false
    /// The enabled mods as the game loads them: overlaps, Forbid/Require (full app only).
    @Published private(set) var report = ModConflicts.Report()

    let library: ModLibrary
    /// The game's language, if known; falls back to the saved profile's.
    private let gameLanguage: String?
    private(set) var language = "en"

    init(library: ModLibrary, gameLanguage: String?) {
        self.library = library
        self.gameLanguage = gameLanguage
        reload()
    }

    var enabledCount: Int { mods.filter(\.enabled).count }

    func reload() {
        let loaded = library.load()
        language = gameLanguage ?? loaded.language ?? "en"
        mods = loaded.mods
        save()   // records newly found mods and the game language
    }

    func check() {
        let profile = library.paths.modProfile
        let catalog = DownloadQueue.shared.catalog
        Task.detached(priority: .utility) {
            let r = ModConflicts.report(profile: profile, catalog: catalog)
            await MainActor.run { self.report = r }
        }
    }

    func setEnabled(_ mod: ModItem, _ enabled: Bool) {
        guard let i = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        mods[i].enabled = enabled
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        mods.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            do { try library.remove(mods[i].fileName) } catch { errorMessage = error.localizedDescription }
        }
        mods.remove(atOffsets: offsets)
        save()
    }

    func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            importing = true
            let library = library
            Task.detached(priority: .userInitiated) {
                var failures: [String] = []
                for url in urls {
                    do { try library.importMod(from: url) } catch { failures.append(error.localizedDescription) }
                }
                await MainActor.run {
                    self.importing = false
                    self.reload()
                    if !failures.isEmpty { self.errorMessage = failures.joined(separator: "\n") }
                }
            }
        }
    }

    #if DEBUG
    func addSampleMods() {
        do { try SampleData.importSampleMods(into: library) } catch { errorMessage = error.localizedDescription }
        reload()
    }
    #endif

    private func save() {
        defer { check() }
        do {
            try library.save(mods, language: language)
        } catch {
            errorMessage = "Could not save the mod profile: \(error.localizedDescription)"
        }
    }
}

/// 7th Heaven mods: Get Mods (the catalogs), enable/disable and priority order, saved to
/// `mods/profile.xml`, which the game reads when it starts; the conflict report.
struct ModsView: View {
    @StateObject private var model: ModsModel
    @State private var showImporter = false

    init(library: ModLibrary, gameLanguage: String?) {
        _model = StateObject(wrappedValue: ModsModel(library: library, gameLanguage: gameLanguage))
    }

    @ObservedObject private var queue = DownloadQueue.shared

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CatalogView(queue: queue)
                } label: {
                    HStack {
                        Label("Get Mods", systemImage: "arrow.down.circle")
                        Spacer()
                        if queue.isBusy {
                            ProgressView()
                        } else if !queue.catalog.updates.isEmpty {
                            Text("\(queue.catalog.updates.count) update\(queue.catalog.updates.count == 1 ? "" : "s")")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                Text("Browse 7th Heaven's catalogs and download mods into FF7Recomp › Mods.")
            }
            if !model.report.lines.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(model.report.lines) { w in
                            Label(w.text, systemImage: w.serious ? "exclamationmark.triangle.fill" : "info.circle")
                                .font(.caption)
                                .foregroundStyle(w.serious ? .orange : .secondary)
                        }
                    } label: {
                        Label(reportTitle, systemImage: model.report.problems > 0 ? "exclamationmark.triangle.fill" : "square.on.square")
                            .foregroundStyle(model.report.problems > 0 ? .orange : .primary)
                    }
                }
            }
            if model.mods.isEmpty {
                ContentUnavailableView {
                    Label("No mods", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Get mods from 7th Heaven's catalogs above, import .iro archives or mod folders, or put them in FF7Recomp › Mods in the Files app.")
                } actions: {
                    Button("Import Mods…") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    ForEach(model.mods) { mod in
                        ModRow(mod: mod, notes: model.report.perMod[mod.fileName.lowercased()] ?? [],
                               update: queue.catalog.installedByFile(mod.fileName).flatMap { queue.catalog.byID($0.id) }
                                   .map(queue.catalog.updateAvailable) ?? false) { model.setEnabled(mod, $0) }
                    }
                    .onMove(perform: model.move)
                    .onDelete(perform: model.delete)
                } header: {
                    Text("\(model.enabledCount) of \(model.mods.count) enabled")
                } footer: {
                    Text("Higher in the list wins when two mods replace the same file. Tap Edit to reorder. Changes apply the next time the game starts.")
                }
            }
        }
        .navigationTitle("Mods")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.importing { ProgressView() }
                if !model.mods.isEmpty { EditButton() }
                Menu {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Mods…", systemImage: "square.and.arrow.down")
                    }
                    #if DEBUG
                    Button("Add sample mods (debug)") { model.addSampleMods() }
                    #endif
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add mods")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.iroArchive, .folder],
            allowsMultipleSelection: true
        ) { result in
            model.handleImport(result)
        }
        .alert("Mods", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .refreshable { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .ff7ModsChanged)) { _ in model.reload() }
    }

    private var reportTitle: String {
        let r = model.report
        if r.problems > 0 { return "\(r.problems) problem\(r.problems == 1 ? "" : "s") with your mods" }
        return "\(r.overlaps) overlap\(r.overlaps == 1 ? "" : "s") between mods"
    }
}

private struct ModRow: View {
    let mod: ModItem
    var notes: [String] = []
    var update = false
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { mod.enabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if update {
                    Text("Update available in Get Mods").font(.caption2.bold()).foregroundStyle(.orange)
                }
                ForEach(notes.prefix(2), id: \.self) { n in
                    Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let category = mod.info?.category { parts.append(category) }
        if let author = mod.info?.author { parts.append(author) }
        if let version = mod.info?.version { parts.append("v\(version)") }
        parts.append(mod.kind == .iro ? mod.fileName : mod.kind.rawValue)
        return parts.joined(separator: " · ")
    }
}
