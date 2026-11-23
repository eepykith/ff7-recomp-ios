import SwiftUI

/// On-screen pad, laid out for landscape around the 4:3 picture: d-pad and L1 on the left,
/// face buttons and R1 on the right, Select and Start in the middle. Feeds PadInput, which
/// merges it with any connected game controller (the XInput-style pad FFNx reads on Android).
///
/// FF7 PC on a pad: A (bottom) cancel, B (right) OK, X (left) menu, Y (top) extra,
/// Start pause, Select help, L1/R1 page / switch target.
struct TouchPadView: View {
    @State private var held: UInt16 = 0

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                padButton("L1", bit: UInt16(FF7_PAD_LEFT_SHOULDER), wide: true)
                dpad
            }
            Spacer()
            HStack(spacing: 12) {
                padButton("Select", bit: UInt16(FF7_PAD_BACK), small: true)
                padButton("Start", bit: UInt16(FF7_PAD_START), small: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                padButton("R1", bit: UInt16(FF7_PAD_RIGHT_SHOULDER), wide: true)
                faceButtons
            }
        }
        .onDisappear {
            held = 0
            PadInput.shared.setTouchButtons(0)
        }
    }

    private var dpad: some View {
        VStack(spacing: 4) {
            padButton("▲", bit: UInt16(FF7_PAD_DPAD_UP))
            HStack(spacing: 4) {
                padButton("◀", bit: UInt16(FF7_PAD_DPAD_LEFT))
                Color.clear.frame(width: 48, height: 44)
                padButton("▶", bit: UInt16(FF7_PAD_DPAD_RIGHT))
            }
            padButton("▼", bit: UInt16(FF7_PAD_DPAD_DOWN))
        }
    }

    private var faceButtons: some View {
        VStack(spacing: 4) {
            padButton("Y", bit: UInt16(FF7_PAD_Y), round: true)
            HStack(spacing: 4) {
                padButton("X", bit: UInt16(FF7_PAD_X), round: true)
                Color.clear.frame(width: 48, height: 44)
                padButton("B", bit: UInt16(FF7_PAD_B), round: true)
            }
            padButton("A", bit: UInt16(FF7_PAD_A), round: true)
        }
    }

    private func padButton(_ title: String, bit: UInt16, wide: Bool = false, small: Bool = false,
                           round: Bool = false) -> some View {
        Text(title)
            .font(small ? .caption2.weight(.semibold) : .callout.weight(.semibold))
            .frame(width: wide ? 72 : (small ? 58 : 48), height: small ? 28 : 44)
            .background((held & bit) != 0 ? Color.white.opacity(0.45) : Color.white.opacity(0.14))
            .foregroundStyle(.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: round ? 22 : 8))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press(bit) }
                    .onEnded { _ in release(bit) }
            )
            .accessibilityLabel(title)
    }

    private func press(_ bit: UInt16) {
        guard (held & bit) == 0 else { return }
        held |= bit
        PadInput.shared.setTouchButtons(held)
    }

    private func release(_ bit: UInt16) {
        held &= ~bit
        PadInput.shared.setTouchButtons(held)
    }
}
