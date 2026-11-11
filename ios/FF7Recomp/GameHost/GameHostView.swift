import SwiftUI

/// Play surface. FF7MetalView presents a CAMetalLayer; FFNx will draw into it
/// once the lifted game is linked. Until then the layer clears to a status color.
struct GameHostView: View {
    let packagePath: String?

    @State private var status = "Starting…"

    var body: some View {
        ZStack(alignment: .bottom) {
            MetalSurfaceView()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(status)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

                TouchPadView()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Play")
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: boot)
        .onDisappear {
            EngineBridge.setPad(buttons: 0)
            EngineBridge.shutdown()
        }
    }

    private func boot() {
        let probe = EngineBridge.probe(width: 1920, height: 1080, fps: 60)
        let result = EngineBridge.boot(packagePath: packagePath)
        status = result.message.isEmpty ? probe.message : result.message
    }
}

private struct MetalSurfaceView: UIViewRepresentable {
    func makeUIView(context: Context) -> FF7MetalView {
        FF7MetalView(frame: .zero)
    }

    func updateUIView(_ uiView: FF7MetalView, context: Context) {}
}
