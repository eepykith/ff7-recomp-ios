import AVFoundation
import GameController
import SwiftUI

/// Play surface. FF7MetalView presents a CAMetalLayer that FFNx draws into once the lifted game
/// is linked (FF7RecompBundled); without it the layer clears to a status color.
///
/// The Metal view is sized to the game's picture, 4:3 or 16:9 (PlayLayout, AspectMode), with
/// the on-screen pad in the columns beside it. When the screen changes size (iPhone Duo folding, split screen) the view
/// follows and FFNx resets its swapchain to the new size (FF7_IOS_SURFACE_RESIZE).
///
/// Landscape only on phone-shaped screens. The iPhone Duo may also turn upright while its hinge
/// is open or half open (the hinge status, iOS 27.1), with the picture on top and the pad below;
/// shut, it goes back to landscape on the outer screen. Without a hinge, a large screen near 4:3
/// (an iPad) may turn upright too.
/// Boots when the Metal layer is wider than tall, which the 4:3 picture is either way.
struct GameHostView: View {
    let gameDir: String?

    @State private var status = "Starting…"
    @State private var showStatus = true
    @State private var booted = false
    @State private var confirmQuit = false
    /// true while the iPhone Duo's hinge is open or half open, false while shut; nil without a hinge.
    @State private var hingeOpen: Bool?
    @AppStorage("screenReflection") private var screenReflection = true
    @State private var controller = Self.hasGamepad()
    @AppStorage(TouchPadMode.key) private var touchPadMode = TouchPadMode.auto
    @State private var companion = CompanionSnapshot.empty
    @State private var note: String?
    @Environment(\.scenePhase) private var scenePhase
    /// A call (or another app's alarm, Siri) has taken the audio.
    @State private var audioInterrupted = false
    /// The guide in the status panel's place (upright on the iPhone Duo).
    @State private var guideInPanel = false
    /// The guide full screen over the paused game (no status panel on this screen).
    @State private var guideFull = false

    var body: some View {
        GeometryReader { safeGeo in
            let safe = safeGeo.safeAreaInsets
            GeometryReader { geo in
                let layout = PlayLayout(size: geo.size, safe: safe,
                                        padHidden: touchPadMode.hidesPad(controller: controller),
                                        aspect: AspectMode.playing.ratio)
                ZStack(alignment: .topLeading) {
                    Color.black

                    let reflect = screenReflection && hingeOpen == true && layout.panel != nil
                    MetalSurfaceView(reflection: reflect)
                        .frame(width: layout.picture.width, height: layout.picture.height)
                        .offset(x: layout.picture.minX, y: layout.picture.minY)

                    if reflect {
                        // the mirrored copy sits just below the picture; soften and fade it
                        let top = layout.picture.maxY
                        let light = touchPadMode.hidesPad(controller: controller)
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            LinearGradient(colors: [.black.opacity(light ? 0.25 : 0.45), .black],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .environment(\.colorScheme, .dark)
                        .frame(width: geo.size.width, height: max(0, geo.size.height - top))
                        .offset(x: 0, y: top)
                        .allowsHitTesting(false)
                    }

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

                    if let panel = layout.panel, guideInPanel {
                        GuideView(compact: true) { guideInPanel = false }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(width: panel.width, height: panel.height)
                            .offset(x: panel.minX, y: panel.minY)
                    } else if let panel = layout.panel {
                        CompanionPanel(state: companion)
                            .frame(width: panel.width, height: panel.height)
                            .overlay(alignment: .bottom) {
                                if let note {
                                    Text(note)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.38))
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(.black.opacity(0.7), in: Capsule())
                                        .padding(.bottom, 6)
                                        .transition(.opacity)
                                }
                            }
                            .offset(x: panel.minX, y: panel.minY)
                    }
                    if let deck = layout.deck {
                        CompanionDeck(state: companion, columns: layout.deckColumns) { text in
                            withAnimation { note = text }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                withAnimation { if note == text { note = nil } }
                            }
                        }
                        .frame(width: deck.width, height: deck.height)
                        .offset(x: deck.minX, y: deck.minY)
                    }

                    TouchPadView(layout: layout, guideOpen: guideInPanel && layout.panel != nil, onGuide: {
                        if layout.panel != nil { guideInPanel.toggle() } else { guideFull = true }
                    }) { confirmQuit = true }
                }
                .task(id: layout.panel != nil) {
                    // the panel's state, ten times a second while it is on screen
                    while layout.panel != nil && !Task.isCancelled {
                        let next = CompanionSnapshot.read()
                        if next != companion { companion = next }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                .onAppear {
                    lockOrientation(for: geo.size)
                    PadSettings.rememberInsets(safe, for: geo.size)
                }
                .onChange(of: geo.size) { PadSettings.rememberInsets(safe, for: geo.size) }
                .onChange(of: safe) { PadSettings.rememberInsets(safe, for: geo.size) }
                .onChange(of: allowsPortrait(geo.size)) { lockOrientation(for: geo.size) }
                .watchHinge { hingeOpen = $0 }
            }
            .ignoresSafeArea()
        }
        .background(Color.black)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $guideFull) {
            GuideView { guideFull = false }
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: guideFull) { updatePause() }
        .confirmationDialog("Quit the game?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { Self.quitGame() }
        } message: {
            Text("FF7Recomp closes. Open it again to play. Progress since your last save is lost.")
        }
        .onAppear {
            EventLog.write("play view open \(EventLog.audioState())")
            PadInput.shared.startControllers()
        }
        .task { await bootWhenLandscape() }
        // Paused by another app's audio (a picture-in-picture video, music) while FF7Recomp is in
        // front: iOS sends nothing when that audio stops, so look once a second and take the
        // sound back once nothing else plays (a call still holds it: reclaiming fails then)
        .task(id: audioInterrupted) {
            while audioInterrupted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard scenePhase == .active else { continue }
                let s = AVAudioSession.sharedInstance()
                if !s.isOtherAudioPlaying, !s.secondaryAudioShouldBeSilencedHint {
                    reclaimAudio(quiet: true)
                    updatePause()
                }
            }
        }
        #if DEBUG
        // FF7_TEST_INTERRUPT_AT=20: an audio interruption "began" 20 s in, with FF7Recomp in front
        // and nothing ended (another app's audio starting and stopping, as a PiP video does)
        .task {
            guard let at = Double(ProcessInfo.processInfo.environment["FF7_TEST_INTERRUPT_AT"] ?? "") else { return }
            try? await Task.sleep(for: .seconds(at))
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        }
        // FF7_TEST_SAVESTATE=s20,l30,l40,s50: save (s) or load (l) a state that many seconds after
        // the play view opens (simulator tests of save states without the status panel's buttons)
        .task {
            let steps = (ProcessInfo.processInfo.environment["FF7_TEST_SAVESTATE"] ?? "").split(separator: ",")
            var last = 0.0
            for step in steps {
                guard let kind = step.first, let at = Double(step.dropFirst()) else { continue }
                try? await Task.sleep(for: .seconds(max(0, at - last)))
                last = at
                ff7_ios_companion_command(kind == "l" ? 3 : 2)
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            controller = Self.hasGamepad()
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            controller = Self.hasGamepad()
        }
        // Leaving the app, the app switcher, Control Center, a call: the game stops at its next
        // frame with its sound, and goes on where it was when FF7Recomp is back in front.
        .onChange(of: scenePhase) {
            EventLog.write("scene \(scenePhase)")
            if scenePhase == .active { reclaimAudio() }
            #if DEBUG
            // FF7_TEST_SUSPEND_INTERRUPT=1: as an iPhone does when it suspends the app (locking it),
            // an audio interruption "began" with no "ended" (the simulator sends none)
            if scenePhase == .background, ProcessInfo.processInfo.environment["FF7_TEST_SUSPEND_INTERRUPT"] == "1" {
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                                userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            }
            #endif
            updatePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let reason = (note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt).map { " reason=\($0)" } ?? ""
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { " options=\($0)" } ?? ""
            EventLog.write("audio interruption \(type == .began ? "began" : "ended")\(reason)\(options)")
            audioInterrupted = type == .began
            updatePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            EventLog.write("audio route change reason=\(reason) \(EventLog.audioState())")
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.silenceSecondaryAudioHintNotification)) { _ in
            EventLog.write("silence hint \(EventLog.audioState())")
        }
        .onDisappear {
            PadInput.shared.stopControllers()
            ff7_platform_set_paused(0)
            EngineBridge.shutdown()
            OrientationLock.set(.all)
        }
    }

    /// Back in front after an audio interruption with no "ended": iOS sends "began" when it
    /// shuts the audio session of an app it suspends (locking the phone, going home) and never
    /// the matching "ended", which left the game paused for good. As Apple advises, take the
    /// session back on returning to the foreground: during a real call that fails and the game
    /// stays paused until the call's own "ended"; otherwise the interruption is over.
    private func reclaimAudio(quiet: Bool = false) {
        guard audioInterrupted else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioInterrupted = false
            EventLog.write("audio session back (no interruption ended came\(quiet ? "; the other audio stopped" : ""))")
        } catch {
            if !quiet { EventLog.write("audio session still taken: \(error.localizedDescription)") }
        }
    }

    private func updatePause() {
        // the full-screen guide pauses the game; the guide in the panel does not (the game is in view)
        let pause = scenePhase != .active || audioInterrupted || guideFull
        let was = ff7_platform_paused() != 0
        ff7_platform_set_paused(pause ? 1 : 0)
        if pause != was {
            EventLog.write("\(pause ? "paused" : "resumed") (scene \(scenePhase), call \(audioInterrupted), guide \(guideFull)) \(EventLog.audioState())")
        }
    }

    /// A controller the game can be played with (a full gamepad: d-pad, four face buttons,
    /// shoulders). Then the on-screen pad is not drawn, as on the AYN Thor.
    static func hasGamepad() -> Bool {
        // FF7_TOUCHPAD=1: as if no controller were connected (testing, a controller nearby)
        if ProcessInfo.processInfo.environment["FF7_TOUCHPAD"] == "1" { return false }
        return GCController.controllers().contains { $0.extendedGamepad != nil }
    }

    private func allowsPortrait(_ size: CGSize) -> Bool { PlayOrientation.allowsPortrait(size, hingeOpen: hingeOpen) }

    private func lockOrientation(for size: CGSize) {
        PlayOrientation.lock(for: size, hingeOpen: hingeOpen)
    }

    /// Ends the game: the lifted game boots once per process (its guest memory is fixed), so
    /// it cannot stop and start again inside the app, and leaving its thread running kept its
    /// sound playing. Closing the app stops it all; the next launch starts fresh.
    /// The game boots once per process, so Quit ends the process. Not with exit(): its cleanup
    /// destroys the renderer's globals while the game thread is still drawing (that aborted on
    /// quit, after a crash report in the engine log). The game is paused first (it stops at a
    /// frame boundary, sound off), the logs are flushed, and the process ends without cleanup.
    static func quitGame() {
        PadInput.shared.stopControllers()
        ff7_platform_set_paused(1)
        _ = ff7_platform_wait_parked(500)
        EngineBridge.shutdown()
        EventLog.write("quit")
        fflush(nil)
        usleep(100_000)     // the engine log's writer thread and the event log's queue drain
        _exit(0)
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
        let result = EngineBridge.boot(gameDir: gameDir)
        status = result.message.isEmpty ? probe.message : result.message
        if result.booted {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { showStatus = false }
        }
    }
}

private struct MetalSurfaceView: UIViewRepresentable {
    var reflection = false

    func makeUIView(context: Context) -> FF7MetalView {
        FF7MetalView(frame: .zero)
    }

    func updateUIView(_ uiView: FF7MetalView, context: Context) {
        uiView.reflection = reflection
    }
}
