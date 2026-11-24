import SwiftUI

/// On-screen pad, laid out in the black side bars beside the game's 4:3 picture so it never
/// covers the picture (FF7's battle menu runs along the picture's bottom edge). The bars are
/// measured from the whole screen, ignoring the safe area: on an iPhone in landscape each bar is
/// ~170 pt, enough for full-size buttons when they use the bar to the screen edge. Controls sit
/// in the bars' corners, clear of the Dynamic Island (mid-height on one edge). On wider screens
/// (iPad) the bars are narrower and the buttons scale down; with no bar at all they overlay the
/// picture as before.
///
/// Left bar: L1 and Select in a row at the top, d-pad at the bottom. Right bar: Start and R1 at
/// the top, face buttons at the bottom. Feeds PadInput, which merges it with any game controller.
///
/// FF7 PC on a pad: A (bottom) cancel, B (right) OK, X (left) menu, Y (top) extra,
/// Start pause, Select help, L1/R1 page / switch target.
struct TouchPadView: View {
    @State private var held: UInt16 = 0

    private static let button: CGFloat = 48          // d-pad / face button side at scale 1
    private static let gap: CGFloat = 4
    private static let cluster = button * 3 + gap * 2 // 152: one d-pad or face-button cluster
    private static let edge: CGFloat = 8              // margin to the screen edge and the picture
    private static let topRow: CGFloat = 72           // below the back button, above the Dynamic Island

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pictureWidth = min(size.width, size.height * 4 / 3)
            let bar = (size.width - pictureWidth) / 2
            // Fit a cluster in the bar; never below 70 % (then it overlaps the picture a little).
            let scale = max(0.7, min(1, (bar - Self.edge * 2) / Self.cluster))
            let clusterSide = Self.cluster * scale
            let inset = max(Self.edge, (bar - clusterSide) / 2)   // centre clusters in the bar

            ZStack {
                // left bar
                HStack(spacing: Self.gap * 2 * scale) {
                    padButton("L1", bit: UInt16(FF7_PAD_LEFT_SHOULDER), scale: scale, wide: true)
                    padButton("Select", bit: UInt16(FF7_PAD_BACK), scale: scale, wide: true)
                }
                .position(x: inset + clusterSide / 2, y: Self.topRow + Self.button * scale / 2)

                cluster(scale: scale, round: false, labels: ("▲", "◀", "▶", "▼"),
                        bits: (UInt16(FF7_PAD_DPAD_UP), UInt16(FF7_PAD_DPAD_LEFT),
                               UInt16(FF7_PAD_DPAD_RIGHT), UInt16(FF7_PAD_DPAD_DOWN)))
                    .position(x: inset + clusterSide / 2, y: size.height - Self.edge - clusterSide / 2)

                // right bar
                HStack(spacing: Self.gap * 2 * scale) {
                    padButton("Start", bit: UInt16(FF7_PAD_START), scale: scale, wide: true)
                    padButton("R1", bit: UInt16(FF7_PAD_RIGHT_SHOULDER), scale: scale, wide: true)
                }
                .position(x: size.width - inset - clusterSide / 2, y: Self.topRow + Self.button * scale / 2)

                cluster(scale: scale, round: true, labels: ("Y", "X", "B", "A"),
                        bits: (UInt16(FF7_PAD_Y), UInt16(FF7_PAD_X),
                               UInt16(FF7_PAD_B), UInt16(FF7_PAD_A)))
                    .position(x: size.width - inset - clusterSide / 2,
                              y: size.height - Self.edge - clusterSide / 2)
            }
        }
        .ignoresSafeArea()
        .onDisappear {
            held = 0
            PadInput.shared.setTouchButtons(0)
        }
    }

    /// A diamond of four buttons: top, left, right, bottom.
    private func cluster(scale: CGFloat, round: Bool, labels: (String, String, String, String),
                         bits: (UInt16, UInt16, UInt16, UInt16)) -> some View {
        let b = Self.button * scale, g = Self.gap * scale
        return VStack(spacing: g) {
            padButton(labels.0, bit: bits.0, scale: scale, round: round)
            HStack(spacing: g) {
                padButton(labels.1, bit: bits.1, scale: scale, round: round)
                Color.clear.frame(width: b, height: b)
                padButton(labels.2, bit: bits.2, scale: scale, round: round)
            }
            padButton(labels.3, bit: bits.3, scale: scale, round: round)
        }
    }

    private func padButton(_ title: String, bit: UInt16, scale: CGFloat, wide: Bool = false,
                           small: Bool = false, round: Bool = false) -> some View {
        let w = (wide ? 72 : Self.button) * scale
        let h = (small ? 30 : (wide ? 40 : Self.button)) * scale
        return Text(title)
            .font(small ? .caption.weight(.semibold) : .callout.weight(.semibold))
            .minimumScaleFactor(0.6)
            .frame(width: w, height: h)
            .background((held & bit) != 0 ? Color.white.opacity(0.45) : Color.white.opacity(0.14))
            .foregroundStyle(.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: round ? h / 2 : 8))
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
