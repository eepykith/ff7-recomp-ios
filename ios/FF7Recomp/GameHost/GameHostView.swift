import SwiftUI

/// Play surface. FF7MetalView presents a CAMetalLayer that FFNx draws into once the lifted game
/// is linked (FF7RecompBundled); without it the layer clears to a status color.
///
/// The Metal view is sized to the game's 4:3 picture (PlayLayout), with the on-screen pad in the
/// columns beside it. When the screen changes size (iPhone Duo folding, split screen) the view
/// follows and FFNx resets its swapchain to the new size (FF7_IOS_SURFACE_RESIZE).
///
/// Landscape only: the view locks to landscape and boots when the layer is landscape-sized.
struct GameHostView: View {
    let packagePath: String?

    @Environment(\.dismiss) private var dismiss
    @State private var status = "Starting…"
    @State private var showStatus = true
    @State private var booted = false
    @State private var confirmQuit = false

    var body: some View {
        GeometryReader { safeGeo in
            let safe = safeGeo.safeAreaInsets
            GeometryReader { geo in
                let layout = PlayLayout(size: geo.size, safe: safe)
                ZStack(alignment: .topLeading) {
                    Color.black

                    MetalSurfaceView()
                        .frame(width: layout.picture.width, height: layout.picture.height)
                        .offset(x: layout.picture.minX, y: layout.picture.minY)

                    if showStatus {
                        Text(status)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .frame(width: layout.picture.width)
                            .offset(x: layout.picture.minX, y: layout.picture.minY + 8)
                            .transition(.opacity)
                    }

                    TouchPadView(layout: layout) { confirmQuit = true }
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("Quit to the launcher?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { dismiss() }
        } message: {
            Text("Progress since your last save is lost.")
        }
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
