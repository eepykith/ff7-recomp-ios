import SwiftUI

/// Settings > Size and layout: the pad over a stand-in for the game picture, as it is in play
/// on this screen. Drag a part to move it; pick one and use the slider to resize it, or resize
/// the whole pad with nothing picked. Kept per screen size (PadSettings), so turning the
/// iPhone, or opening or closing the Duo, edits that screen's layout.
struct PadLayoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PadSettings.shownKey) private var hiddenList = ""
    @AppStorage(PadSettings.layoutKey) private var layoutJSON = ""

    @State private var working: PadSettings.Layouts = [:]
    @State private var loaded = false
    @State private var selected: PadElement?
    @State private var dragStart: PadAdjust?
    /// The iPhone Duo's hinge, as play watches it: the editor turns the way play does here.
    @State private var hingeOpen: Bool?

    var body: some View {
        GeometryReader { safeGeo in
            GeometryReader { geo in
                let safe = PadSettings.insets(for: geo.size) ?? safeGeo.safeAreaInsets
                let layout = PlayLayout(size: geo.size, safe: safe, aspect: AspectMode.current.ratio)
                let key = PadSettings.screenKey(geo.size)
                let adjust = working[key] ?? [:]
                let items = layout.padItems(shown: PadSettings.shown(hiddenList), adjust: adjust)
                ZStack(alignment: .topLeading) {
                    Color.black
                        .onTapGesture { selected = nil }
                    stand(in: layout.picture, label: "Game")
                    if let panel = layout.panel { stand(in: panel, label: "Status panel") }
                    if let deck = layout.deck { stand(in: deck, label: nil) }

                    controls(layout: layout, key: key, items: items,
                             canTurn: PlayOrientation.allowsPortrait(geo.size, hingeOpen: hingeOpen))
                        .opacity(dragStart == nil ? 1 : 0.2)
                        .allowsHitTesting(dragStart == nil)

                    // the buttons above the card, so one dragged under it can be picked up again
                    ForEach(items) { item in
                        PadItemView(item: item, held: 0, placed: false)
                            .overlay {
                                if selected == item.element {
                                    RoundedRectangle(cornerRadius: item.element.isRound ? item.size.height / 2 : item.size.height * 0.3)
                                        .stroke(Color.accentColor, lineWidth: 3)
                                        .padding(-4)
                                }
                            }
                            .contentShape(Rectangle())
                            .gesture(drag(item, layout: layout, key: key))
                            .position(item.center)
                    }
                }
                .onAppear { PlayOrientation.lock(for: geo.size, hingeOpen: hingeOpen) }
                .onChange(of: PlayOrientation.allowsPortrait(geo.size, hingeOpen: hingeOpen)) {
                    PlayOrientation.lock(for: geo.size, hingeOpen: hingeOpen)
                }
                .watchHinge { hingeOpen = $0 }
            }
            .ignoresSafeArea()
        }
        .onDisappear { OrientationLock.set(.all) }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            guard !loaded else { return }
            working = PadSettings.layouts(layoutJSON)
            loaded = true
        }
    }

    /// A grey stand-in for the picture or the status panel.
    private func stand(in rect: CGRect, label: String?) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.07))
            .overlay {
                if let label {
                    Text(label).font(.caption).foregroundStyle(.white.opacity(0.35))
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    private func drag(_ item: PadItem, layout: PlayLayout, key: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in
                let el = item.element
                let start = dragStart ?? (working[key]?[el] ?? .none)
                if dragStart == nil {
                    dragStart = start
                    selected = el
                }
                var a = start
                a.dx = start.dx + g.translation.width
                a.dy = start.dy + g.translation.height
                working[key, default: [:]][el] = a
            }
            .onEnded { _ in
                dragStart = nil
                // keep what was stored where it is drawn (a part dragged off the edge stays at it)
                let el = item.element
                guard var a = working[key]?[el],
                      let base = layout.defaultPadItems().first(where: { $0.element == el }) else { return }
                var moved = base
                moved.size = CGSize(width: base.size.width * a.scale, height: base.size.height * a.scale)
                moved.center = CGPoint(x: base.center.x + a.dx, y: base.center.y + a.dy)
                let kept = layout.clamped(moved)
                a.dx = kept.center.x - base.center.x
                a.dy = kept.center.y - base.center.y
                working[key, default: [:]][el] = a
            }
    }

    /// The size of the picked part, or of every part with none picked.
    private func scaleBinding(key: String, items: [PadItem]) -> Binding<Double> {
        Binding {
            let adjust = working[key] ?? [:]
            if let selected { return Double((adjust[selected] ?? .none).scale) }
            return Double(items.first.map { (adjust[$0.element] ?? .none).scale } ?? 1)
        } set: { v in
            let targets = selected.map { [$0] } ?? PadElement.allCases
            for el in targets {
                var a = working[key]?[el] ?? .none
                a.scale = CGFloat(v)
                working[key, default: [:]][el] = a
            }
        }
    }

    private func controls(layout: PlayLayout, key: String, items: [PadItem], canTurn: Bool) -> some View {
        let pic = layout.picture
        let width = min(360, pic.width - 24)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selected?.label ?? "Whole pad").font(.headline)
                Spacer()
                if selected != nil {
                    Button("Whole pad") { selected = nil }.font(.subheadline)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: scaleBinding(key: key, items: items), in: 0.6...1.6)
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }
            Text(canTurn ? "Drag a button to move it. Tap one to resize just that one. Turn the iPhone to set up the other way of holding it."
                         : "Drag a button to move it. Tap one to resize just that one.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(selected == nil ? "Reset all" : "Reset", role: .destructive) {
                    if let selected { working[key]?[selected] = nil } else { working[key] = nil }
                }
                .disabled((working[key] ?? [:]).isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") {
                    layoutJSON = PadSettings.json(working)
                    dismiss()
                }
                .bold()
                .padding(.leading, 12)
            }
        }
        .padding(14)
        .frame(width: width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .position(x: pic.midX, y: pic.midY)
    }
}
