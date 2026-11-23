import SwiftUI

/// Root: game setup until a GamePackage is installed, then the launcher home.
struct LauncherRootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            switch model.route {
            case .setup:
                GameSetupView(model: model)
                    .transition(.opacity)
            case .home:
                LauncherHomeView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.route)
    }
}

struct LauncherHomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let pkg = model.package {
                    Section {
                        PackageSummary(package: pkg)
                    }
                } else if let dir = model.bundledGameDir {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Bundled dev game", systemImage: "hammer.fill").font(.headline)
                            Text(dir).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    NavigationLink {
                        GameHostView(packagePath: model.playPackagePath)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                    }
                    .disabled(!model.canPlay)

                    NavigationLink {
                        ModsView(library: model.modLibrary, gameLanguage: model.package?.manifest.language)
                    } label: {
                        Label("Mods", systemImage: "puzzlepiece.extension")
                    }

                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } footer: {
                    if model.package?.isStub == true {
                        Text(model.bundledGameDir != nil
                             ? "Stub package without game code; Play boots the bundled dev game instead."
                             : "This is a stub package without game code; Play opens the engine surface only.")
                    }
                }
            }
            .navigationTitle("FF7Recomp")
        }
    }
}

private struct PackageSummary: View {
    let package: GamePackage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Game installed").font(.headline)
            }
            Text("Build \(package.manifest.buildID)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text("\(languageName(package.manifest.language)) · core \(package.manifest.coreVersion) · exe \(package.manifest.exeFingerprint)…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }
}

#Preview {
    LauncherRootView()
}
