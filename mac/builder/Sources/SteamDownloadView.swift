import AppKit
import CoreImage
import SwiftUI

/// "Download from Steam…": sign in once by scanning a QR code with the Steam app (no password
/// is typed here), then the game files your account owns come straight from Steam into the
/// Builder's own folder, each checked against Steam's checksum. Pressing it again after a stop
/// goes on where it was; with the files all there it only checks them.
@MainActor
final class SteamDownloader: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting(String)
        case qr(String)
        case downloading
        case done
        case failed(String)
    }

    /// Where the download goes: laid out as Steam installs the game.
    nonisolated static let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("FF7Recomp Builder/FINAL FANTASY VII Steam Edition", isDirectory: true)

    /// Whether a game folder is this download (not the player's own Steam install).
    nonisolated static func isDownload(_ url: URL?) -> Bool {
        url?.standardizedFileURL.path == folder.standardizedFileURL.path
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress = SteamGameDownload.Progress(phase: "")
    @Published private(set) var accountName: String?
    /// The size of the downloaded game files on disk (0: none).
    @Published private(set) var downloadedBytes: Int64 = 0
    private let store = KeychainAccountStore()
    private var task: Task<Void, Never>?
    private var connection: SteamConnection?

    init() {
        accountName = store.load()?.accountName
        refreshSize()
    }

    func refreshSize() {
        Task.detached(priority: .utility) {
            let n = Self.folderSize()
            await MainActor.run { self.downloadedBytes = n }
        }
    }

    nonisolated private static func folderSize() -> Int64 {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var n: Int64 = 0
        for case let url as URL in e {
            n += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return n
    }

    /// Deletes the downloaded game files (only the Builder's own folder; never a Steam install).
    /// The Steam sign-in stays. Downloading again fetches them all.
    func removeDownload() {
        stop()
        try? FileManager.default.removeItem(at: Self.folder)
        downloadedBytes = 0
        state = .idle
    }

    static func gb(_ bytes: Int64) -> String { String(format: "%.1f GB", Double(bytes) / 1e9) }

    var running: Bool {
        switch state {
        case .connecting, .qr, .downloading: return true
        default: return false
        }
    }

    func start(onDone: @escaping (URL) -> Void) {
        guard !running else { return }
        state = .connecting("Connecting to Steam…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run()
                self.state = .done
                self.refreshSize()
                onDone(Self.folder)
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.state = Task.isCancelled ? .idle : .failed("\(error)")
            }
            self.connection?.close()
            self.connection = nil
            self.refreshSize()
        }
    }

    func stop() {
        task?.cancel()
        connection?.close()
    }

    func signOut() {
        stop()
        store.clear()
        accountName = nil
        state = .idle
    }

    private func run() async throws {
        var c = try await SteamConnection.connect()
        connection = c
        var account = store.load()
        if let a = account {
            state = .connecting("Signing in to Steam…")
            do {
                try await SteamLogin.logOn(c, a)
            } catch let e as SteamLogin.LogOnError where e.needsNewSignIn {
                store.clear()
                accountName = nil
                account = nil
                c.close()
                c = try await SteamConnection.connect()
                connection = c
            }
        }
        if account == nil {
            var s = try await SteamLogin.beginQR(c)
            state = .qr(s.challengeURL)
            signIn: while true {
                try await Task.sleep(nanoseconds: UInt64(max(1, s.interval) * 1e9))
                let result: SteamLogin.PollResult
                do {
                    result = try await SteamLogin.poll(c, &s)
                } catch SteamConnection.Failure.closed {
                    try Task.checkCancellation()
                    // Steam drops a connection that has not signed in after about a minute;
                    // the sign-in goes on over a new one
                    c = try await SteamConnection.connect()
                    connection = c
                    continue
                }
                switch result {
                case .waiting(let url):
                    if let url { state = .qr(url) }
                case .approved(let a):
                    store.save(a)
                    accountName = a.accountName
                    state = .connecting("Signing in to Steam…")
                    try await SteamLogin.logOn(c, a)
                    break signIn
                }
            }
        }

        state = .downloading
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let d = SteamGameDownload(connection: c, destination: Self.folder)
        var last = Date.distantPast
        try await d.run { [weak self] p in
            let now = Date()
            guard now.timeIntervalSince(last) > 0.25 || p.phase == "Done" else { return }
            last = now
            Task { @MainActor in self?.progress = p }
        }
    }
}

struct SteamDownloadView: View {
    @ObservedObject var steam: SteamDownloader
    let onDone: (URL) -> Void
    let onRemoved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download from Steam").font(.title2.bold())
            Text("The game files your Steam account owns come straight from Steam (about 3.6 GB) and each is checked. If the download stops, start it again: it goes on where it was.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch steam.state {
            case .idle:
                if let name = steam.accountName {
                    Text("Signed in to Steam as \(name).").font(.callout)
                } else {
                    Text("You sign in once by scanning a QR code with the Steam app on your phone. You never type your Steam password into FF7Recomp.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .connecting(let text):
                HStack { ProgressView().controlSize(.small); Text(text) }
            case .qr(let url):
                HStack(alignment: .top, spacing: 18) {
                    if let img = qrImage(url) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 200, height: 200)
                            .accessibilityLabel("Steam sign-in QR code")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan this with the Steam app").font(.headline)
                        Text("In the Steam app on your phone: Steam Guard › Scan a QR code, then approve FF7Recomp Builder. The code changes every so often; scan the one shown.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack { ProgressView().controlSize(.small); Text("Waiting for your approval…").font(.callout) }
                    }
                }
            case .downloading:
                let p = steam.progress
                ProgressView(value: p.total > 0 ? Double(p.done) / Double(p.total) : 0) {
                    Text(p.phase).lineLimit(1).truncationMode(.middle)
                } currentValueLabel: {
                    Text(String(format: "%.2f of %.2f GB · %d of %d files", Double(p.done) / 1e9, Double(p.total) / 1e9, p.files, p.filesTotal))
                }
            case .done:
                Label("The game files are here and checked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.headline)
            case .failed(let message):
                Label("The download did not finish", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.headline)
                Text(message).font(.callout).textSelection(.enabled)
            }

            if steam.downloadedBytes > 0, !steam.running {
                HStack {
                    Text("Downloaded game files: \(SteamDownloader.gb(steam.downloadedBytes)), kept for your next build.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove…", role: .destructive) { confirmRemove = true }
                }
            }

            HStack {
                if steam.accountName != nil, !steam.running {
                    Button("Sign out of Steam") { steam.signOut() }
                }
                Spacer()
                if steam.running {
                    Button("Stop", role: .destructive) { steam.stop() }
                } else if steam.state == .done {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(steam.state == .idle ? "Download" : "Try again") {
                        steam.start(onDone: onDone)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .removeDownloadDialog(isPresented: $confirmRemove, steam: steam, onRemoved: onRemoved)
    }

    private func qrImage(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

extension View {
    /// Asks before deleting the downloaded game files.
    func removeDownloadDialog(isPresented: Binding<Bool>, steam: SteamDownloader, onRemoved: @escaping () -> Void) -> some View {
        confirmationDialog("Remove the downloaded game files?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Remove \(SteamDownloader.gb(steam.downloadedBytes))", role: .destructive) {
                steam.removeDownload()
                onRemoved()
            }
        } message: {
            Text("They are deleted from this Mac. Your Steam sign-in stays, and your Steam install, if you have one, is not touched. The next build needs them again: Download from Steam fetches them (about 3.6 GB).")
        }
    }
}
