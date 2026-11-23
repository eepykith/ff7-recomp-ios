import SwiftUI

@main
struct FF7RecompApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LauncherRootView()
        }
    }
}
