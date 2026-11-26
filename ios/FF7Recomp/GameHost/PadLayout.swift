import SwiftUI

/// One part of the on-screen pad. The labels follow the game's own prompts: B (right) is OK,
/// A (bottom) is Back, Y is the menu, X switches (targets, the battle window).
enum PadElement: String, CaseIterable, Identifiable, Codable {
    case dpad, ok, back, menu, swap, l1, r1, select, start

    var id: String { rawValue }

    /// The name in Settings and the layout editor.
    var label: String {
        switch self {
        case .dpad: return "D-pad"
        case .ok: return "OK (B)"
        case .back: return "Back (A)"
        case .menu: return "Menu (Y)"
        case .swap: return "Switch (X)"
        case .l1: return "L1"
        case .r1: return "R1"
        case .select: return "Select"
        case .start: return "Start"
        }
    }

    /// The letter on the button, and the word under it.
    var face: (title: String, caption: String?) {
        switch self {
        case .ok: return ("B", "OK")
        case .back: return ("A", "Back")
        case .menu: return ("Y", "Menu")
        case .swap: return ("X", "Switch")
        case .l1: return ("L1", nil)
        case .r1: return ("R1", nil)
        case .select: return ("Select", nil)
        case .start: return ("Start", nil)
        case .dpad: return ("", nil)
        }
    }

    /// The pad bit (none for the d-pad: its direction depends on where the thumb is).
    var bit: UInt16 {
        switch self {
        case .dpad: return 0
        case .ok: return UInt16(FF7_PAD_B)
        case .back: return UInt16(FF7_PAD_A)
        case .menu: return UInt16(FF7_PAD_Y)
        case .swap: return UInt16(FF7_PAD_X)
        case .l1: return UInt16(FF7_PAD_LEFT_SHOULDER)
        case .r1: return UInt16(FF7_PAD_RIGHT_SHOULDER)
        case .select: return UInt16(FF7_PAD_BACK)
        case .start: return UInt16(FF7_PAD_START)
        }
    }

    /// Round face buttons: a finger can slide from one to another.
    var isFace: Bool { [.ok, .back, .menu, .swap].contains(self) }
    var isRound: Bool { self == .dpad || isFace }
}

/// A pad part where it is drawn and touched.
struct PadItem: Identifiable, Equatable {
    let element: PadElement
    var center: CGPoint
    var size: CGSize
    var id: PadElement { element }
    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
               width: size.width, height: size.height)
    }
    var radius: CGFloat { min(size.width, size.height) / 2 }
}

/// A player's change to one part: moved by (dx, dy) points, resized by `scale`.
struct PadAdjust: Codable, Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var scale: CGFloat = 1
    static let none = PadAdjust()
}

/// Settings > Controls: which buttons show, and the player's layout. A layout is kept per
/// screen size, so the iPhone Duo's outer screen, open in landscape, and upright each have
/// their own.
enum PadSettings {
    static let shownKey = "ff7.padShown"
    static let layoutKey = "ff7.padLayout"

    /// The stored value: the hidden parts, comma-separated (empty: everything shows).
    static func shown(_ hiddenList: String) -> Set<PadElement> {
        let hidden = Set(hiddenList.split(separator: ",").compactMap { PadElement(rawValue: String($0)) })
        return Set(PadElement.allCases).subtracting(hidden)
    }

    static func hiddenList(_ shown: Set<PadElement>) -> String {
        PadElement.allCases.filter { !shown.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    typealias Layouts = [String: [PadElement: PadAdjust]]

    static func screenKey(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    /// The play screen's safe area on each screen size, kept when the game shows, so the layout
    /// editor lays the pad out exactly as play does (the launcher's own insets differ a little).
    static func rememberInsets(_ safe: EdgeInsets, for size: CGSize) {
        let key = "ff7.padInsets." + screenKey(size)
        UserDefaults.standard.set([safe.top, safe.leading, safe.bottom, safe.trailing], forKey: key)
    }

    static func insets(for size: CGSize) -> EdgeInsets? {
        guard let v = UserDefaults.standard.array(forKey: "ff7.padInsets." + screenKey(size)) as? [Double],
              v.count == 4 else { return nil }
        return EdgeInsets(top: v[0], leading: v[1], bottom: v[2], trailing: v[3])
    }

    static func layouts(_ json: String) -> Layouts {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: [String: PadAdjust]].self, from: data)
        else { return [:] }
        return raw.mapValues { screen in
            Dictionary(uniqueKeysWithValues: screen.compactMap { k, v in
                PadElement(rawValue: k).map { ($0, v) }
            })
        }
    }

    static func json(_ layouts: Layouts) -> String {
        let raw = layouts.mapValues { screen in
            Dictionary(uniqueKeysWithValues: screen.map { ($0.key.rawValue, $0.value) })
        }.filter { !$0.value.isEmpty }
        guard let data = try? JSONEncoder().encode(raw) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension PlayLayout {
    /// The pad's parts on this screen: where PlayLayout puts them, then the player's changes,
    /// kept on screen. Only the parts that show (Settings > Buttons shown).
    func padItems(shown: Set<PadElement>, adjust: [PadElement: PadAdjust]) -> [PadItem] {
        guard showsPad else { return [] }
        return defaultPadItems().compactMap { item in
            guard shown.contains(item.element) else { return nil }
            let a = adjust[item.element] ?? .none
            var it = item
            it.size = CGSize(width: item.size.width * a.scale, height: item.size.height * a.scale)
            it.center = CGPoint(x: item.center.x + a.dx, y: item.center.y + a.dy)
            return clamped(it)
        }
    }

    func clamped(_ item: PadItem) -> PadItem {
        var it = item
        let hw = it.size.width / 2, hh = it.size.height / 2
        it.center.x = min(max(it.center.x, hw), max(hw, screen.width - hw))
        it.center.y = min(max(it.center.y, hh), max(hh, screen.height - hh))
        return it
    }

    /// The pad as it comes: a round d-pad in the left column; in the right column a big OK (B)
    /// with Back (A) below to its left, and the smaller Menu (Y) and Switch (X) above them;
    /// L1 / Select and Start / R1 in pairs at the top of the columns.
    func defaultPadItems() -> [PadItem] {
        let s = scale
        let dpad = CGPoint(x: leftX, y: clusterY)
        let face = CGPoint(x: rightX, y: clusterY)
        func at(_ c: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: c.x + dx * s, y: c.y + dy * s)
        }
        func circle(_ d: CGFloat) -> CGSize { CGSize(width: d * s, height: d * s) }
        let pill = CGSize(width: 72 * s, height: 40 * s)
        let pairGap = PlayLayout.gap * 2 * s
        let rowY = topY + pill.height / 2
        let half = (pairGap + pill.width) / 2
        return [
            PadItem(element: .dpad, center: dpad, size: circle(PlayLayout.cluster)),
            PadItem(element: .ok, center: at(face, 40, 8), size: circle(70)),
            PadItem(element: .back, center: at(face, -30, 44), size: circle(62)),
            PadItem(element: .menu, center: at(face, 30, -58), size: circle(50)),
            PadItem(element: .swap, center: at(face, -36, -48), size: circle(50)),
            PadItem(element: .l1, center: CGPoint(x: rowLeftX - half, y: rowY), size: pill),
            PadItem(element: .select, center: CGPoint(x: rowLeftX + half, y: rowY), size: pill),
            PadItem(element: .start, center: CGPoint(x: rowRightX - half, y: rowY), size: pill),
            PadItem(element: .r1, center: CGPoint(x: rowRightX + half, y: rowY), size: pill),
        ]
    }
}

// MARK: drawing

/// The pad's look: see-through outlines over the game, brighter while pressed.
struct PadItemView: View {
    let item: PadItem
    let held: UInt16
    /// false: sized but not placed (the layout editor places it, with its drag).
    var placed = true

    private static let line = Color.white.opacity(0.6)
    private static let fill = Color.white.opacity(0.08)
    private static let lit = Color.white.opacity(0.38)

    var body: some View {
        Group {
            switch item.element {
            case .dpad: dpad
            default: button
            }
        }
        .frame(width: item.size.width, height: item.size.height)
        .position(placed ? item.center : CGPoint(x: item.size.width / 2, y: item.size.height / 2))
        .frame(width: placed ? nil : item.size.width, height: placed ? nil : item.size.height)
        .accessibilityLabel(item.element.label)
    }

    private var pressed: Bool { (held & item.element.bit) != 0 }

    private var button: some View {
        let h = item.size.height
        let shape = RoundedRectangle(cornerRadius: item.element.isRound ? h / 2 : h * 0.3, style: .continuous)
        let face = item.element.face
        return ZStack {
            shape.fill(pressed ? Self.lit : Self.fill)
            shape.strokeBorder(Self.line, lineWidth: 1.5)
            VStack(spacing: -2) {
                Text(face.title)
                    .font(.system(size: item.element.isRound ? h * 0.36 : h * 0.42, weight: .semibold))
                if let caption = face.caption, h >= 44 {
                    Text(caption).font(.system(size: max(9, h * 0.2), weight: .medium))
                }
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .foregroundStyle(.white.opacity(0.92))
        }
    }

    private var dpad: some View {
        let d = item.size.width
        let up = UInt16(FF7_PAD_DPAD_UP), down = UInt16(FF7_PAD_DPAD_DOWN)
        let left = UInt16(FF7_PAD_DPAD_LEFT), right = UInt16(FF7_PAD_DPAD_RIGHT)
        let arrows: [(Angle, UInt16)] = [(.degrees(0), up), (.degrees(90), right),
                                         (.degrees(180), down), (.degrees(270), left)]
        return ZStack {
            Circle().fill(Self.fill)
            Circle().strokeBorder(Self.line, lineWidth: 1.5)
            ForEach(arrows, id: \.1) { angle, bit in
                Triangle()
                    .fill(.white.opacity((held & bit) != 0 ? 0.95 : 0.6))
                    .frame(width: d * 0.2, height: d * 0.16)
                    .offset(y: -d * 0.3)
                    .rotationEffect(angle)
                    .shadow(color: .white.opacity((held & bit) != 0 ? 0.6 : 0), radius: 6)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}
