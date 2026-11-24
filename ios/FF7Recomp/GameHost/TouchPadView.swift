import SwiftUI

/// Where the game's 4:3 picture and the on-screen pad go on a screen of a given size. The
/// picture is always as large as the screen allows. On a wide screen (an iPhone in landscape)
/// the pad fits in the black bars beside it; where the bars are narrow (iPhone Duo, iPad) the pad
/// lies over the picture's edges at full size, as touch games do.
///
/// The d-pad and face buttons sit in the bottom corners, measured from the screen edge (the
/// bottom corners are clear on every iPhone and iPad). The top rows (quit, L1/Select,
/// Start/R1) sit below the top safe area, and lower still when the screen has side insets: the
/// iPhone Duo's outer camera is in a top corner, an iPhone's Dynamic Island mid-height.
///
/// Recomputed whenever the screen changes size: rotation, iPhone Duo folding, split screen.
///
/// Portrait (the iPhone Duo open or half-folded, an iPad): the picture spans the width at the
/// top, kept in the top half so it stays above the Duo's fold. The bottom half is the Android
/// port's bottom screen, narrowed to a centre column: the status panel (CompanionPanel) with
/// its touch buttons below it. The pad keeps to the side columns (L1/Select over the d-pad on
/// the left; quit, Start/R1 over the face buttons on the right), so a thumb on the pad never
/// lands on Save or Load. With a game controller connected the pad is not drawn.
struct PlayLayout {
    static let button: CGFloat = 48          // d-pad / face button side at scale 1
    static let gap: CGFloat = 4
    static let cluster = button * 3 + gap * 2 // 152: one d-pad or face-button cluster
    static let edge: CGFloat = 8              // margin to the screen edge and the picture

    let picture: CGRect
    let scale: CGFloat
    let column: CGFloat        // width of one pad column (a cluster at this scale)
    let leftX: CGFloat         // centre x of the d-pad
    let rightX: CGFloat        // centre x of the face buttons
    let rowLeftX: CGFloat      // centre x of L1 / Select
    let rowRightX: CGFloat     // centre x of Start / R1
    let quitX: CGFloat         // centre x of the quit button
    let topY: CGFloat          // top of the L1/Select and Start/R1 rows
    let quitY: CGFloat         // top of the quit button
    let bottomY: CGFloat       // bottom of the clusters
    let showsPad: Bool         // the on-screen pad is drawn (no controller, or landscape)
    let panel: CGRect?         // portrait: the status panel
    let deck: CGRect?          // portrait: the panel's command buttons
    let deckColumns: Int       // buttons per row in the deck

    init(size: CGSize, safe: EdgeInsets, controller: Bool = false) {
        if size.height > size.width {
            self.init(portrait: size, safe: safe, controller: controller)
        } else {
            self.init(landscape: size, safe: safe)
        }
    }

    private init(landscape size: CGSize, safe: EdgeInsets) {
        let width = min(size.width, size.height * 4 / 3)
        let height = width * 3 / 4
        picture = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                         width: width, height: height)
        // In the bars when a cluster fits there at 85 % or more; otherwise over the picture,
        // full size on a tall screen and 85 % on a short one (an iPhone Duo's outer screen).
        let bar = picture.minX
        let fit = (bar - 2 * Self.edge) / Self.cluster
        let scale: CGFloat = fit >= 0.85 ? min(1, fit) : (size.height >= 600 ? 1 : 0.85)
        self.scale = scale
        column = Self.cluster * scale
        let inset = max(Self.edge, (bar - column) / 2)      // centre the column in a wide bar
        rowLeftX = inset + column / 2
        rowRightX = size.width - inset - column / 2
        if fit >= 0.85 {
            leftX = rowLeftX
            rightX = rowRightX
        } else {
            // Over the picture: the clusters keep inside the side safe area, which on an iPhone
            // Duo's outer screen keeps them off the camera (in the bottom corner when the screen
            // is turned that way). The top rows are low enough to clear a top-corner camera.
            leftX = safe.leading + Self.edge + column / 2
            rightX = size.width - safe.trailing - Self.edge - column / 2
        }
        let sideInsets = safe.leading > 0 || safe.trailing > 0
        quitX = rowRightX + column / 2 - 18 * scale
        quitY = safe.top + 2 * Self.edge
        topY = sideInsets ? safe.top + 72 : quitY + 36 * scale + Self.edge   // below quit
        bottomY = size.height - Self.edge
        showsPad = true
        panel = nil
        deck = nil
        deckColumns = 0
    }

    /// Upright: picture on top; pad columns at the sides and the status panel between them.
    /// The picture keeps to the top half (the iPhone Duo folds across the middle) and everything
    /// else starts below the middle, so nothing sits on the fold.
    private init(portrait size: CGSize, safe: EdgeInsets, controller: Bool) {
        let half = size.height / 2
        let width = min(size.width, (half - safe.top) * 4 / 3)
        let height = width * 3 / 4
        picture = CGRect(x: (size.width - width) / 2, y: max(safe.top, half - height),
                         width: width, height: height)
        let fold: CGFloat = 16                                  // clearance below the middle
        let top = max(picture.maxY, half) + fold
        let left = safe.leading + 2 * Self.edge
        let right = size.width - safe.trailing - 2 * Self.edge
        bottomY = size.height - max(safe.bottom, Self.edge) - Self.edge
        showsPad = !controller

        // pad columns as large as leaves the centre at least 320 wide (up to 1.2x), and as fit
        // the height: quit (36), a shoulder row (40) and a cluster (152), with gaps
        let gutter: CGFloat = 20                                // between the pad and the panel
        let fitWidth = (right - left - 2 * gutter - 320) / (2 * Self.cluster)
        let fitHeight = (bottomY - top - 2 * Self.edge - 20) / (36 + 40 + Self.cluster)
        let scale = max(0.6, min(1.2, fitWidth, fitHeight))
        self.scale = scale
        column = Self.cluster * scale
        leftX = left + column / 2
        rightX = right - column / 2
        rowLeftX = leftX
        rowRightX = rightX
        quitX = right - 18 * scale
        quitY = top
        topY = top + 36 * scale + Self.edge

        // the centre column: status panel above, its buttons (3 x 2) below
        let x0 = left + column + gutter, x1 = right - column - gutter
        let deckHeight: CGFloat = 2 * 44 + 6
        deckColumns = 3
        deck = CGRect(x: x0, y: bottomY - deckHeight, width: x1 - x0, height: deckHeight)
        panel = CGRect(x: x0, y: top, width: x1 - x0, height: bottomY - deckHeight - Self.edge - top)
    }
}

/// On-screen pad, laid out by PlayLayout in the columns beside the picture.
///
/// Quit in the top-right corner. Left: L1 and Select at the top; d-pad at the bottom. Right: Start and R1 at the
/// top, face buttons at the bottom. Feeds PadInput, which merges it with any game controller.
///
/// FF7 PC on a pad: A (bottom) cancel, B (right) OK, X (left) menu, Y (top) extra,
/// Start pause, Select help, L1/R1 page / switch target.
struct TouchPadView: View {
    let layout: PlayLayout
    let onQuit: () -> Void

    @State private var held: UInt16 = 0

    var body: some View {
        let s = layout.scale
        let rowHeight = 40 * s
        let quitSide = 36 * s
        ZStack(alignment: .topLeading) {
            // quit: top-right in landscape (clear of cameras and the Dynamic Island), centred in portrait
            Button(action: onQuit) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: quitSide, height: quitSide)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .foregroundStyle(.white.opacity(0.9))
            }
            .accessibilityLabel("Quit")
            .position(x: layout.quitX, y: layout.quitY + quitSide / 2)

            if layout.showsPad { pad(s: s, rowHeight: rowHeight) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            held = 0
            PadInput.shared.setTouchButtons(0)
        }
    }

    /// The buttons (not drawn while a controller is connected in portrait).
    @ViewBuilder
    private func pad(s: CGFloat, rowHeight: CGFloat) -> some View {
            // left column
            HStack(spacing: PlayLayout.gap * 2 * s) {
                padButton("L1", bit: UInt16(FF7_PAD_LEFT_SHOULDER), wide: true)
                padButton("Select", bit: UInt16(FF7_PAD_BACK), wide: true)
            }
            .position(x: layout.rowLeftX, y: layout.topY + rowHeight / 2)

            cluster(round: false, labels: ("▲", "◀", "▶", "▼"),
                    bits: (UInt16(FF7_PAD_DPAD_UP), UInt16(FF7_PAD_DPAD_LEFT),
                           UInt16(FF7_PAD_DPAD_RIGHT), UInt16(FF7_PAD_DPAD_DOWN)))
                .position(x: layout.leftX, y: layout.bottomY - layout.column / 2)

            // right column: Start / R1 level with L1 / Select
            HStack(spacing: PlayLayout.gap * 2 * s) {
                padButton("Start", bit: UInt16(FF7_PAD_START), wide: true)
                padButton("R1", bit: UInt16(FF7_PAD_RIGHT_SHOULDER), wide: true)
            }
            .position(x: layout.rowRightX, y: layout.topY + rowHeight / 2)

            cluster(round: true, labels: ("Y", "X", "B", "A"),
                    bits: (UInt16(FF7_PAD_Y), UInt16(FF7_PAD_X),
                           UInt16(FF7_PAD_B), UInt16(FF7_PAD_A)))
                .position(x: layout.rightX, y: layout.bottomY - layout.column / 2)
    }

    /// A diamond of four buttons: top, left, right, bottom.
    private func cluster(round: Bool, labels: (String, String, String, String),
                         bits: (UInt16, UInt16, UInt16, UInt16)) -> some View {
        let s = layout.scale
        let b = PlayLayout.button * s, g = PlayLayout.gap * s
        return VStack(spacing: g) {
            padButton(labels.0, bit: bits.0, round: round)
            HStack(spacing: g) {
                padButton(labels.1, bit: bits.1, round: round)
                Color.clear.frame(width: b, height: b)
                padButton(labels.2, bit: bits.2, round: round)
            }
            padButton(labels.3, bit: bits.3, round: round)
        }
    }

    private func padButton(_ title: String, bit: UInt16, wide: Bool = false,
                           round: Bool = false) -> some View {
        let s = layout.scale
        let w = (wide ? 72 : PlayLayout.button) * s
        let h = (wide ? 40 : PlayLayout.button) * s
        return Text(title)
            .font(.callout.weight(.semibold))
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
