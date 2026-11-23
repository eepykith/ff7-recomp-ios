import SwiftUI

/// First launch: explains the Mac build step and imports the resulting GamePackage.
struct GameSetupView: View {
    @ObservedObject var model: AppModel
    @State private var showImporter = false

    private let command = #"python3 -m ff7recomp_mac build-package "<Steam FF7 folder>" -o FF7.ff7pkg"#

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    steps
                    StatusCard(status: model.setupStatus)
                    actions
                    Text("You need your own Steam copy of FINAL FANTASY VII. This app ships no game files and is not affiliated with Square Enix.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Game setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Back to the launcher when it can still play (a package, or the bundled dev game; e.g. a replacement
                // import failed); the ready state has its own Continue button.
                if model.canPlay, !isReady, !model.isWorking {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { model.continueToLauncher() }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.ff7Package, .zip, .folder],
                allowsMultipleSelection: false
            ) { result in
                model.handleImport(result)
            }
        }
    }

    private var isReady: Bool {
        if case .ready = model.setupStatus { return true }
        return false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Set up your game")
                .font(.largeTitle.bold())
            Text("iOS can't compile code on the device, so the game is built on a Mac from your own copy and then imported here.")
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepRow(number: 1, title: "Build on your Mac") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run the companion from the repository's `mac/` folder, pointing it at your Steam install:")
                    Text(command)
                        .font(.caption.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            StepRow(number: 2, title: "Copy it to this device") {
                Text("Send the .ff7pkg with AirDrop, iCloud Drive, or Finder's Files tab.")
            }
            StepRow(number: 3, title: "Import it") {
                Text("The app checks the manifest and every file's SHA-256 before installing.")
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if isReady {
                Button {
                    model.continueToLauncher()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Import a different package…") { showImporter = true }
                    .disabled(model.isWorking)
            } else {
                Button {
                    showImporter = true
                } label: {
                    Label("Import GamePackage", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isWorking)
            }

            #if DEBUG
            Button("Install sample package (debug)") { model.installSamplePackage() }
                .font(.footnote)
                .disabled(model.isWorking)
            #endif
        }
    }
}

private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                content.foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusCard: View {
    let status: AppModel.SetupStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .notInstalled:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .working:
            ProgressView()
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch status {
        case .notInstalled: return "No game installed"
        case .working(let stage): return stage.rawValue
        case .ready: return "Ready to play"
        case .failed: return "Import failed"
        }
    }

    private var detail: String? {
        switch status {
        case .notInstalled:
            return "Import a GamePackage built by the Mac companion."
        case .working:
            return "Large packages can take a minute."
        case .ready(let pkg):
            var lines = ["Build \(pkg.manifest.buildID) · \(pkg.manifest.language.uppercased()) · core \(pkg.manifest.coreVersion)"]
            if pkg.isStub { lines.append("Stub package: no game code yet (P3).") }
            return lines.joined(separator: "\n")
        case .failed(let message):
            return message
        }
    }
}

#Preview {
    GameSetupView(model: AppModel())
}
