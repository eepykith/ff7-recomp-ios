import SwiftUI

/// Root: game setup until the game files are here and the game is built in, then the launcher home.
struct LauncherRootView: View {
    @StateObject private var model = AppModel()
    @AppStorage(LauncherAppearance.key) private var appearance = LauncherAppearance.system

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
        .preferredColorScheme(appearance.colorScheme)
    }
}

/// Settings > Appearance: the launcher light, dark, or as the system is (the game is drawn
/// on black either way).
enum LauncherAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "ff7.appearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct LauncherHomeView: View {
    @ObservedObject var model: AppModel
    /// The last session ended in a crash and we haven't offered its logs yet.
    @State private var crashOffer = false
    @State private var crashZip: URL?
    @AppStorage("ff7.crashOffered") private var crashOffered = ""
    @Environment(\.openURL) private var openURL

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
            .onAppear {
                LogBundle.refreshFolder()
                if LogBundle.lastSessionCrashed(), let id = LogBundle.crashID(), id != crashOffered {
                    crashOffered = id
                    crashOffer = true
                }
            }
            .alert("FF7Recomp closed unexpectedly", isPresented: $crashOffer) {
                Button("Share logs") { crashZip = try? LogBundle.makeZip() }
                Button("Report a problem") { openURL(LogBundle.reportURL()) }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("The game crashed last time. Its logs say where: share them with a problem report on GitHub to help fix it.")
            }
            .sheet(item: $crashZip) { url in
                ShareSheet(items: [url]).ignoresSafeArea()
            }
            .navigationDestination(isPresented: $model.playing) {
                GameHostView(gameDir: model.paths.game.path)
            }
        }
    }
}

#Preview {
    LauncherRootView()
}
