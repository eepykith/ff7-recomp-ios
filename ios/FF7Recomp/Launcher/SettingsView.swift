import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmRemove = false
    @AppStorage(TouchPadMode.key) private var touchPadMode = TouchPadMode.auto

    var body: some View {
        Form {
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
            } header: {
                Text("Controls")
            } footer: {
                Text("A connected game controller plays the game either way; the on-screen pad and any controller work together.")
            }

            Section("Game files") {
                LabeledContent("Files", value: model.hasFiles ? "Here" : "Not here")
                LabeledContent("Game build", value: model.hasGameCode ? "Built in" : "Not built")
                Button("Game files…") { model.showSetup() }
                Button("Remove game files", role: .destructive) { confirmRemove = true }
                    .disabled(model.filesState == .missing)
            }

            Section("About") {
                LabeledContent("Engine", value: model.engineVersion)
                Text("Sideload only. You need your own Steam copy of FINAL FANTASY VII. Not affiliated with Square Enix.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove the game files?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove game files", role: .destructive) { model.removeFiles() }
        } message: {
            Text("ff7_en.exe and the data folder are deleted from this iPhone. Mods, saves and save states are kept.")
        }
    }
}
