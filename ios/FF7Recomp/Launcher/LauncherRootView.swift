import SwiftUI

/// Root: game setup until the game files are here and the game is built in, then the launcher home.
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
                Section {
                    Button {
                        model.play()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                    }
                    .disabled(!model.canPlay)

                    Button {
                        model.showSetup()
                    } label: {
                        Label("Game files", systemImage: "externaldrive")
                    }

                    NavigationLink {
                        ModsView(library: model.modLibrary, gameLanguage: nil)
                    } label: {
                        Label("Mods", systemImage: model.modsUnlocked ? "puzzlepiece.extension" : "lock.fill")
                    }
                    .disabled(!model.modsUnlocked)

                    NavigationLink {
                        SettingsView(model: model)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } footer: {
                    if !model.modsUnlocked {
                        Text("Mods unlock once the game files are confirmed.")
                    }
                }
            }
            .navigationTitle("FF7Recomp")
            .navigationDestination(isPresented: $model.playing) {
                GameHostView(gameDir: model.paths.game.path)
            }
        }
    }
}

#Preview {
    LauncherRootView()
}
