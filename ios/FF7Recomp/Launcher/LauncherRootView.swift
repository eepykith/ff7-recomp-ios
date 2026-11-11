import SwiftUI

struct LauncherRootView: View {
    @StateObject private var model = LauncherModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Game") {
                    NavigationLink("Play") {
                        GameHostView(packagePath: model.packagePath)
                    }
                    .disabled(!model.canAttemptPlay)

                    LabeledContent("Package") {
                        Text(model.packageLabel)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button("Import GamePackage…") {
                        model.showImporter = true
                    }
                }

                Section("Library") {
                    NavigationLink("Mods") {
                        PlaceholderScreen(
                            title: "Mods",
                            detail: "P4 — import .iro / folders through the shared C++ mod layer."
                        )
                    }
                    NavigationLink("Save states") {
                        PlaceholderScreen(
                            title: "Save states",
                            detail: "P2 — same .ff7s format as Android."
                        )
                    }
                }

                Section("System") {
                    NavigationLink("Settings") {
                        SettingsView(model: model)
                    }
                    LabeledContent("Engine") {
                        Text(model.engineVersion)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = model.statusMessage {
                    Section("Status") {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("FF7Recomp")
            .fileImporter(
                isPresented: $model.showImporter,
                allowedContentTypes: [.ff7Package, .zip, .data],
                allowsMultipleSelection: false
            ) { result in
                model.handleImport(result)
            }
        }
        .onAppear { model.refresh() }
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .navigationTitle(title)
    }
}

#Preview {
    LauncherRootView()
}
