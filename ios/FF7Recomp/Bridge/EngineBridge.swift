import Foundation

struct EngineState {
    let statusCode: Int32
    let booted: Bool
    let frame: Int32
    let message: String
}

enum EngineBridge {
    static func version() -> String {
        String(cString: ff7_host_version())
    }

    @discardableResult
    static func probe(width: Int32, height: Int32, fps: Int32) -> EngineState {
        var config = ff7_host_config(
            width: width,
            height: height,
            target_fps: fps,
            metal: 1
        )
        _ = ff7_host_init(&config)
        return snapshot()
    }

    /// Starts the game from the game folder (AppPaths.game).
    static func boot(gameDir: String?) -> EngineState {
        if let gameDir {
            gameDir.withCString { _ = ff7_host_boot($0) }
        } else {
            _ = ff7_host_boot(nil)
        }
        return snapshot()
    }

    /// The game is compiled into this app: the Mac build (tools/ff7recomp-mac install) links
    /// the lifted game in (FF7RecompBundled target). The launcher alone has no game code.
    static var hasGameCode: Bool {
#if FF7_BUNDLE_GAME
        true
#else
        false
#endif
    }

    static func shutdown() {
        ff7_host_shutdown()
    }

    static func setPad(buttons: UInt16, lt: UInt8 = 0, rt: UInt8 = 0, lx: Int16 = 0, ly: Int16 = 0, rx: Int16 = 0, ry: Int16 = 0) {
        ff7_platform_set_pad(buttons, lt, rt, lx, ly, rx, ry)
    }

    private static func snapshot() -> EngineState {
        let state = ff7_host_get_state()
        return EngineState(
            statusCode: state.status,
            booted: state.booted != 0,
            frame: state.frame,
            message: String(cString: ff7_host_message())
        )
    }
}
