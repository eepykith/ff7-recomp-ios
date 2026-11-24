import SwiftUI
import UIKit

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
/// lands on Save or Load.
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
    let showsPad: Bool         // the on-screen pad is drawn (hidden with a controller: TouchPadMode)
    let panel: CGRect?         // portrait: the status panel
    let deck: CGRect?          // portrait: the panel's command buttons
    let deckColumns: Int       // buttons per row in the deck

    init(size: CGSize, safe: EdgeInsets, padHidden: Bool = false) {
        if size.height > size.width {
            self.init(portrait: size, safe: safe, padHidden: padHidden)
        } else {
            self.init(landscape: size, safe: safe, padHidden: padHidden)
        }
    }

    private init(landscape size: CGSize, safe: EdgeInsets, padHidden: Bool) {
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
        showsPad = !padHidden
        panel = nil
        deck = nil
        deckColumns = 0
    }

    /// Upright: picture on top; pad columns at the sides and the status panel between them.
    /// The picture keeps to the top half (the iPhone Duo folds across the middle) and everything
    /// else starts below the middle, so nothing sits on the fold.
    private init(portrait size: CGSize, safe: EdgeInsets, padHidden: Bool) {
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
        showsPad = !padHidden

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
            if layout.showsPad {
                pad(s: s, rowHeight: rowHeight)
                    .allowsHitTesting(false)          // PadTouchSurface takes the touches
                PadTouchSurface(layout: layout) { bits in
                    held = bits
                    PadInput.shared.setTouchButtons(bits)
                }
            }
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

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            held = 0
            PadInput.shared.setTouchButtons(0)
        }
    }

    /// The buttons (not drawn while they are hidden: a controller, or Settings).
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
            .accessibilityLabel(title)
    }
}

/// The pad's touches, every finger at once, in UIKit (lower latency than SwiftUI gestures, and
/// a finger can slide from button to button):
/// - the d-pad is one area: the direction is where the thumb is from its centre, 8 ways
///   (diagonals press two), and sliding changes direction without lifting;
/// - the face buttons: the one nearest the finger, sliding from one to another;
/// - L1, Select, Start, R1: the button under the finger.
/// A finger keeps to the area it touched first, so a thumb drifting off the d-pad still steers.
/// Touches anywhere else pass through (the status panel, its buttons, the quit button).
struct PadTouchSurface: UIViewRepresentable {
    let layout: PlayLayout
    let onChange: (UInt16) -> Void

    func makeUIView(context: Context) -> PadTouchView {
        let v = PadTouchView()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        v.layout = layout
        v.onChange = onChange
        return v
    }

    func updateUIView(_ v: PadTouchView, context: Context) {
        v.layout = layout
        v.onChange = onChange
    }

    static func dismantleUIView(_ v: PadTouchView, coordinator: ()) {
        v.releaseAll()
    }
}

final class PadTouchView: UIView {
    var layout: PlayLayout?
    var onChange: ((UInt16) -> Void)?

    private enum Area { case dpad, face, rows }
    private var touchArea: [ObjectIdentifier: Area] = [:]
    private var touchBits: [ObjectIdentifier: UInt16] = [:]
    private var sent: UInt16 = 0

    private static let up = UInt16(FF7_PAD_DPAD_UP), down = UInt16(FF7_PAD_DPAD_DOWN)
    private static let left = UInt16(FF7_PAD_DPAD_LEFT), right = UInt16(FF7_PAD_DPAD_RIGHT)

    // MARK: geometry (PlayLayout's, the same the buttons are drawn with)

    private func clusterCenter(_ x: CGFloat, _ l: PlayLayout) -> CGPoint {
        CGPoint(x: x, y: l.bottomY - l.column / 2)
    }

    /// The square a cluster's touches start in: the cluster, and a little around it.
    private func clusterZone(_ c: CGPoint, _ l: PlayLayout) -> CGRect {
        let half = l.column / 2 + 14 * l.scale
        return CGRect(x: c.x - half, y: c.y - half, width: 2 * half, height: 2 * half)
    }

    private func rowButtons(_ l: PlayLayout) -> [(CGRect, UInt16)] {
        let s = l.scale, w = 72 * s, h = 40 * s, gap = PlayLayout.gap * 2 * s
        let y = l.topY, slop = 6 * s
        func pair(_ cx: CGFloat, _ a: UInt16, _ b: UInt16) -> [(CGRect, UInt16)] {
            let lx = cx - gap / 2 - w, rx = cx + gap / 2
            return [(CGRect(x: lx, y: y, width: w, height: h).insetBy(dx: -slop, dy: -slop), a),
                    (CGRect(x: rx, y: y, width: w, height: h).insetBy(dx: -slop, dy: -slop), b)]
        }
        return pair(l.rowLeftX, UInt16(FF7_PAD_LEFT_SHOULDER), UInt16(FF7_PAD_BACK))
            + pair(l.rowRightX, UInt16(FF7_PAD_START), UInt16(FF7_PAD_RIGHT_SHOULDER))
    }

    private func area(at p: CGPoint) -> Area? {
        guard let l = layout, l.showsPad else { return nil }
        if clusterZone(clusterCenter(l.leftX, l), l).contains(p) { return .dpad }
        if clusterZone(clusterCenter(l.rightX, l), l).contains(p) { return .face }
        if rowButtons(l).contains(where: { $0.0.contains(p) }) { return .rows }
        return nil
    }

    private func bits(_ area: Area, at p: CGPoint) -> UInt16 {
        guard let l = layout else { return 0 }
        switch area {
        case .dpad:
            let c = clusterCenter(l.leftX, l)
            let dx = p.x - c.x, dy = p.y - c.y
            guard hypot(dx, dy) > l.column * 0.1 else { return 0 }      // the centre: no direction
            // 8 sectors of 45°: right, down-right, down, ... (screen y grows down)
            let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded()) & 7
            let dirs: [UInt16] = [Self.right, Self.right | Self.down, Self.down, Self.down | Self.left,
                                  Self.left, Self.left | Self.up, Self.up, Self.up | Self.right]
            return dirs[sector]
        case .face:
            let c = clusterCenter(l.rightX, l)
            let off = (PlayLayout.button + PlayLayout.gap) * l.scale
            let buttons: [(CGPoint, UInt16)] = [
                (CGPoint(x: c.x, y: c.y - off), UInt16(FF7_PAD_Y)),
                (CGPoint(x: c.x - off, y: c.y), UInt16(FF7_PAD_X)),
                (CGPoint(x: c.x + off, y: c.y), UInt16(FF7_PAD_B)),
                (CGPoint(x: c.x, y: c.y + off), UInt16(FF7_PAD_A)),
            ]
            let nearest = buttons.min { hypot($0.0.x - p.x, $0.0.y - p.y) < hypot($1.0.x - p.x, $1.0.y - p.y) }!
            // far off the cluster (a finger that slid away): nothing
            return hypot(nearest.0.x - p.x, nearest.0.y - p.y) < 1.6 * PlayLayout.button * l.scale ? nearest.1 : 0
        case .rows:
            return rowButtons(l).first { $0.0.contains(p) }?.1 ?? 0
        }
    }

    // MARK: touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        area(at: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let p = t.location(in: self)
            guard let a = area(at: p) else { continue }
            touchArea[ObjectIdentifier(t)] = a
            touchBits[ObjectIdentifier(t)] = bits(a, at: p)
        }
        publish()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let a = touchArea[ObjectIdentifier(t)] else { continue }
            touchBits[ObjectIdentifier(t)] = bits(a, at: t.location(in: self))
        }
        publish()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

    private func end(_ touches: Set<UITouch>) {
        for t in touches {
            touchArea[ObjectIdentifier(t)] = nil
            touchBits[ObjectIdentifier(t)] = nil
        }
        publish()
    }

    func releaseAll() {
        touchArea.removeAll()
        touchBits.removeAll()
        publish()
    }

    private func publish() {
        let held = touchBits.values.reduce(UInt16(0)) { $0 | $1 }
        guard held != sent else { return }
        sent = held
        onChange?(held)
    }
}

/// When the on-screen pad shows (Settings > Controls).
enum TouchPadMode: String, CaseIterable, Identifiable {
    case auto, always, never
    static let key = "ff7.touchPad"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Hide with a controller"
        case .always: return "Always show"
        case .never: return "Never show"
        }
    }
    /// Whether the pad hides, given whether a game controller is connected.
    func hidesPad(controller: Bool) -> Bool {
        switch self {
        case .auto: return controller
        case .always: return false
        case .never: return true
        }
    }
}
