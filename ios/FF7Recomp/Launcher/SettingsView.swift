import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmRemove = false
    @AppStorage(TouchPadMode.key) private var touchPadMode = TouchPadMode.auto
    @AppStorage(LauncherAppearance.key) private var appearance = LauncherAppearance.system
    @State private var showButtons = false
    @State private var editLayout = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(LauncherAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone's light or dark setting.")
            }

            Section {
                Picker("Frame rate", selection: $model.frameRate) {
                    ForEach(FrameRate.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Display")
            } footer: {
                Text(model.frameRate.detail + " Applies the next time the game starts.")
            }

            Section {
                Picker("On-screen pad", selection: $touchPadMode) {
                    ForEach(TouchPadMode.allCases) { Text($0.label).tag($0) }
                }
                Button("Buttons shown…") { showButtons = true }
                Button("Size and layout…") { editLayout = true }
            } header: {
                Text("Controls")
            } footer: {
                Text("A connected game controller plays the game either way; the on-screen pad and any controller work together. Size and layout is kept for each way you hold the iPhone.")
            }

            Section("Game files") {
                LabeledContent("Files", value: model.hasFiles ? "Here" : "Not here")
                LabeledContent("Game build", value: model.hasGameCode ? "Built in" : "Not built")
                Button("Game files…") { model.showSetup() }
                Button("Remove game files", role: .destructive) { confirmRemove = true }
                    .disabled(model.filesState == .missing)
            }

            Section {
                LogShareButton()
                Link(destination: LogBundle.reportURL()) {
                    Label("Report a problem", systemImage: "exclamationmark.bubble")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("Share logs packs the game's logs, this iPhone's model and iOS version, and your mods into a zip: attach it to a report on GitHub. Nothing is sent unless you share it. The logs are also in Files › On My iPhone › FF7Recomp › Logs.")
            }

            Section("About") {
                LabeledContent("Engine", value: model.engineVersion)
                Text("Sideload only. You need your own Steam copy of FINAL FANTASY VII. Not affiliated with Square Enix.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showButtons) { ButtonsShownView() }
        .fullScreenCover(isPresented: $editLayout) { PadLayoutEditor() }
        .confirmationDialog("Remove the game files?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove game files", role: .destructive) { model.removeFiles() }
        } message: {
            Text("ff7_en.exe and the data folder are deleted from this iPhone. Mods, saves and save states are kept.")
        }
    }
}

/// Settings > Share logs: zips the logs (LogBundle) and opens the share sheet.
struct LogShareButton: View {
    var title = "Share logs"
    @State private var zip: URL?
    @State private var error: String?

    var body: some View {
        Button {
            do { zip = try LogBundle.makeZip() } catch { self.error = error.localizedDescription }
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
        .sheet(item: $zip) { url in
            ShareSheet(items: [url]).ignoresSafeArea()
        }
        .alert("Couldn't pack the logs", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// The system share sheet (AirDrop, Save to Files, Mail, Messages, ...).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Settings > Buttons shown: which parts of the on-screen pad are drawn. A hidden button still
/// works on a game controller.
struct ButtonsShownView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PadSettings.shownKey) private var hiddenList = ""

    var body: some View {
        let shown = PadSettings.shown(hiddenList)
        NavigationStack {
            List {
                Section {
                    ForEach(PadElement.allCases) { el in
                        Toggle(el.label, isOn: Binding {
                            shown.contains(el)
                        } set: { on in
                            var s = shown
                            if on { s.insert(el) } else { s.remove(el) }
                            hiddenList = PadSettings.hiddenList(s)
                        })
                    }
                } footer: {
                    Text("Hidden buttons still work on a game controller.")
                }
            }
            .navigationTitle("Buttons shown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Show all") { hiddenList = "" }.disabled(hiddenList.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
