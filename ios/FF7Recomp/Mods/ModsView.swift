import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ModsModel: ObservableObject {
    @Published private(set) var mods: [ModItem] = []
    @Published var errorMessage: String?
    @Published private(set) var importing = false

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
        do {
            try library.save(mods, language: language)
        } catch {
            errorMessage = "Could not save the mod profile: \(error.localizedDescription)"
        }
    }
}

/// Imported 7th Heaven mods: enable/disable and priority order, saved to `mods/profile.xml`.
/// Applying them in-game is P4.
struct ModsView: View {
    @StateObject private var model: ModsModel
    @State private var showImporter = false

    init(library: ModLibrary, gameLanguage: String?) {
        _model = StateObject(wrappedValue: ModsModel(library: library, gameLanguage: gameLanguage))
    }

    var body: some View {
        List {
            if model.mods.isEmpty {
                ContentUnavailableView {
                    Label("No mods", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Import 7th Heaven .iro archives or mod folders. They are copied into the app.")
                } actions: {
                    Button("Import Mods…") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    ForEach(model.mods) { mod in
                        ModRow(mod: mod) { model.setEnabled(mod, $0) }
                    }
                    .onMove(perform: model.move)
                    .onDelete(perform: model.delete)
                } header: {
                    Text("\(model.enabledCount) of \(model.mods.count) enabled")
                } footer: {
                    Text("Higher in the list wins when two mods replace the same file. Tap Edit to reorder. Mods are applied in-game in a later update.")
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
    }
}

private struct ModRow: View {
    let mod: ModItem
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
