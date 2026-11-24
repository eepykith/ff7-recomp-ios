import Foundation
import GameController
import QuartzCore

/// The game's one XInput-style pad (ff7_platform_set_pad), fed by the on-screen pad and any
/// connected game controller at once: buttons are OR-ed; sticks and triggers come from the
/// controller.
final class PadInput {
    static let shared = PadInput()

    private let lock = NSLock()
    private var touchButtons: UInt16 = 0
    private var tapButtons: UInt16 = 0
    private var pad = ControllerState()
    private var observers: [NSObjectProtocol] = []

    private struct ControllerState {
        var buttons: UInt16 = 0
        var lt: UInt8 = 0, rt: UInt8 = 0
        var lx: Int16 = 0, ly: Int16 = 0, rx: Int16 = 0, ry: Int16 = 0
    }

    // MARK: touch

    // The game reads the pad once per game frame (30 a second in the field, as few as 15 in
    // battle), so a tap shorter than a frame could fall between two reads and be lost, and two
    // quick taps could merge into one. Each touch press is therefore shown to the game for at
    // least minPhase, and each release too before the next press: every tap arrives, in order,
    // however fast. A press still reaches the game at once.
    private static let minPhase: CFTimeInterval = 0.07
    private var fingers: UInt16 = 0                              // what the fingers hold now
    private var pending = [Int](repeating: 0, count: 16)          // taps not yet shown, per bit
    private var lastEdge = [CFTimeInterval](repeating: 0, count: 16)
    private var recheck = false

    /// The on-screen pad's buttons under the fingers (main thread).
    func setTouchButtons(_ buttons: UInt16) {
        let rising = buttons & ~fingers
        for bit in 0..<16 where rising & (1 << bit) != 0 { pending[bit] += 1 }
        fingers = buttons
        stepTouch()
    }

    private func stepTouch() {
        let now = CACurrentMediaTime()
        lock.lock(); var shown = touchButtons; lock.unlock()
        var busy = false
        for bit in 0..<16 {
            let m = UInt16(1) << bit
            let since = now - lastEdge[bit]
            if shown & m == 0 {
                guard pending[bit] > 0 else { continue }
                if since >= Self.minPhase {
                    shown |= m
                    pending[bit] -= 1
                    lastEdge[bit] = now
                }
                busy = true
            } else if fingers & m == 0 || pending[bit] > 0 {    // let go, or another tap waits
                if since >= Self.minPhase {
                    shown &= ~m
                    lastEdge[bit] = now
                }
                busy = true
            }
        }
        lock.lock(); let changed = shown != touchButtons; touchButtons = shown; lock.unlock()
        if changed { push() }
        if busy, !recheck {
            recheck = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
                self?.recheck = false
                self?.stepTouch()
            }
        }
    }

    /// A short press (the status panel's Menu button): held 150 ms, long enough for the game,
    /// which reads the pad once per frame.
    func tap(_ bit: UInt16) {
        lock.lock(); tapButtons |= bit; lock.unlock()
        push()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            lock.lock(); tapButtons &= ~bit; lock.unlock()
            push()
        }
    }

    // MARK: game controllers

    /// Starts listening for controllers (idempotent). Call while the play view is up.
    func startControllers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.controllerChanged(nil)
        })
        GCController.controllers().forEach(attach)
        GCController.startWirelessControllerDiscovery {}
    }

    func stopControllers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.stopWirelessControllerDiscovery()
        GCController.controllers().forEach { $0.extendedGamepad?.valueChangedHandler = nil }
        lock.lock(); pad = ControllerState(); touchButtons = 0; lock.unlock()
        fingers = 0
        pending = [Int](repeating: 0, count: 16)
        push()
    }

    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in self?.controllerChanged(gamepad) }
        controllerChanged(gamepad)
    }

    private func controllerChanged(_ gamepad: GCExtendedGamepad?) {
        var s = ControllerState()
        if let g = gamepad {
            // Apple's face-button names are positional, like XInput's: A bottom, B right, X left, Y top.
            let map: [(GCControllerButtonInput, UInt16)] = [
                (g.dpad.up, UInt16(FF7_PAD_DPAD_UP)), (g.dpad.down, UInt16(FF7_PAD_DPAD_DOWN)),
                (g.dpad.left, UInt16(FF7_PAD_DPAD_LEFT)), (g.dpad.right, UInt16(FF7_PAD_DPAD_RIGHT)),
                (g.buttonA, UInt16(FF7_PAD_A)), (g.buttonB, UInt16(FF7_PAD_B)),
                (g.buttonX, UInt16(FF7_PAD_X)), (g.buttonY, UInt16(FF7_PAD_Y)),
                (g.leftShoulder, UInt16(FF7_PAD_LEFT_SHOULDER)),
                (g.rightShoulder, UInt16(FF7_PAD_RIGHT_SHOULDER)),
                (g.buttonMenu, UInt16(FF7_PAD_START)),
            ]
            for (button, bit) in map where button.isPressed { s.buttons |= bit }
            if g.buttonOptions?.isPressed == true { s.buttons |= UInt16(FF7_PAD_BACK) }
            s.lt = Self.trigger(g.leftTrigger.value)
            s.rt = Self.trigger(g.rightTrigger.value)
            s.lx = Self.axis(g.leftThumbstick.xAxis.value)
            s.ly = Self.axis(g.leftThumbstick.yAxis.value)
            s.rx = Self.axis(g.rightThumbstick.xAxis.value)
            s.ry = Self.axis(g.rightThumbstick.yAxis.value)
        }
        lock.lock(); pad = s; lock.unlock()
        push()
    }

    private static func trigger(_ v: Float) -> UInt8 { UInt8(clamping: Int((v * 255).rounded())) }
    private static func axis(_ v: Float) -> Int16 { Int16(clamping: Int((v * 32767).rounded())) }   // up is +, as XInput

    // MARK: output

    private func push() {
        lock.lock()
        let touch = touchButtons | tapButtons, c = pad
        lock.unlock()
        let buttons = touch | c.buttons
        // D-pad presses stay button bits only: FFNx turns them into the game's directions
        // (dpad_up etc.), so the touch pad needs no faked stick. Sticks and triggers come only
        // from a real controller.
        EngineBridge.setPad(buttons: buttons, lt: c.lt, rt: c.rt, lx: c.lx, ly: c.ly, rx: c.rx, ry: c.ry)
    }
}
