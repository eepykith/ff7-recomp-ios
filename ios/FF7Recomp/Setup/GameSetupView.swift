import SwiftUI

/// Setting the game up: FF7Recomp asks for the game files, checks them, confirms them, and
/// Play starts the game. (A build without the game in it also shows how the Mac builds it.)
struct GameSetupView: View {
    @ObservedObject var model: AppModel
    @State private var pickFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filesStatus
                    if model.filesBuiltIn {
                        EmptyView()
                    } else if let job = model.job {
                        JobRow(job: job) { model.cancelJob() }
                    } else {
                        Button {
                            pickFolder = true
                        } label: {
                            Label("Find my FF7 folder…", systemImage: "folder")
                        }
                    }
                } header: {
                    Text("Game files")
                } footer: {
                    if !model.filesBuiltIn {
                    Text("FF7Recomp needs the game files from your own Steam copy. Copy the FINAL FANTASY VII install folder to this iPhone (Files app: On My iPhone, a USB drive or iCloud Drive) and pick it here: the folder as Steam installs it today (\"FINAL FANTASY VII Steam Edition\", the one with ff7 inside). No patch or older version is needed; patched game files are not supported.")
                    }
                }

                if !model.hasGameCode {
                    Section {
                        buildStatus
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This build of FF7Recomp has no game in it. iOS can't compile code on the phone, so FF7Recomp Builder, a Mac app, builds the game from your own Steam copy into an IPA to install instead of this one (github.com/eepykith/ff7-recomp-ios, Releases).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Game build")
                    }
                }

                if model.hasFiles {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Game files confirmed", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("FINAL FANTASY VII 1.02 US (Steam)\(model.filesBuiltIn ? ", built into this app from your copy" : ""). ff7_en.exe checked (SHA-1 \(GameFiles.exeSHA1.prefix(8))…), with its data in English, French, German and Spanish. Mods are unlocked.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                model.play()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!model.canPlay || model.isWorking)
                        }
                        .padding(.vertical, 6)
                    } footer: {
                        Text("You need your own Steam copy of FINAL FANTASY VII. This app ships no game files and is not affiliated with Square Enix.")
                    }
                } else {
                    Section {
                    } footer: {
                        Text("You need your own Steam copy of FINAL FANTASY VII. This app ships no game files and is not affiliated with Square Enix.")
                    }
                }
            }
            .navigationTitle("Game setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.canPlay, !model.isWorking {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { model.continueToLauncher() }
                    }
                }
            }
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder],
                          allowsMultipleSelection: false) { result in
                model.importFolder(result)
            }
            .alert("Game files", isPresented: Binding(get: { model.message != nil },
                                                      set: { if !$0 { model.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.message ?? "")
            }
            .onAppear { model.refresh() }
        }
    }

    @ViewBuilder
    private var filesStatus: some View {
        switch model.filesState {
        case .ready:
            StatusRow(symbol: "checkmark.circle.fill", tint: .green, title: "Game files here",
                      detail: "FINAL FANTASY VII 1.02 (Steam), English, French, German and Spanish")
        case .wrongExe(let sha):
            StatusRow(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Not the right ff7_en",
                      detail: "Its SHA-1 starts \(sha)…; FF7Recomp is made from the 1.02 US build. Import the files again.")
        case .missing:
            StatusRow(symbol: "circle.dashed", tint: .secondary, title: "No game files yet", detail: nil)
        }
    }

    @ViewBuilder
    private var buildStatus: some View {
        if model.hasGameCode {
            StatusRow(symbol: "checkmark.circle.fill", tint: .green, title: "Built for this iPhone",
                      detail: "Engine \(model.engineVersion)")
        } else {
            StatusRow(symbol: "desktopcomputer", tint: .secondary, title: "Not built yet",
                      detail: model.hasFiles ? "Ready for the Mac build." : "The Mac build needs the game files first.")
        }
    }
}

private struct StatusRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct JobRow: View {
    let job: AppModel.Job
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.title).font(.headline)
                Spacer()
                Button("Stop", role: .destructive, action: onStop).buttonStyle(.borderless)
            }
            if let fraction = job.fraction {
                ProgressView(value: fraction)
                Text("\(job.detail): \(Int((fraction * 100).rounded())) %")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ProgressView()
                if !job.detail.isEmpty {
                    Text(job.detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GameSetupView(model: AppModel())
}
