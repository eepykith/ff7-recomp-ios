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

    /// Moves one mod by `by` places (negative: up, toward winning), or to the top.
    func move(_ mod: ModItem, by: Int) {
        guard let i = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        let to = max(0, min(mods.count - 1, i + by))
        guard to != i else { return }
        let m = mods.remove(at: i)
        mods.insert(m, at: to)
        save()
    }

    /// A drag that ended (iOS 27's reorderable list): the dragged mods go before `before`, or last.
    func reorder(moving ids: [String], before: String?) {
        let moving = Set(ids)
        guard !moving.isEmpty else { return }
        var moved: [ModItem] = []
        mods.removeAll { m in
            guard moving.contains(m.id) else { return false }
            moved.append(m)
            return true
        }
        let at = before.flatMap { id in mods.firstIndex { $0.id == id } } ?? mods.endIndex
        mods.insert(contentsOf: moved, at: at)
        save()
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            do { try library.remove(mods[i].fileName) } catch { errorMessage = error.localizedDescription }
        }
        mods.remove(atOffsets: offsets)
        save()
        DownloadQueue.shared.libraryChanged()      // the catalog no longer counts it as installed
    }

    func delete(_ mod: ModItem) {
        guard let i = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        delete(at: IndexSet(integer: i))
    }

    /// Set one of a mod's options (saved in the profile; the game reads it when it starts).
    func setOption(_ mod: ModItem, _ option: ModOptionDef, _ value: Int) {
        guard let i = mods.firstIndex(where: { $0.id == mod.id }) else { return }
        mods[i].options.removeAll { $0.id == option.id }
        if value != option.defaultValue { mods[i].options.append(.init(id: option.id, value: value)) }
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
    @State private var optionsFor: ModItem?
    @State private var deleting: ModItem?

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
                    if #available(iOS 27, *) {
                        // drag a mod to move it, no Edit mode (iOS 27)
                        ForEach(model.mods) { mod in row(mod) }
                            .reorderable()
                            .onDelete(perform: model.delete)
                    } else {
                        ForEach(model.mods) { mod in row(mod) }
                            .onMove(perform: model.move)
                            .onDelete(perform: model.delete)
                    }
                } header: {
                    Text("Load order · \(model.enabledCount) of \(model.mods.count) on")
                } footer: {
                    Text(reorderHelp + " Where two mods replace the same game file, the higher one wins (shown under each mod). Changes apply the next time the game starts.")
                }
            }
        }
        .modifier(ModReorder(model: model))
        .navigationTitle("Mods")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if model.importing { ProgressView() }
                if #unavailable(iOS 27), !model.mods.isEmpty { EditButton() }
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
        .sheet(item: $optionsFor) { mod in
            NavigationStack { ModOptionsView(model: model, modID: mod.id) }
        }
        .confirmationDialog("Delete \(deleting?.displayName ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let m = deleting { model.delete(m) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("It's removed from FF7Recomp › Mods. You can download it again from Get Mods.")
        }
    }

    private var reorderHelp: String {
        if #available(iOS 27, *) { return "Touch and hold a mod, then drag it to change the order; or touch and hold for Move up and Move down." }
        return "Tap Edit to drag mods into order, or touch and hold a mod for Move up and Move down."
    }

    private func row(_ mod: ModItem) -> some View {
        let position = (model.mods.firstIndex { $0.id == mod.id } ?? 0) + 1
        return ModRow(mod: mod, position: position, count: model.mods.count,
                      onOptions: { optionsFor = mod }, onDelete: { deleting = mod },
                      onMove: { model.move(mod, by: $0) },
                      notes: model.report.perMod[mod.fileName.lowercased()] ?? [],
                      update: queue.catalog.installedByFile(mod.fileName).flatMap { queue.catalog.byID($0.id) }
                          .map(queue.catalog.updateAvailable) ?? false) { model.setEnabled(mod, $0) }
    }

    private var reportTitle: String {
        let r = model.report
        if r.problems > 0 { return "\(r.problems) problem\(r.problems == 1 ? "" : "s") with your mods" }
        return "\(r.overlaps) overlap\(r.overlaps == 1 ? "" : "s") between mods"
    }
}

private struct ModRow: View {
    let mod: ModItem
    var position = 0
    var count = 0
    var onOptions: () -> Void = {}
    var onDelete: () -> Void = {}
    var onMove: (Int) -> Void = { _ in }
    var notes: [String] = []
    var update = false
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { mod.enabled }, set: onToggle)) {
            HStack(alignment: .top, spacing: 10) {
            Text("\(position)")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(mod.enabled ? Color.accentColor : Color.secondary)
                .frame(minWidth: 18)
                .padding(.top, 2)
                .accessibilityLabel("Position \(position)")
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
                if let n = mod.info?.options.count, n > 0 {
                    Text("\(n) option\(n == 1 ? "" : "s") · touch and hold to change")
                        .font(.caption2).foregroundStyle(.tint).lineLimit(1)
                }
            }
            }
        }
        .contextMenu {
            Button(action: onOptions) {
                Label((mod.info?.options.isEmpty ?? true) ? "About this mod" : "Options…", systemImage: "slider.horizontal.3")
            }
            if position > 1 {
                Button { onMove(-count) } label: { Label("Move to top", systemImage: "arrow.up.to.line") }
                Button { onMove(-1) } label: { Label("Move up", systemImage: "arrow.up") }
            }
            if position < count {
                Button { onMove(1) } label: { Label("Move down", systemImage: "arrow.down") }
            }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
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

/// A mod's settings (7th Heaven's configuration screen): switches and choices from its mod.xml,
/// saved in the profile; the game applies them when it starts.
private struct ModOptionsView: View {
    @ObservedObject var model: ModsModel
    let modID: String
    @Environment(\.dismiss) private var dismiss

    private var mod: ModItem? { model.mods.first { $0.id == modID } }

    var body: some View {
        List {
            if let mod {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mod.displayName).font(.headline)
                        let facts = [mod.info?.category, mod.info?.author, mod.info?.version.map { "v\($0)" }].compactMap { $0 }
                        if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        if let d = mod.info?.description, !d.isEmpty {
                            Text(d).font(.callout).padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Switched on", isOn: Binding(get: { mod.enabled }, set: { model.setEnabled(mod, $0) }))
                }
                let options = mod.info?.options ?? []
                if options.isEmpty {
                    Section { Text("This mod has no options.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        ForEach(options) { option in
                            OptionRow(option: option, value: mod.value(of: option)) { model.setOption(mod, option, $0) }
                        }
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("Changes apply the next time the game starts.")
                    }
                    if mod.options.contains(where: { o in options.contains { $0.id == o.id } }) {
                        Section {
                            Button("Reset to defaults") {
                                for o in options { model.setOption(mod, o, o.defaultValue) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

private struct OptionRow: View {
    let option: ModOptionDef
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if option.isBool {
                Toggle(option.name, isOn: Binding(get: { value != 0 }, set: { onChange($0 ? 1 : 0) }))
            } else {
                Picker(option.name, selection: Binding(get: { value }, set: onChange)) {
                    ForEach(option.values, id: \.value) { v in Text(v.name).tag(v.value) }
                    if !option.values.contains(where: { $0.value == value }) { Text("\(value)").tag(value) }
                }
            }
            if !option.description.isEmpty {
                Text(option.description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// iOS 27: the list takes drags to reorder mods (with .reorderable() on its ForEach).
private struct ModReorder: ViewModifier {
    let model: ModsModel
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.reorderContainer(for: ModItem.self) { difference in
                let before: String?
                switch difference.destination.position {
                case .before(let id): before = id
                case .end: before = nil
                }
                model.reorder(moving: difference.sources, before: before)
            }
        } else {
            content
        }
    }
}
