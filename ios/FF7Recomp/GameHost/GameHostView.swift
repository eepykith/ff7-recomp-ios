import SwiftUI

/// Play surface. FF7MetalView presents a CAMetalLayer that FFNx draws into once the lifted game
/// is linked (FF7RecompBundled); without it the layer clears to a status color.
///
/// Landscape only: FFNx sizes its swapchain once at boot and pillarboxes its 4:3 frame only in
/// a wide window, so the view locks to landscape and boots when the layer is landscape-sized.
struct GameHostView: View {
    let packagePath: String?

    @State private var status = "Starting…"
    @State private var showStatus = true
    @State private var booted = false

    var body: some View {
        ZStack {
            MetalSurfaceView()
                .ignoresSafeArea()

            VStack {
                if showStatus {
                    Text(status)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                Spacer()
                TouchPadView()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            OrientationLock.set(.landscape)
            PadInput.shared.startControllers()
        }
        .task { await bootWhenLandscape() }
        .onDisappear {
            PadInput.shared.stopControllers()
            EngineBridge.shutdown()
            OrientationLock.set(.all)
        }
    }

    /// Waits (up to 3 s) for the Metal layer to report a landscape size, then boots once.
    private func bootWhenLandscape() async {
        guard !booted else { return }
        for _ in 0..<60 {
            var w: Int32 = 0, h: Int32 = 0
            _ = ff7_platform_window(&w, &h)
            if w > h && w > 0 { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        booted = true
        let probe = EngineBridge.probe(width: 1920, height: 1080, fps: 60)
        let result = EngineBridge.boot(packagePath: packagePath)
        status = result.message.isEmpty ? probe.message : result.message
        if result.booted {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { showStatus = false }
        }
    }
}

private struct MetalSurfaceView: UIViewRepresentable {
    func makeUIView(context: Context) -> FF7MetalView {
        FF7MetalView(frame: .zero)
    }

    func updateUIView(_ uiView: FF7MetalView, context: Context) {}
}
