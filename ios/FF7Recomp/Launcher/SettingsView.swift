import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section("Display") {
                Picker("Frame rate", selection: $model.targetFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                Text("Widescreen / CRT land in later milestones.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
