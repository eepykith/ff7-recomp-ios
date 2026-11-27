import CoreImage
import Foundation

// Development tool for the Builder's Steam download (not shipped): the same code the Builder
// runs, from the command line.
//   ff7steam login ACCOUNT.json [QR.png]   sign in by QR (prints the link, writes the code)
//   ff7steam info ACCOUNT.json             log on; list the game's depots and wanted files
//   ff7steam download ACCOUNT.json DIR     download the files the Builder needs into DIR

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: ff7steam login|info|download ACCOUNT.json [QR.png | DIR]")
    exit(2)
}
let store = FileAccountStore(url: URL(fileURLWithPath: args[2]))

func qrPNG(_ text: String, to path: String) {
    let f = CIFilter(name: "CIQRCodeGenerator")!
    f.setValue(Data(text.utf8), forKey: "inputMessage")
    f.setValue("M", forKey: "inputCorrectionLevel")
    guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return }
    let ctx = CIContext()
    try? ctx.writePNGRepresentation(of: img, to: URL(fileURLWithPath: path), format: .RGBA8,
                                    colorSpace: CGColorSpaceCreateDeviceRGB())
}

func log(_ s: String) {
    let t = ISO8601DateFormatter().string(from: Date())
    print("[\(t)] \(s)")
    fflush(stdout)
}

let task = Task {
    do {
        var c = try await SteamConnection.connect()
        log("connected")
        switch args[1] {
        case "login":
            var s = try await SteamLogin.beginQR(c)
            log("QR: \(s.challengeURL)")
            if args.count > 3 { qrPNG(s.challengeURL, to: args[3]); log("QR image: \(args[3])") }
            while true {
                try await Task.sleep(nanoseconds: UInt64(s.interval * 1e9))
                let result: SteamLogin.PollResult
                do { result = try await SteamLogin.poll(c, &s) }
                catch SteamConnection.Failure.closed(let why) {
                    // Steam drops a connection that has not signed in after a minute; the
                    // sign-in session goes on over a new one
                    log("reconnecting (\(why))")
                    c = try await SteamConnection.connect()
                    continue
                }
                switch result {
                case .waiting(let newURL):
                    if let newURL {
                        log("QR changed: \(newURL)")
                        if args.count > 3 { qrPNG(newURL, to: args[3]) }
                    }
                case .approved(let account):
                    store.save(account)
                    log("signed in as \(account.accountName)")
                    try await SteamLogin.logOn(c, account)
                    log("logged on: steamid \(c.steamID ?? 0), cell \(c.cellID)")
                    exit(0)
                }
            }
        case "info", "download":
            guard let account = store.load() else { log("no sign-in in \(args[2])"); exit(1) }
            try await SteamLogin.logOn(c, account)
            log("logged on: steamid \(c.steamID ?? 0), cell \(c.cellID)")
            let dest = URL(fileURLWithPath: args.count > 3 ? args[3] : NSTemporaryDirectory() + "ff7steam")
            let d = SteamGameDownload(connection: c, destination: dest)
            if args[1] == "info" { SteamGameDownload.infoOnly = true }
            var last = Date.distantPast
            try await d.run { p in
                if Date().timeIntervalSince(last) > 2 || p.phase == "Done" || p.done == 0 {
                    last = Date()
                    log(String(format: "%@  %.2f / %.2f GB  files %d/%d", p.phase,
                               Double(p.done) / 1e9, Double(p.total) / 1e9, p.files, p.filesTotal))
                }
            }
            exit(0)
        default:
            log("unknown command \(args[1])")
            exit(2)
        }
    } catch {
        log("error: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
