import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherModel

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

            Section("About") {
                LabeledContent("Version") {
                    Text(model.engineVersion)
                }
                Text("Sideload only. You need your own Steam copy of FINAL FANTASY VII. Not affiliated with Square Enix.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
