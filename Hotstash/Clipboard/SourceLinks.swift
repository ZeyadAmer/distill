import AppKit

// MARK: - SourceLinks

/// Remembers the web page a text clip was copied from, and builds a link that
/// reopens that page scrolled to the copied passage (a URL text fragment,
/// `#:~:text=`).
///
/// Stored locally in UserDefaults rather than on `ClipboardItem`, so the
/// CloudKit schema doesn't change. Source links don't sync between Macs.
enum SourceLinks {

    private static let defaultsKey = "sourceLinks"
    /// ponytail: linear scan over at most this many entries; move to SwiftData if it grows.
    private static let maxEntries = 1000

    /// Chromium browsers (Chrome, Edge, Brave, Arc) tag copies with the page URL.
    private static let chromiumSourceURL = NSPasteboard.PasteboardType("org.chromium.source-url")
    /// Safari puts a web archive on rich copies; its main resource is the page.
    private static let webArchive = NSPasteboard.PasteboardType("com.apple.webarchive")

    /// Records the source page of the copy currently on `pasteboard`, if it has one.
    static func capture(from pasteboard: NSPasteboard, itemID: UUID) {
        guard let page = sourceURL(on: pasteboard) else { return }
        var entries = stored().filter { $0.first != itemID.uuidString }
        entries.append([itemID.uuidString, page.absoluteString])
        UserDefaults.standard.set(Array(entries.suffix(maxEntries)), forKey: defaultsKey)
    }

    /// The page this item was copied from, if known.
    static func page(for itemID: UUID) -> URL? {
        guard let entry = stored().last(where: { $0.first == itemID.uuidString }), entry.count == 2 else { return nil }
        return URL(string: entry[1])
    }

    /// `page` with a text fragment that highlights `text`. Long passages use the
    /// first and last few words (`start,end`) so small edits on the page still match.
    static func textFragmentURL(page: URL, text: String) -> URL {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty,
              var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return page }
        components.fragment = nil
        guard let base = components.url?.absoluteString else { return page }

        let directive = words.count <= 8
            ? encode(words.joined(separator: " "))
            : encode(words.prefix(4).joined(separator: " ")) + "," + encode(words.suffix(4).joined(separator: " "))
        return URL(string: base + "#:~:text=" + directive) ?? page
    }

    // MARK: Private

    private static func stored() -> [[String]] {
        UserDefaults.standard.array(forKey: defaultsKey) as? [[String]] ?? []
    }

    private static func sourceURL(on pasteboard: NSPasteboard) -> URL? {
        if let s = pasteboard.string(forType: chromiumSourceURL), let url = webURL(s) { return url }
        if let data = pasteboard.data(forType: webArchive),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let main = plist["WebMainResource"] as? [String: Any],
           let s = main["WebResourceURL"] as? String,
           let url = webURL(s) {
            return url
        }
        return nil
    }

    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// Text-directive encoding: everything but ASCII alphanumerics and `._~`
    /// is percent-encoded (the spec requires `-`, `,` and `&` to be).
    private static func encode(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
