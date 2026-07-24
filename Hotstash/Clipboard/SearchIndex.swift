import Foundation

// MARK: - SearchIndex

/// In-memory search index over the clipboard history.
///
/// SwiftData substring predicates (`localizedStandardContains`) full-scan the
/// SQLite store on every keystroke, which crawls once history is unbounded.
/// Instead we keep one case/diacritic-folded copy of every searchable field in
/// RAM and scan that: matching + ranking over tens of thousands of entries
/// runs in milliseconds.
///
/// The index is invalidated on every store save and lazily rebuilt on the next
/// search (or eagerly via `warmIfNeeded()` when the panel opens, so the first
/// keystroke never pays the rebuild).
@MainActor
final class SearchIndex {

    struct Entry {
        let id: UUID
        let label: String      // folded; "" when unset
        let content: String    // folded, capped
        let ocrText: String    // folded
        let linkTitle: String  // folded
        let useCount: Int
        let timestamp: Date
    }

    // ponytail: index caps content at 10k chars per item to bound RAM;
    // raise or chunk if users report missing matches deep inside huge pastes.
    static let maxIndexedContentLength = 10_000

    private var entries: [Entry] = []
    private var isDirty = true

    /// Marks the index stale. Cheap — called from every store mutation.
    func invalidate() {
        isDirty = true
    }

    /// Rebuilds from the given items if stale.
    /// ponytail: full rebuild on any change; switch to incremental updates
    /// if rebuild time ever shows up on a profile.
    func rebuildIfNeeded(from items: @autoclosure () -> [ClipboardItem]) {
        guard isDirty else { return }
        entries = items().map { item in
            Entry(
                id: item.id,
                label: Self.fold(item.label),
                content: Self.fold(String(item.content.prefix(Self.maxIndexedContentLength))),
                ocrText: Self.fold(item.ocrText),
                linkTitle: Self.fold(item.linkTitle),
                useCount: item.useCount,
                timestamp: item.timestamp
            )
        }
        isDirty = false
    }

    /// Ranked matching item IDs, best first. Name (label) matches rank first,
    /// then content prefix/substring, then OCR/link-title hits; frequent use
    /// and recency break ties.
    func search(query: String, limit: Int) -> [UUID] {
        let q = Self.fold(query)
        guard !q.isEmpty else { return [] }
        let scored: [(entry: Entry, score: Int)] = entries.compactMap { entry in
            guard let score = Self.score(entry, query: q) else { return nil }
            return (entry, score)
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.entry.timestamp > $1.entry.timestamp
            }
            .prefix(limit)
            .map { $0.entry.id }
    }

    /// Relevance score, or nil when the entry doesn't match at all.
    private static func score(_ entry: Entry, query q: String) -> Int? {
        var score = 0
        if !entry.label.isEmpty {
            if entry.label == q { score += 10_000 }
            else if entry.label.hasPrefix(q) { score += 5_000 }
            else if entry.label.contains(q) { score += 2_000 }
        }
        if entry.content.hasPrefix(q) { score += 800 }
        else if entry.content.contains(q) { score += 300 }
        if score == 0 {
            guard entry.ocrText.contains(q) || entry.linkTitle.contains(q) else { return nil }
            score = 100
        }
        return score + min(entry.useCount, 50) * 5
    }

    /// Case- and diacritic-insensitive normal form (matches the old
    /// `localizedStandardContains` semantics).
    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
