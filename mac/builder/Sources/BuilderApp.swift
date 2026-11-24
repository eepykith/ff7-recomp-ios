import SwiftUI

@main
struct BuilderApp: App {
    var body: some Scene {
        WindowGroup("FF7Recomp Builder") {
            BuilderView()
                .frame(minWidth: 620, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
