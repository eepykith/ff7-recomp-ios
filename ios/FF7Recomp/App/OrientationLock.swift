import UIKit

/// Which interface orientations the app allows right now. The play view locks to landscape:
/// FFNx sizes its swapchain once at boot and pillarboxes its 4:3 frame only in a wide window.
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .all

    static func set(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // the engine's stderr/stdout -> FF7Recomp/engine.log (src/ios/ff7_ios_log.c)
        ff7_ios_log_start(AppPaths.standard.root.path)
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
