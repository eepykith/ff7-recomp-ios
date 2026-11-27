import Foundation

/// Valve's text KeyValues ("key" "value", "key" { ... }): the format of an app's info from Steam.
final class KeyValues {
    let key: String
    var value: String?
    var children: [KeyValues] = []

    init(key: String, value: String? = nil) {
        self.key = key
        self.value = value
    }

    subscript(_ k: String) -> KeyValues? {
        children.first { $0.key.caseInsensitiveCompare(k) == .orderedSame }
    }

    /// The first (root) node of a text buffer; a trailing NUL is allowed.
    static func parse(_ text: String) -> KeyValues? {
        var tokens: [String?] = []           // nil: "{"; "\u{0}": "}"
        let s = Array(text.unicodeScalars)
        var i = 0
        while i < s.count {
            let ch = s[i]
            if ch == "\u{0}" { break }
            if ch == " " || ch == "\t" || ch == "\n" || ch == "\r" { i += 1; continue }
            if ch == "/" && i + 1 < s.count && s[i + 1] == "/" {
                while i < s.count && s[i] != "\n" { i += 1 }
                continue
            }
            if ch == "{" { tokens.append(nil); i += 1; continue }
            if ch == "}" { tokens.append("\u{0}"); i += 1; continue }
            var out = String.UnicodeScalarView()
            if ch == "\"" {
                i += 1
                while i < s.count && s[i] != "\"" {
                    if s[i] == "\\", i + 1 < s.count {
                        i += 1
                        switch s[i] {
                        case "n": out.append("\n")
                        case "t": out.append("\t")
                        default: out.append(s[i])
                        }
                    } else {
                        out.append(s[i])
                    }
                    i += 1
                }
                i += 1
            } else {
                while i < s.count, !" \t\r\n{}\"".unicodeScalars.contains(s[i]) {
                    out.append(s[i])
                    i += 1
                }
            }
            tokens.append(String(out))
        }

        var t = 0
        func node(_ key: String) -> KeyValues {
            let kv = KeyValues(key: key)
            while t < tokens.count {
                guard let k = tokens[t] else { t += 1; continue }
                if k == "\u{0}" { t += 1; return kv }
                t += 1
                guard t < tokens.count else { break }
                if tokens[t] == nil {
                    t += 1
                    kv.children.append(node(k))
                } else if let v = tokens[t], v != "\u{0}" {
                    t += 1
                    kv.children.append(KeyValues(key: k, value: v))
                }
            }
            return kv
        }
        guard tokens.count >= 2, let rootKey = tokens[0], tokens[1] == nil else { return nil }
        t = 2
        return node(rootKey)
    }
}
