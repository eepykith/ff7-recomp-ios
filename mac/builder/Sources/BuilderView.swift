import AppKit
import SwiftUI

/// One window: your game, Xcode, Build. The IPA it writes holds the game built from your copy
/// and your game's files: for your own devices only.
struct BuilderView: View {
    @StateObject private var builder = Builder()
    @State private var pickFolder = false
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FF7Recomp Builder").font(.largeTitle.bold())
                Text("Builds FF7Recomp for your iPhone from your own FINAL FANTASY VII: the game translated for iPhone, with your game files in it, ready to sign and install.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    row(title: "Your game", status: gameStatus) {
                        Button("Choose…") { pickFolder = true }
                            .disabled(builder.phase == .building)
                    }
                    if let folder = builder.gameFolder {
                        Text(folder.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Divider()
                    row(title: "Xcode", status: xcodeStatus) {
                        Button("Check again") { builder.checkXcode() }
                            .disabled(builder.phase == .building)
                    }
                    if builder.kit == nil {
                        Divider()
                        row(title: "Engine kit", status: (.red, "Missing from this app: build it with tools/make_builder_kit.sh")) { EmptyView() }
                    }
                }
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    switch builder.phase {
                    case .idle:
                        Text("The first build takes a while (lifting and compiling the game). The IPA is about 3 GB.")
                            .font(.callout).foregroundStyle(.secondary)
                    case .building:
                        ProgressView(value: builder.progress) { Text(builder.step) } currentValueLabel: {
                            Text("\(Int((builder.progress * 100).rounded())) %")
                        }
                    case .done(let url):
                        Label("FF7Recomp.ipa is ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.headline)
                        Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("Sign it and install it on your iPhone (a development profile, AltStore, SideStore…). Open FF7Recomp: it confirms your game files and Play starts the game. Mods unlock once the files are confirmed.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    case .failed(let message):
                        Label("The build did not finish", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.headline)
                        Text(message).font(.callout).textSelection(.enabled)
                    }
                    HStack {
                        if builder.phase == .building {
                            Button("Stop", role: .destructive) { builder.stop() }
                        } else {
                            Button {
                                saveAs()
                            } label: {
                                Label("Build FF7Recomp.ipa…", systemImage: "hammer.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!builder.canBuild)
                        }
                        Spacer()
                        Toggle("Show log", isOn: $showLog).toggleStyle(.switch).controlSize(.small)
                    }
                }
                .padding(6)
            }

            if showLog {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(builder.log.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.caption.monospaced()).textSelection(.enabled).id(i)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: builder.log.count) { proxy.scrollTo(builder.log.count - 1) }
                }
            }

            Spacer(minLength: 0)
            Text("The IPA holds the game built from your copy and your game's files: for your own devices only, never share it. You need your own Steam copy of FINAL FANTASY VII. Not affiliated with Square Enix.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { builder.choose(url) }
        }
    }

    private var gameStatus: (Color, String) {
        switch builder.game {
        case .none: return builder.gameFolder == nil ? (.secondary, "Choose your FINAL FANTASY VII Steam Edition folder") : (.secondary, "Checking…")
        case .ok: return (.green, "FINAL FANTASY VII 1.02 US (Steam): ff7_en checked")
        case .problem(let text): return (.orange, text)
        }
    }

    private var xcodeStatus: (Color, String) {
        builder.xcode != nil ? (.green, "iOS SDK found")
            : (.orange, "Install Xcode from the App Store and open it once: building for iPhone needs its iOS SDK.")
    }

    private func row<Trailing: View>(title: String, status: (Color, String), @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).frame(width: 100, alignment: .leading)
            Text(status.1).foregroundStyle(status.0).fixedSize(horizontal: false, vertical: true)
            Spacer()
            trailing()
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FF7Recomp.ipa"
        panel.allowedContentTypes = [.init(filenameExtension: "ipa") ?? .data]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url { builder.build(to: url) }
    }
}
