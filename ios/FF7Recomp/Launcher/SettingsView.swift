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

            Section("Game package") {
                if let pkg = model.package {
                    LabeledContent("Build", value: pkg.manifest.buildID)
                    LabeledContent("Language", value: pkg.manifest.language.uppercased())
                    LabeledContent("Core", value: pkg.manifest.coreVersion)
                    LabeledContent("Executable") {
                        Text(pkg.manifest.exeFingerprint + "…").font(.body.monospaced())
                    }
                    if let created = pkg.manifest.createdAt {
                        LabeledContent("Built", value: created)
                    }
                }
                Button("Import a new package…") { model.showSetup() }
                Button("Remove game", role: .destructive) { confirmRemove = true }
                    .disabled(model.package == nil)
            }

            Section("About") {
                LabeledContent("Engine", value: model.engineVersion)
                Text("Sideload only. You need your own Steam copy of FINAL FANTASY VII. Not affiliated with Square Enix.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove the installed game?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove game", role: .destructive) { model.removeGame() }
        } message: {
            Text("The GamePackage is deleted from this device. Mods and saves are kept.")
        }
    }
}
