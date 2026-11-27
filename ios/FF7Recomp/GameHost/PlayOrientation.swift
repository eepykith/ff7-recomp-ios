import SwiftUI

/// Which way play may turn, shared by the game and Settings › Size and layout, so the editor
/// shows the layout play really uses on this screen.
enum PlayOrientation {
    /// Upright play: on the iPhone Duo, while the hinge is open or half open (closed, the outer
    /// screen plays landscape only). Without a hinge, only on a large screen near 4:3: the
    /// shorter side at least 600 pt and the longer under 1.6 times it (an iPad), not a regular
    /// iPhone (about 2.2:1).
    static func allowsPortrait(_ size: CGSize, hingeOpen: Bool?) -> Bool {
        if let hingeOpen { return hingeOpen }
        let short = min(size.width, size.height), long = max(size.width, size.height)
        return short >= 600 && long / short < 1.6
    }

    static func lock(for size: CGSize, hingeOpen: Bool?) {
        guard size.width > 0, size.height > 0 else { return }
        OrientationLock.set(allowsPortrait(size, hingeOpen: hingeOpen) ? [.landscape, .portrait] : .landscape)
    }
}

extension View {
    /// Reports the iPhone Duo's hinge: true when open or half open, false when shut, nil when the
    /// device has no hinge. Does nothing before iOS 27.1.
    @ViewBuilder
    func watchHinge(_ action: @escaping (Bool?) -> Void) -> some View {
        if #available(iOS 27.1, *) {
            onHingeChange { _, context in
                action(context.hinge.map { $0.status != .closed })
            }
        } else {
            self
        }
    }
}
