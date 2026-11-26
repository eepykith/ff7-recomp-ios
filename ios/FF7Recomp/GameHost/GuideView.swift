import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The player's own game guides (a GameFAQs walkthrough, a PDF), read beside the game: in the
/// status panel's place on the iPhone Duo upright, full screen over the paused game otherwise.
/// FF7Recomp ships no guides; they go in Files > On My iPhone > FF7Recomp > Guides (TXT, HTML
/// or PDF), or "Add a guide…" copies one in. Each guide keeps its place.
enum GuideLibrary {
    static let folderName = "Guides"
    static let lastKey = "ff7.guideLast"
    static let textScaleKey = "ff7.guideTextScale"
    static let types: [UTType] = [.plainText, .html, .pdf]

    static var folder: URL {
        let url = AppPaths.documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func guides() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { kind($0) != nil }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    enum Kind { case text, html, pdf }

    static func kind(_ url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "txt", "text", "faq", "md": return .text
        case "html", "htm", "xhtml": return .html
        case "pdf": return .pdf
        default: return nil
        }
    }

    /// Copies a picked file into Guides (replacing one of the same name).
    static func add(_ picked: URL) throws -> URL {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let dst = folder.appendingPathComponent(picked.lastPathComponent)
        if dst.standardizedFileURL != picked.standardizedFileURL {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: picked, to: dst)
        }
        return dst
    }

    // where the player is in each guide: a character offset (text), a scroll fraction (HTML),
    // a page index (PDF)
    static func position(_ url: URL) -> Double {
        UserDefaults.standard.double(forKey: "ff7.guidePos." + url.lastPathComponent)
    }

    static func setPosition(_ value: Double, for url: URL) {
        UserDefaults.standard.set(value, forKey: "ff7.guidePos." + url.lastPathComponent)
    }
}

/// The reader's buttons reach the document view through this (find, text size).
final class GuideController: ObservableObject {
    weak var find: UIFindInteraction?
}

/// A guide with a small bar: the guide's name (a menu of the others and "Add a guide…"),
/// text size, find, close.
struct GuideView: View {
    /// In the status panel (smaller bar), or full screen.
    var compact = false
    let onClose: () -> Void

    @AppStorage(GuideLibrary.lastKey) private var last = ""
    @AppStorage(GuideLibrary.textScaleKey) private var textScale = 1.0
    @State private var guides: [URL] = []
    @State private var importing = false
    @State private var browsing = false
    @State private var error: String?
    @StateObject private var controller = GuideController()

    private var current: URL? {
        guides.first { $0.lastPathComponent == last } ?? guides.first
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider().overlay(Color.white.opacity(0.2))
            if let url = current {
                reader(url)
                    .id(url)
            } else {
                empty
            }
        }
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
        .onAppear { guides = GuideLibrary.guides() }
        .fileImporter(isPresented: $importing, allowedContentTypes: GuideLibrary.types,
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                do {
                    var added: URL?
                    for u in urls { added = try GuideLibrary.add(u) }
                    guides = GuideLibrary.guides()
                    if let added { last = added.lastPathComponent }
                } catch { self.error = error.localizedDescription }
            case .failure(let e): error = e.localizedDescription
            }
        }
        .sheet(isPresented: $browsing) {
            GuideBrowser { saved in
                guides = GuideLibrary.guides()
                last = saved
            }
        }
        .alert("Could not add the guide", isPresented: Binding { error != nil } set: { if !$0 { error = nil } }) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var bar: some View {
        let size: CGFloat = compact ? 15 : 17
        return HStack(spacing: compact ? 14 : 20) {
            Menu {
                ForEach(guides, id: \.self) { g in
                    Button { last = g.lastPathComponent } label: {
                        if g == current { Label(g.deletingPathExtension().lastPathComponent, systemImage: "checkmark") }
                        else { Text(g.deletingPathExtension().lastPathComponent) }
                    }
                }
                Divider()
                Button { browsing = true } label: { Label("Find guides on GameFAQs", systemImage: "magnifyingglass") }
                Button { importing = true } label: { Label("Add a guide from Files…", systemImage: "plus") }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                    Text(current?.deletingPathExtension().lastPathComponent ?? "Guides")
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: size * 0.7, weight: .semibold))
                }
                .font(.system(size: size, weight: .semibold))
            }
            Spacer(minLength: 0)
            if let url = current, GuideLibrary.kind(url) != .pdf {
                Button { textScale = max(0.6, textScale - 0.1) } label: { Image(systemName: "textformat.size.smaller") }
                    .accessibilityLabel("Smaller text")
                Button { textScale = min(2.5, textScale + 0.1) } label: { Image(systemName: "textformat.size.larger") }
                    .accessibilityLabel("Larger text")
            }
            if current != nil {
                Button { controller.find?.presentFindNavigator(showingReplace: false) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Find in guide")
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .accessibilityLabel("Close the guide")
        }
        .font(.system(size: size))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 10 : 16)
        .padding(.vertical, compact ? 6 : 10)
    }

    @ViewBuilder
    private func reader(_ url: URL) -> some View {
        switch GuideLibrary.kind(url) {
        case .text: GuideTextView(url: url, scale: textScale, controller: controller)
        case .html: GuideWebView(url: url, scale: textScale, controller: controller)
        case .pdf: GuidePDFView(url: url, controller: controller)
        case nil: empty
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed").font(.system(size: compact ? 28 : 40))
            Text("No guides yet").font(.headline)
            Text("Find a Final Fantasy VII guide on GameFAQs and save it here, or add your own TXT, HTML or PDF guides (Files › On My iPhone › FF7Recomp › Guides). Each guide keeps your place.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button { browsing = true } label: {
                Label("Find guides on GameFAQs", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            Button { importing = true } label: {
                Label("Add a guide from Files…", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: 420, maxHeight: .infinity)
    }
}

// MARK: text (GameFAQs-style ASCII guides)

/// A plain-text guide in a monospaced font sized so 80 columns fit the width (ASCII-art
/// tables stay lined up), times the player's text size. Keeps the character at the top.
struct GuideTextView: UIViewRepresentable {
    let url: URL
    let scale: Double
    let controller: GuideController

    func makeUIView(context: Context) -> GuideTextUIView {
        let v = GuideTextUIView(url: url)
        v.scale = scale
        v.isFindInteractionEnabled = true
        controller.find = v.findInteraction
        return v
    }

    func updateUIView(_ v: GuideTextUIView, context: Context) {
        if v.scale != scale { v.scale = scale }
        controller.find = v.findInteraction
    }

    static func dismantleUIView(_ v: GuideTextUIView, coordinator: ()) { v.savePosition() }
}

final class GuideTextUIView: UITextView, UITextViewDelegate {
    let url: URL
    var scale: Double = 1 { didSet { if oldValue != scale { refit() } } }
    private var fittedWidth: CGFloat = 0
    private var restored = false

    init(url: URL) {
        self.url = url
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true            // long guides scroll without laying out all
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        textColor = UIColor(white: 0.92, alpha: 1)
        textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 40, right: 8)
        delegate = self
        text = Self.read(url)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != fittedWidth { refit() }
        if !restored, bounds.height > 0 {
            restored = true
            scrollTo(character: Int(GuideLibrary.position(url)))
        }
    }

    private func refit() {
        guard bounds.width > 0 else { return }
        let keep = restored ? topCharacter() : nil
        fittedWidth = bounds.width
        let usable = bounds.width - textContainerInset.left - textContainerInset.right
            - 2 * textContainer.lineFragmentPadding - 2
        // the advance of one character at 10 pt, measured: 81 columns fit (80 and a little room)
        let ten = ("0" as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]).width
        let fitted = min(20, 10 * usable / (81 * ten))
        font = .monospacedSystemFont(ofSize: max(8, fitted * scale), weight: .regular)
        if let keep { scrollTo(character: keep) }
    }

    private func topCharacter() -> Int {
        let p = CGPoint(x: textContainerInset.left + 2, y: contentOffset.y + textContainerInset.top + 2)
        guard let pos = closestPosition(to: p) else { return 0 }
        return offset(from: beginningOfDocument, to: pos)
    }

    private func scrollTo(character: Int) {
        guard character > 0,
              let pos = position(from: beginningOfDocument, offset: min(character, text.utf16.count)),
              let range = textRange(from: pos, to: pos) else { return }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: min(character + 1, text.utf16.count)))
        let y = firstRect(for: range).minY - textContainerInset.top
        let maxY = max(0, contentSize.height - bounds.height)
        contentOffset = CGPoint(x: 0, y: min(max(0, y), maxY))
    }

    func savePosition() { GuideLibrary.setPosition(Double(topCharacter()), for: url) }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { savePosition() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { savePosition() }
    }
}

// MARK: HTML

struct GuideWebView: UIViewRepresentable {
    let url: URL
    let scale: Double
    let controller: GuideController

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.isOpaque = false
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.isFindInteractionEnabled = true
        v.navigationDelegate = context.coordinator
        v.scrollView.delegate = context.coordinator
        v.pageZoom = scale
        context.coordinator.web = v
        v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        controller.find = v.findInteraction
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        if v.pageZoom != scale { v.pageZoom = scale }
        controller.find = v.findInteraction
    }

    static func dismantleUIView(_ v: WKWebView, coordinator: Coordinator) { coordinator.save() }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        let url: URL
        weak var web: WKWebView?
        private var restored = false
        init(url: URL) { self.url = url }

        private var fraction: Double {
            guard let s = web?.scrollView else { return 0 }
            let range = s.contentSize.height - s.bounds.height
            return range > 0 ? Double(s.contentOffset.y / range) : 0
        }

        func save() { if restored { GuideLibrary.setPosition(fraction, for: url) } }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let f = GuideLibrary.position(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak webView] in
                guard let s = webView?.scrollView else { return }
                let range = s.contentSize.height - s.bounds.height
                if range > 0 { s.contentOffset.y = CGFloat(f) * range }
                self?.restored = true
            }
        }

        // A link to a section of this guide (a table of contents) jumps there in the reader. A
        // guide saved from GameFAQs keeps the page's address as its <base>, so its "#section"
        // links read as web addresses: any link with a #fragment the page has is in-guide.
        // Other files in the guide's folder open here; anything else opens in Safari.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = action.request.url, action.navigationType == .linkActivated else {
                decisionHandler(.allow); return
            }
            let external = {
                if u.isFileURL { decisionHandler(.allow) }
                else { UIApplication.shared.open(u); decisionHandler(.cancel) }
            }
            guard let fragment = u.fragment(percentEncoded: false), !fragment.isEmpty else {
                external(); return
            }
            let js = """
            (function(f){
              var e = document.getElementById(f) || document.getElementsByName(f)[0];
              if (!e) return false;
              e.scrollIntoView({block: 'start'});
              return true;
            })(\(Self.jsString(fragment)))
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                if (result as? Bool) == true {
                    decisionHandler(.cancel)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.save() }
                } else {
                    external()
                }
            }
        }

        static func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { save() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
            if !willDecelerate { save() }
        }
    }
}

// MARK: PDF

struct GuidePDFView: UIViewRepresentable {
    let url: URL
    let controller: GuideController

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.isFindInteractionEnabled = true
        v.document = PDFDocument(url: url)
        let page = Int(GuideLibrary.position(url))
        if let doc = v.document, page > 0, page < doc.pageCount, let p = doc.page(at: page) {
            DispatchQueue.main.async { v.go(to: p) }
        }
        context.coordinator.observe(v)
        controller.find = v.findInteraction
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) { controller.find = v.findInteraction }

    final class Coordinator: NSObject {
        let url: URL
        private var token: NSObjectProtocol?
        init(url: URL) { self.url = url }

        func observe(_ v: PDFView) {
            token = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [url] _ in
                if let page = v.currentPage, let doc = v.document {
                    GuideLibrary.setPosition(Double(doc.index(for: page)), for: url)
                }
            }
        }

        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}
