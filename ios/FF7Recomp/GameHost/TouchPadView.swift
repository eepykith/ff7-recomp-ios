import SwiftUI

/// On-screen pad. Feeds the same XInput-style state FFNx reads on Android.
struct TouchPadView: View {
    @State private var held: UInt16 = 0

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 6) {
                padButton("Up", bit: UInt16(FF7_PAD_DPAD_UP))
                HStack(spacing: 6) {
                    padButton("Left", bit: UInt16(FF7_PAD_DPAD_LEFT))
                    padButton("Right", bit: UInt16(FF7_PAD_DPAD_RIGHT))
                }
                padButton("Down", bit: UInt16(FF7_PAD_DPAD_DOWN))
            }
            Spacer()
            VStack(spacing: 6) {
                padButton("Y", bit: UInt16(FF7_PAD_Y))
                HStack(spacing: 6) {
                    padButton("X", bit: UInt16(FF7_PAD_X))
                    padButton("B", bit: UInt16(FF7_PAD_B))
                }
                padButton("A", bit: UInt16(FF7_PAD_A))
            }
        }
        .onDisappear {
            held = 0
            EngineBridge.setPad(buttons: 0)
        }
    }

    private func padButton(_ title: String, bit: UInt16) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .frame(minWidth: 56, minHeight: 40)
            .background((held & bit) != 0 ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press(bit) }
                    .onEnded { _ in release(bit) }
            )
    }

    private func press(_ bit: UInt16) {
        guard (held & bit) == 0 else { return }
        held |= bit
        EngineBridge.setPad(buttons: held, lx: stickX, ly: stickY)
    }

    private func release(_ bit: UInt16) {
        held &= ~bit
        EngineBridge.setPad(buttons: held, lx: stickX, ly: stickY)
    }

    private var stickX: Int16 {
        var x: Int32 = 0
        if held & UInt16(FF7_PAD_DPAD_LEFT) != 0 { x -= 32767 }
        if held & UInt16(FF7_PAD_DPAD_RIGHT) != 0 { x += 32767 }
        return Int16(clamping: x)
    }

    private var stickY: Int16 {
        var y: Int32 = 0
        if held & UInt16(FF7_PAD_DPAD_DOWN) != 0 { y -= 32767 }
        if held & UInt16(FF7_PAD_DPAD_UP) != 0 { y += 32767 }
        return Int16(clamping: y)
    }
}
