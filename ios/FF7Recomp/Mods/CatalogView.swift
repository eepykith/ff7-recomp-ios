import SwiftUI

/// Get Mods: browse 7th Heaven's catalogs, install and update mods (in the background, one at
/// a time), as the Android launcher does.
struct CatalogView: View {
    @ObservedObject var queue: DownloadQueue
    @State private var query = ""
    @State private var category: String?
    @State private var filter = Filter.all
    @State private var results: [CatalogMod] = []
    @State private var refreshing = false
    @State private var problem: String?
    @State private var showCatalogs = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", installed = "Installed", updates = "Updates"
        var id: String { rawValue }
    }

    var body: some View {
        List {
            if !queue.items.isEmpty {
                Section {
                    ForEach(queue.items) { item in
                        QueueRow(item: item) { queue.cancel(item) }
                    }
                } header: {
                    HStack {
                        Text("Downloads")
                        Spacer()
                        if queue.items.contains(where: \.finished) {
                            Button("Clear") { queue.clearFinished() }.font(.caption)
                        }
                    }
                } footer: {
                    if queue.isBusy {
                        Text("Downloads go on while you browse. If you leave FF7Recomp, a download that's cut off resumes the next time you open it.")
                    }
                }
            }

            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if results.isEmpty {
                    if refreshing {
                        HStack { ProgressView(); Text("Getting the catalogs…").foregroundStyle(.secondary) }
                    } else if queue.catalog.mods.isEmpty {
                        ContentUnavailableView("No catalogs yet", systemImage: "books.vertical",
                                               description: Text("Pull down to get 7th Heaven's catalogs (needs the internet)."))
                    } else {
                        Text(filter == .updates ? "Your catalog mods are up to date." : "No mods match.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(results) { mod in
                    NavigationLink {
                        CatalogModView(mod: mod, queue: queue)
                    } label: {
                        CatalogRow(mod: mod, queue: queue)
                    }
                }
            } header: {
                if !results.isEmpty { Text(results.count == 1 ? "1 mod" : "\(results.count) mods") }
            } footer: {
                Text("Mods come from 7th Heaven's catalogs and their authors' sites. FF7Recomp doesn't host them; check each mod's page for what it needs.")
            }
        }
        .navigationTitle("Get Mods")
        .searchable(text: $query, prompt: "Name, author, tag")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(String?.none)
                        ForEach(ModCatalog.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    Image(systemName: category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Category")
                Menu {
                    Button { Task { await refresh(force: true) } } label: { Label("Check for new mods", systemImage: "arrow.clockwise") }
                    Button { showCatalogs = true } label: { Label("Catalogs…", systemImage: "books.vertical") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await refresh(force: true) }
        .task { await refresh(force: false) }
        .onAppear { queue.libraryChanged(); search() }
        .onChange(of: query) { search() }
        .onChange(of: category) { search() }
        .onChange(of: filter) { search() }
        .onReceive(NotificationCenter.default.publisher(for: .ff7ModsChanged)) { _ in search() }
        .sheet(isPresented: $showCatalogs, onDismiss: { Task { await refresh(force: false) } }) {
            NavigationStack { CatalogsView(catalog: queue.catalog) }
        }
        .alert("Catalogs", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }

    private func refresh(force: Bool) async {
        search()
        refreshing = true
        let catalog = queue.catalog
        let issue = await catalog.refresh(force: force)
        refreshing = false
        if force || catalog.mods.isEmpty { problem = issue }
        search()
    }

    private func search() {
        let c = queue.catalog
        var list = c.search(query, category: category, installedOnly: filter != .all)
        if filter == .updates { list = list.filter(c.updateAvailable) }
        results = list
    }
}

private struct CatalogRow: View {
    let mod: CatalogMod
    @ObservedObject var queue: DownloadQueue

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name).lineLimit(1)
                Text([mod.category, mod.author, mod.sizeText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            status
        }
    }

    @ViewBuilder private var status: some View {
        if let item = queue.item(for: mod), !item.finished {
            if let f = item.fraction, item.state == .running {
                ProgressView(value: f).frame(width: 44)
            } else {
                ProgressView()
            }
        } else if queue.catalog.updateAvailable(mod) {
            Text("Update").font(.caption.bold()).foregroundStyle(.orange)
        } else if queue.catalog.installedOf(mod) != nil {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Installed")
        } else if mod.needsBrowser {
            Image(systemName: "safari").foregroundStyle(.secondary).accessibilityLabel("Download from its page")
        }
    }
}

private struct QueueRow: View {
    let item: DownloadQueue.Item
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.mod.name).lineLimit(1)
                Spacer()
                if !item.finished {
                    Button(role: .destructive, action: onCancel) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cancel \(item.mod.name)")
                }
            }
            switch item.state {
            case .queued:
                Text("Waiting").font(.caption).foregroundStyle(.secondary)
            case .running:
                if let f = item.fraction {
                    ProgressView(value: f)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            case .done:
                Label(item.update ? "Updated" : "Installed and switched on", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            case .cancelled:
                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let total = item.total > 0 ? item.total : item.mod.sizeKB * 1024
        var s = item.phase
        if item.done > 0 { s += " \(ByteFormat.human(item.done))" + (total > 0 ? " of \(ByteFormat.human(total))" : "") }
        return s
    }
}

/// One catalog mod: what it is, and Install / Update.
struct CatalogModView: View {
    let mod: CatalogMod
    @ObservedObject var queue: DownloadQueue
    @Environment(\.openURL) private var openURL
    @State private var confirm: [ModConflicts.Warning]?

    var body: some View {
        List {
            if let url = previewURL {
                Section {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else if phase.error != nil {
                            EmptyView()
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mod.name).font(.title3.bold())
                    Text(facts).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                action
            }
            if !queue.requirements(of: mod).isEmpty || mod.requirements.contains(where: { queue.catalog.byID($0.id) == nil }) {
                Section("Needs") {
                    ForEach(Array(mod.requirements.enumerated()), id: \.offset) { _, r in
                        let need = queue.catalog.byID(r.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(need?.name ?? r.description.ifEmpty("Another mod"))
                            Text(need.map { queue.catalog.installedOf($0) != nil ? "Installed" : "Installed with this mod" }
                                 ?? "Not in your catalogs: install it yourself")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !mod.description.isEmpty {
                Section("About") { Text(mod.description).font(.callout) }
            }
            if !mod.releaseNotes.isEmpty {
                Section("What's new in \(mod.versionText)") { Text(mod.releaseNotes).font(.callout) }
            }
            if let page = URL(string: mod.infoLink), page.scheme?.hasPrefix("http") == true {
                Section {
                    Link(destination: page) { Label("Mod page", systemImage: "safari") }
                }
            }
        }
        .navigationTitle(mod.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Install \(mod.name)?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button("Install anyway") { queue.add(mod); confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: {
            Text((confirm ?? []).map(\.text).joined(separator: "\n\n"))
        }
    }

    private var previewURL: URL? {
        guard let u = URL(string: mod.preview), u.scheme?.hasPrefix("http") == true else { return nil }
        return u
    }

    private var facts: String {
        var parts = [mod.category, mod.author]
        if !mod.versionText.isEmpty { parts.append("v\(mod.versionText)") }
        if !mod.sizeText.isEmpty { parts.append(mod.sizeText) }
        parts.append(mod.catalog)
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var action: some View {
        let installed = queue.catalog.installedOf(mod)
        if let item = queue.item(for: mod), !item.finished {
            HStack {
                ProgressView()
                Text(item.state == .running ? item.phase : "Waiting").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .destructive) { queue.cancel(item) }
            }
        } else if mod.needsBrowser {
            Button {
                if let u = mod.browserLink { openURL(u) }
            } label: {
                Label("Download from its page", systemImage: "safari")
            }
            Text("This mod is shared on a site that needs a browser (Mega, a forum). Download it there, then add it in Mods with + › Import Mods.")
                .font(.caption).foregroundStyle(.secondary)
        } else if let installed, queue.catalog.updateAvailable(mod) {
            Button { queue.add(mod) } label: {
                Label("Update to \(mod.versionText) (you have \(installed.version))", systemImage: "arrow.down.circle")
            }
        } else if installed != nil {
            Label("Installed (\(installed?.version ?? ""))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Button { queue.add(mod) } label: { Label("Download again", systemImage: "arrow.clockwise") }
        } else {
            Button {
                let wanted = queue.requirements(of: mod).filter { queue.catalog.installedOf($0) == nil } + [mod]
                let warnings = ModConflicts.beforeInstall(wanted, library: queue.library.load().mods, catalog: queue.catalog)
                if warnings.isEmpty { queue.add(mod) } else { confirm = warnings }
            } label: {
                Label("Install" + (mod.sizeText.isEmpty ? "" : " (\(mod.sizeText))"), systemImage: "arrow.down.circle.fill")
                    .font(.headline)
            }
        }
    }
}

/// The catalogs FF7Recomp reads: 7th Heaven's two defaults, and any you add (a catalog link
/// from a mod site, iros:// or https).
struct CatalogsView: View {
    let catalog: ModCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var subs: [ModCatalog.Subscription] = []
    @State private var name = ""
    @State private var link = ""
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                ForEach(subs) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                        Text(detail(s)).font(.caption).foregroundStyle(s.error == nil ? Color.secondary : Color.orange)
                    }
                    .deleteDisabled(catalog.isDefault(s))
                }
                .onDelete { offsets in
                    for i in offsets { catalog.removeSubscription(subs[i]) }
                    subs = catalog.subscriptions
                }
            } footer: {
                Text("7th Heaven's Qhimm and Sega catalogs are always here. Catalogs are checked again after a day.")
            }
            Section("Add a catalog") {
                TextField("Name (optional)", text: $name)
                TextField("Catalog link (iros://… or https://…)", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Add") {
                    if let p = catalog.addSubscription(name: name, link: link) {
                        problem = p
                    } else {
                        name = ""; link = ""
                        subs = catalog.subscriptions
                    }
                }
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Catalogs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { subs = catalog.subscriptions }
        .alert("Catalogs", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(problem ?? "") }
    }

    private func detail(_ s: ModCatalog.Subscription) -> String {
        if let e = s.error { return e }
        var parts = ["\(s.count) mods"]
        if let d = s.lastCheck { parts.append("checked " + d.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
