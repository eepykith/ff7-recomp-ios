import SwiftUI

/// P0: placeholder host that talks to the C engine stub.
/// P1 replaces the Color layer with an MTKView / CAMetalLayer surface.
struct GameHostView: View {
    let packagePath: String?

    @State private var status = "Starting…"
    @State private var canBoot = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Text("FF7Recomp")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)

                Text(status)
                    .font(.body.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if canBoot {
                    Text("Metal surface wiring is next (P1).")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Play")
        .onAppear(perform: boot)
        .onDisappear {
            EngineBridge.shutdown()
        }
    }

    private func boot() {
        let probe = EngineBridge.probe(width: 1920, height: 1080, fps: 60)
        let result = EngineBridge.boot(packagePath: packagePath)
        status = result.message.isEmpty ? probe.message : result.message
        canBoot = result.statusCode == 0
    }
}
