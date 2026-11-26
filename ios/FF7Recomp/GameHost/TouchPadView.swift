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
/// lands on Save or Load. The d-pad and face buttons sit high in the columns, where a thumb
/// reaches with the hands holding the lower edge.
///
/// Where each part goes exactly, and the player's own layout: PadLayout.swift.
struct PlayLayout {
    static let button: CGFloat = 48          // d-pad / face button side at scale 1
    static let gap: CGFloat = 4
    static let cluster = button * 3 + gap * 2 // 152: one d-pad or face-button cluster
    static let edge: CGFloat = 8              // margin to the screen edge and the picture

    let screen: CGSize
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
    let bottomY: CGFloat       // bottom of the pad area
    let clusterY: CGFloat      // centre y of the d-pad and the face buttons
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
        screen = size
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
        clusterY = bottomY - column / 2
        showsPad = !padHidden
        panel = nil
        deck = nil
        deckColumns = 0
    }

    /// Upright: picture on top; pad columns at the sides and the status panel between them.
    /// The picture keeps to the top half (the iPhone Duo folds across the middle) and everything
    /// else starts below the middle, so nothing sits on the fold.
    private init(portrait size: CGSize, safe: EdgeInsets, padHidden: Bool) {
        screen = size
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
        // the d-pad and face buttons high in the columns, not at the bottom: holding the Duo
        // upright, the hands rest on its lower edge and the thumbs reach up
        let rowBottom = topY + 40 * scale
        clusterY = min(bottomY - column / 2,
                       rowBottom + max(column / 2 + 2 * Self.edge, (bottomY - rowBottom) * 0.36))

        // the centre column: status panel above, its buttons (3 x 2) below
        let x0 = left + column + gutter, x1 = right - column - gutter
        let deckHeight: CGFloat = 2 * 44 + 6
        deckColumns = 3
        deck = CGRect(x: x0, y: bottomY - deckHeight, width: x1 - x0, height: deckHeight)
        panel = CGRect(x: x0, y: top, width: x1 - x0, height: bottomY - deckHeight - Self.edge - top)
    }
}

/// On-screen pad: the parts PlayLayout.padItems places (Settings > Buttons shown, Size and
/// layout), and quit in the top-right corner. Feeds PadInput, which merges it with any game
/// controller.
struct TouchPadView: View {
    let layout: PlayLayout
    let onQuit: () -> Void

    @State private var held: UInt16 = 0
    @AppStorage(PadSettings.shownKey) private var hiddenList = ""
    @AppStorage(PadSettings.layoutKey) private var layoutJSON = ""

    var body: some View {
        let items = layout.padItems(
            shown: PadSettings.shown(hiddenList),
            adjust: PadSettings.layouts(layoutJSON)[PadSettings.screenKey(layout.screen)] ?? [:])
        let quitSide = 36 * layout.scale
        ZStack(alignment: .topLeading) {
            if !items.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(items) { PadItemView(item: $0, held: held) }
                }
                .allowsHitTesting(false)          // PadTouchSurface takes the touches
                PadTouchSurface(items: items, scale: layout.scale) { bits in
                    held = bits
                    PadInput.shared.setTouchButtons(bits)
                }
            }
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
}

/// The pad's touches, every finger at once, in UIKit (lower latency than SwiftUI gestures, and
/// a finger can slide from button to button):
/// - the d-pad: the direction is where the thumb is from its centre, 8 ways (diagonals press
///   two), and sliding changes direction without lifting;
/// - the face buttons (OK, Back, Menu, Switch): the one nearest the finger, sliding from one
///   to another;
/// - L1, Select, Start, R1: the button under the finger.
/// A finger keeps to the part it touched first, so a thumb drifting off the d-pad still steers.
/// Touches anywhere else pass through (the status panel, its buttons, the quit button).
struct PadTouchSurface: UIViewRepresentable {
    let items: [PadItem]
    let scale: CGFloat
    let onChange: (UInt16) -> Void

    func makeUIView(context: Context) -> PadTouchView {
        let v = PadTouchView()
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        updateUIView(v, context: context)
        return v
    }

    func updateUIView(_ v: PadTouchView, context: Context) {
        v.items = items
        v.scale = scale
        v.onChange = onChange
    }

    static func dismantleUIView(_ v: PadTouchView, coordinator: ()) {
        v.releaseAll()
    }
}

final class PadTouchView: UIView {
    var items: [PadItem] = []
    var scale: CGFloat = 1
    var onChange: ((UInt16) -> Void)?

    private enum Area { case dpad, face, row(UInt16) }
    private var touchArea: [ObjectIdentifier: Area] = [:]
    private var touchBits: [ObjectIdentifier: UInt16] = [:]
    private var sent: UInt16 = 0

    private static let up = UInt16(FF7_PAD_DPAD_UP), down = UInt16(FF7_PAD_DPAD_DOWN)
    private static let left = UInt16(FF7_PAD_DPAD_LEFT), right = UInt16(FF7_PAD_DPAD_RIGHT)

    private var dpad: PadItem? { items.first { $0.element == .dpad } }
    private var faces: [PadItem] { items.filter { $0.element.isFace } }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func area(at p: CGPoint) -> Area? {
        if let d = dpad, distance(p, d.center) <= d.radius + 14 * scale { return .dpad }
        if faces.contains(where: { distance(p, $0.center) <= $0.radius + 8 * scale }) { return .face }
        let slop = 6 * scale
        if let row = items.first(where: { !$0.element.isRound && $0.frame.insetBy(dx: -slop, dy: -slop).contains(p) }) {
            return .row(row.element.bit)
        }
        return nil
    }

    private func bits(_ area: Area, at p: CGPoint) -> UInt16 {
        switch area {
        case .dpad:
            guard let d = dpad else { return 0 }
            let dx = p.x - d.center.x, dy = p.y - d.center.y
            guard hypot(dx, dy) > d.radius * 0.2 else { return 0 }      // the centre: no direction
            // 8 sectors of 45°: right, down-right, down, ... (screen y grows down)
            let sector = Int((atan2(dy, dx) / (.pi / 4)).rounded()) & 7
            let dirs: [UInt16] = [Self.right, Self.right | Self.down, Self.down, Self.down | Self.left,
                                  Self.left, Self.left | Self.up, Self.up, Self.up | Self.right]
            return dirs[sector]
        case .face:
            // the button whose edge is nearest; nothing once the finger has slid well away
            guard let nearest = faces.min(by: {
                distance(p, $0.center) - $0.radius < distance(p, $1.center) - $1.radius
            }) else { return 0 }
            return distance(p, nearest.center) - nearest.radius < 28 * scale ? nearest.element.bit : 0
        case .row(let bit):
            let slop = 6 * scale
            let inside = items.contains { $0.element.bit == bit && $0.frame.insetBy(dx: -slop, dy: -slop).contains(p) }
            return inside ? bit : 0
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
