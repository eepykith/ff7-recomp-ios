import SwiftUI

/// The game's live state for the status panel (the companion screen), from the snapshot the game thread builds ten times a second
/// (src/ffnx_port/companion.cpp, ff7_ios_companion_json).
struct CompanionSnapshot: Decodable, Equatable {
    struct Member: Decodable, Equatable {
        var name = "", lv = 0, hp = 0, mhp = 1, mp = 0, mmp = 1, limit = 0, limlv = 1, atb = -1
    }
    struct Enemy: Decodable, Equatable {
        var slot = 0, name = "", hp = 0, mhp = 1
    }
    var ready = 0
    var mode = ""
    var loc = ""
    var gil = 0
    var time = 0
    var speed = 1
    var noenc = 0
    var bplus = 0
    var cine = 0
    var party: [Member] = []
    var enemies: [Enemy] = []

    static let empty = CompanionSnapshot()

    /// The current snapshot, or `empty` before a game is under way (title screen) or when no
    /// game is linked (the launcher-only target).
    static func read() -> CompanionSnapshot {
        var buffer = [CChar](repeating: 0, count: 8192)
        let n = ff7_ios_companion_json(&buffer, Int32(buffer.count))
        guard n > 0 else { return .empty }
        let data = Data(bytes: buffer, count: Int(n))
        return (try? JSONDecoder().decode(CompanionSnapshot.self, from: data)) ?? .empty
    }
}

extension CompanionSnapshot.Member {
    private enum CodingKeys: String, CodingKey { case name, lv, hp, mhp, mp, mmp, limit, limlv, atb }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lv = try c.decodeIfPresent(Int.self, forKey: .lv) ?? 0
        hp = try c.decodeIfPresent(Int.self, forKey: .hp) ?? 0
        mhp = max(1, try c.decodeIfPresent(Int.self, forKey: .mhp) ?? 1)
        mp = try c.decodeIfPresent(Int.self, forKey: .mp) ?? 0
        mmp = max(1, try c.decodeIfPresent(Int.self, forKey: .mmp) ?? 1)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        limlv = try c.decodeIfPresent(Int.self, forKey: .limlv) ?? 1
        atb = try c.decodeIfPresent(Int.self, forKey: .atb) ?? -1
    }
}

extension CompanionSnapshot.Enemy {
    private enum CodingKeys: String, CodingKey { case slot, name, hp, mhp }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slot = try c.decodeIfPresent(Int.self, forKey: .slot) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        hp = try c.decodeIfPresent(Int.self, forKey: .hp) ?? 0
        mhp = max(1, try c.decodeIfPresent(Int.self, forKey: .mhp) ?? 1)
    }
}

extension CompanionSnapshot {
    private enum CodingKeys: String, CodingKey {
        case ready, mode, loc, gil, time, speed, noenc, bplus, cine, party, enemies
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ready = try c.decodeIfPresent(Int.self, forKey: .ready) ?? 0
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        loc = try c.decodeIfPresent(String.self, forKey: .loc) ?? ""
        gil = try c.decodeIfPresent(Int.self, forKey: .gil) ?? 0
        time = try c.decodeIfPresent(Int.self, forKey: .time) ?? 0
        speed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? 1
        noenc = try c.decodeIfPresent(Int.self, forKey: .noenc) ?? 0
        bplus = try c.decodeIfPresent(Int.self, forKey: .bplus) ?? 0
        cine = try c.decodeIfPresent(Int.self, forKey: .cine) ?? 0
        party = try c.decodeIfPresent([Member].self, forKey: .party) ?? []
        enemies = try c.decodeIfPresent([Enemy].self, forKey: .enemies) ?? []
    }
}

/// An FF7 menu window: blue gradient, light border, rounded corners.
struct FF7Window: ViewModifier {
    var highlight: Color? = nil
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.29, blue: 0.66),
                                                  Color(red: 0.04, green: 0.10, blue: 0.31)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let highlight {
                    RoundedRectangle(cornerRadius: 7).fill(highlight)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color(red: 0.86, green: 0.86, blue: 0.94), lineWidth: 2)
            }
    }
}

extension View {
    func ff7Window(highlight: Color? = nil) -> some View { modifier(FF7Window(highlight: highlight)) }
}

/// The status panel: where the party is, play time and gil, and each member's HP / MP / Limit
/// (ATB in battle, with the enemies' HP on top). Dims during cutscenes, as the core's
/// port's bottom screen does.
struct CompanionPanel: View {
    let state: CompanionSnapshot
    var reserveTrailing: CGFloat = 0      // room kept free at the top right (the quit button)

    var body: some View {
        VStack(spacing: 6) {
            if state.mode == "battle" {
                enemies
            } else {
                header
            }
            ForEach(0..<3, id: \.self) { i in
                member(i < state.party.count ? state.party[i] : nil)
            }
        }
        .foregroundStyle(.white)
        .overlay {
            Color.black.opacity(state.cine == 1 ? 0.75 : 0)
                .animation(.easeInOut(duration: 0.8), value: state.cine)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.loc.isEmpty ? "–" : state.loc)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text("\(Self.clock(state.time))   \(state.gil) G")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Self.soft)
        }
        .padding(.horizontal, 12)
        .padding(.trailing, reserveTrailing)
        .frame(maxWidth: .infinity, minHeight: 34)
        .ff7Window()
    }

    private var enemies: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                  spacing: 4) {
            ForEach(state.enemies, id: \.slot) { e in
                VStack(spacing: 2) {
                    HStack {
                        Text(e.name.isEmpty ? "#\(e.slot)" : e.name)
                            .foregroundStyle(e.hp > 0 ? .white : Color(red: 0.5, green: 0.56, blue: 0.69))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(e.hp)/\(e.mhp)").foregroundStyle(Self.soft)
                    }
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    Self.bar(Double(e.hp) / Double(e.mhp), Color(red: 0.88, green: 0.31, blue: 0.31), height: 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.trailing, reserveTrailing)
        .frame(maxWidth: .infinity, minHeight: 34)
        .ff7Window()
    }

    @ViewBuilder
    private func member(_ m: CompanionSnapshot.Member?) -> some View {
        Group {
            if let m {
                let hf = Double(m.hp) / Double(m.mhp)
                let low = hf <= 0.25
                GeometryReader { geo in
                    let compact = geo.size.height < 76
                    VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.name).font(.system(size: compact ? 14 : 17, weight: .bold))
                            Spacer()
                            Text("Lv \(m.lv)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Self.soft)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            stat("HP \(m.hp)/\(m.mhp)", hf,
                                 low ? Color(red: 0.88, green: 0.69, blue: 0.13) : Color(red: 0.25, green: 0.82, blue: 0.44),
                                 text: low ? Color(red: 1, green: 0.82, blue: 0.25) : .white)
                            stat("MP \(m.mp)/\(m.mmp)", Double(m.mp) / Double(m.mmp), Color(red: 0.25, green: 0.56, blue: 0.94))
                        }
                        HStack(alignment: .top, spacing: 14) {
                            if m.atb >= 0 {
                                stat("ATB", Double(m.atb) / 65535, Color(red: 0.94, green: 0.82, blue: 0.3))
                            } else {
                                stat("Limit \(m.limlv)", Double(m.limit) / 255, Color(red: 0.94, green: 0.38, blue: 0.69),
                                     text: Color(red: 1, green: 0.69, blue: 0.82))
                            }
                            Color.clear.frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ff7Window()
    }

    private func stat(_ label: String, _ fraction: Double, _ color: Color, text: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Self.bar(fraction, color, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let soft = Color(red: 0.86, green: 0.86, blue: 0.94)

    static func bar(_ fraction: Double, _ color: Color, height: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.06))
                Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }

    static func clock(_ s: Int) -> String {
        String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}

/// The panel's touch buttons: Menu (the game's main menu, a Triangle press), Save and Load
/// (save states), and the boosters: speed 1x/2x/3x, random battles on/off, battle enhancement.
struct CompanionDeck: View {
    let state: CompanionSnapshot
    let columns: Int
    let onNote: (String) -> Void

    private enum Command: Int { case speed = 1, save = 2, load = 3, battles = 4, battlePlus = 5 }

    var body: some View {
        let items: [(String, Bool, () -> Void)] = [
            ("Menu", false, { PadInput.shared.tap(UInt16(FF7_PAD_Y)) }),
            ("Save", false, { send(.save); onNote("Saving state…") }),
            ("Load", false, { send(.load); onNote("Loading state…") }),
            ("Speed \(max(1, state.speed))×", state.speed > 1, { send(.speed) }),
            (state.noenc == 1 ? "No battles" : "Battles", state.noenc == 1, { send(.battles) }),
            ("Battle+", state.bplus == 1, { send(.battlePlus) }),
        ]
        let grid = Array(repeating: GridItem(.flexible(), spacing: 6), count: columns)
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button(action: item.2) {
                    Text(item.0)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .ff7Window(highlight: item.1 ? Color.green.opacity(0.3) : nil)
                }
                .buttonStyle(DeckButtonStyle())
            }
        }
        .disabled(state.ready != 1)
        .opacity(state.ready == 1 ? 1 : 0.4)
    }

    private func send(_ command: Command) {
        ff7_ios_companion_command(Int32(command.rawValue))
    }
}

private struct DeckButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.3 : 0))
            }
    }
}
