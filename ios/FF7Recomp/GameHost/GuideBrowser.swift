import SwiftUI
import WebKit

/// "Find guides on GameFAQs": GameFAQs' Final Fantasy VII (PC) guide list in an in-app
/// browser. On a guide's page, Save guide keeps it in Files > FF7Recomp > Guides to read
/// beside the game, offline. A text guide is saved whole as TXT (GameFAQs shows it on one page,
/// in #faqtext); an HTML guide saves the page you're on.
struct GuideBrowser: View {
    static let start = URL(string: "https://gamefaqs.gamespot.com/pc/130791-final-fantasy-vii/faqs")!

    /// The saved guide's file name, to open it.
    let onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GuideBrowserModel()

    var body: some View {
        NavigationStack {
            GuideBrowserWeb(model: model)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("GameFAQs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { model.web?.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                            .accessibilityLabel("Back")
                        Button { model.web?.load(URLRequest(url: Self.start)) } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("All Final Fantasy VII guides")
                        Button {
                            Task {
                                if let name = await model.save() {
                                    onSaved(name)
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("Save guide", systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(!model.onGuide || model.saving)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let note = model.note {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
                }
        }
    }
}

@MainActor
final class GuideBrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    weak var web: WKWebView?
    @Published var canGoBack = false
    /// The page is one guide (…/faqs/<number>), not the list.
    @Published var onGuide = false
    @Published var saving = false
    @Published var note: String?

    func update(_ v: WKWebView) {
        canGoBack = v.canGoBack
        let path = v.url?.path ?? ""
        onGuide = v.url?.host?.hasSuffix("gamefaqs.gamespot.com") == true
            && path.range(of: #"/faqs/\d+"#, options: .regularExpression) != nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { update(webView) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { update(webView) }

    /// Saves the open guide into Guides; returns its file name.
    ///
    /// A text guide (#faqtext) is one page on GameFAQs: saved whole as TXT. An HTML guide is
    /// split into a page per section (…/faqs/71240/sector-8), its table of contents (.ftoc)
    /// linking them by name; every section is fetched and joined into one HTML file, each in a
    /// <section id="name"> with the contents linking "#name", so it reads offline and the
    /// contents jump within it.
    func save() async -> String? {
        guard let web else { return nil }
        saving = true
        note = "Saving the guide…"
        defer { saving = false }
        do {
            guard let r = try await web.callAsyncJavaScript(Self.collectJS, contentWorld: .page) as? [String: Any]
            else { throw SaveError.empty }
            let title = r["title"] as? String ?? "Guide"
            let name = Self.fileName(fromTitle: title)
            let dst: URL
            if let text = r["text"] as? String, !text.isEmpty {
                dst = GuideLibrary.folder.appendingPathComponent(name + ".txt")
                try Data(text.utf8).write(to: dst, options: .atomic)
            } else if let html = r["html"] as? String, !html.isEmpty {
                dst = GuideLibrary.folder.appendingPathComponent(name + ".html")
                let page = """
                <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
                <style>body{font-family:-apple-system;color:#ddd;background:#141414;padding:10px;line-height:1.45}
                a{color:#6cf}img{max-width:100%;height:auto}table{border-collapse:collapse}td,th{border:1px solid #444;padding:3px}
                section{border-top:1px solid #333;margin-top:18px}.ftoc ol{padding-left:22px}</style>
                <title>\(name)</title>\(html)
                """
                try Data(page.utf8).write(to: dst, options: .atomic)
            } else {
                throw SaveError.empty
            }
            EventLog.write("guide saved: \(dst.lastPathComponent) (\(r["sections"] as? Int ?? 1) sections)")
            note = nil
            return dst.lastPathComponent
        } catch {
            EventLog.write("guide save failed: \(error)")
            note = "This page has no guide text to save"
            Task { try? await Task.sleep(for: .seconds(3)); note = nil }
            return nil
        }
    }

    /// Runs in the GameFAQs page (same site, so its pages can be fetched).
    static let collectJS = #"""
    const t = document.querySelector('#faqtext');
    if (t) return { title: document.title, text: t.innerText, sections: 1 };
    const m = location.pathname.match(/^(.*\/faqs\/\d+)/);
    if (!m) return null;
    const root = m[1];
    const faqId = root.match(/\/faqs\/(\d+)$/)[1];
    // a section of this guide, on whichever platform's copy GameFAQs links it under
    const slugOf = (href, base) => {
      if (!href) return null;
      const u = new URL(href, base || location.origin + root + '/');
      const p = u.pathname.match(/\/faqs\/(\d+)\/([^\/?#]+)$/);
      return p && p[1] === faqId ? p[2] : null;
    };
    const tidy = (wrap, base) => {
      const w = wrap.cloneNode(true);
      w.querySelectorAll('.ftoc, script, iframe, style, noscript, .ad, [id^="div-gpt"], .ftoc_nav').forEach(e => e.remove());
      w.querySelectorAll('img').forEach(i => {
        const s = i.getAttribute('data-src') || i.getAttribute('src');
        if (s) i.setAttribute('src', new URL(s, base).href);
        i.removeAttribute('srcset'); i.setAttribute('loading', 'lazy');
      });
      w.querySelectorAll('a[href]').forEach(a => {
        const h = a.getAttribute('href');
        if (h.startsWith('#')) return;
        const s = slugOf(h, base);
        a.setAttribute('href', s ? '#' + s : new URL(h, base).href);
      });
      return w;
    };
    const fetchDoc = async (path) => {
      const r = await fetch(path, { credentials: 'include' });
      if (!r.ok) throw new Error('HTTP ' + r.status + ' ' + path);
      return new DOMParser().parseFromString(await r.text(), 'text/html');
    };
    const first = await fetchDoc(root);
    const toc = first.querySelector('.ftoc') || document.querySelector('.ftoc');
    const firstWrap = first.querySelector('#faqwrap');
    if (!firstWrap) return null;
    const slugs = [];
    if (toc) toc.querySelectorAll('a').forEach(a => {
      const s = slugOf(a.getAttribute('href'));
      if (s && !slugs.includes(s)) slugs.push(s);
    });
    let tocHTML = '';
    if (toc) {
      const c = toc.cloneNode(true);
      c.querySelectorAll('a').forEach(a => {
        const s = slugOf(a.getAttribute('href'));
        if (s) a.setAttribute('href', '#' + s); else a.removeAttribute('href');
      });
      tocHTML = c.outerHTML;
    }
    const parts = ['<section id="top">' + tidy(firstWrap, location.origin + root + '/').innerHTML + '</section>'];
    const docs = new Array(slugs.length);
    let next = 0;
    const worker = async () => {
      while (next < slugs.length) {
        const i = next++;
        try { docs[i] = await fetchDoc(root + '/' + slugs[i]); } catch (e) { docs[i] = null; }
      }
    };
    await Promise.all([worker(), worker(), worker(), worker()]);
    slugs.forEach((s, i) => {
      const w = docs[i] && docs[i].querySelector('#faqwrap');
      if (w) parts.push('<section id="' + s + '">' + tidy(w, location.origin + root + '/' + s).innerHTML + '</section>');
    });
    return { title: first.title || document.title, html: tocHTML + parts.join('\n'), sections: parts.length };
    """#

    enum SaveError: Error { case empty }

    /// "Final Fantasy VII - Guide and Walkthrough - PC - By Kao_Megura - GameFAQs"
    ///   -> "Guide and Walkthrough by Kao_Megura"
    /// "Final Fantasy VII Walkthrough & Guide - PC - By bover_87 - GameFAQs"
    ///   -> "Walkthrough & Guide by bover_87"
    static func fileName(fromTitle title: String) -> String {
        let platforms: Set<String> = ["pc", "ps", "ps4", "psp", "ps3", "switch", "xbox one", "android", "iphone", "ipad", "ios", "playstation"]
        let parts = title.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        let by = parts.first { $0.lowercased().hasPrefix("by ") }.map { String($0.dropFirst(3)) }
        let rest = parts.filter { p in
            let l = p.lowercased()
            return !l.hasPrefix("by ") && l != "gamefaqs" && !platforms.contains(l)
        }
        var kind = rest.last ?? "Guide"
        for prefix in ["Final Fantasy VII ", "Final Fantasy VII"] where kind.hasPrefix(prefix) && kind != prefix {
            kind = String(kind.dropFirst(prefix.count))
        }
        if kind == "Final Fantasy VII" { kind = "Guide" }
        if let by { kind += " by " + by }
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let clean = String(kind.components(separatedBy: bad).joined(separator: "-").prefix(80))
        return clean.isEmpty ? "Guide" : clean
    }
}

struct GuideBrowserWeb: UIViewRepresentable {
    let model: GuideBrowserModel

    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.navigationDelegate = model
        v.allowsBackForwardNavigationGestures = true
        model.web = v
        v.load(URLRequest(url: GuideBrowser.start))
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {}
}
