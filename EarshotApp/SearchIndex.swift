// SearchIndex: the pure logic behind the ⌘K search. Foundation only.
import Foundation

struct SearchDoc { var id: String; var title: String; var text: String }
struct SearchDestination { var id: String; var title: String; var detail: String; var keywords: [String] }

enum SearchHit: Equatable {
    case recording(id: String, title: String, snippet: String)
    case destination(id: String, title: String, detail: String)
    case note(id: String, title: String, snippet: String)
}

/// A titled group of search results (ADR-2611072100 B7).
struct SearchSection: Equatable {
    let title: String
    let hits: [SearchHit]
}

enum SearchIndex {
    private static let maxDestinations = 4
    private static let maxNotes = 4
    private static let wholeLimit = 100
    private static let windowSize = 90

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func search(_ query: String, recordings: [SearchDoc], destinations: [SearchDestination], notes: [SearchDoc] = [], limit: Int = 8) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let rawWords = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let words = rawWords.map(fold)
        if words.isEmpty { return [] }

        var hits: [SearchHit] = []
        for d in destinations {
            if hits.count >= maxDestinations { break }
            let hay = fold(([d.title, d.detail] + d.keywords).joined(separator: " "))
            if words.allSatisfy({ hay.contains($0) }) {
                hits.append(.destination(id: d.id, title: d.title, detail: d.detail))
            }
        }

        func rank(_ docs: [SearchDoc]) -> [SearchDoc] {
            var titleHits: [SearchDoc] = []
            var bodyHits: [SearchDoc] = []
            for r in docs {
                let title = fold(r.title)
                if words.allSatisfy({ title.contains($0) }) { titleHits.append(r); continue }
                let hay = title + " " + fold(r.text)
                if words.allSatisfy({ hay.contains($0) }) { bodyHits.append(r) }
            }
            return titleHits + bodyHits
        }
        for n in rank(notes).prefix(maxNotes) {
            hits.append(.note(id: n.id, title: n.title, snippet: snippet(n.text, words: rawWords)))
        }
        for r in rank(recordings).prefix(max(0, limit)) {
            hits.append(.recording(id: r.id, title: r.title, snippet: snippet(r.text, words: rawWords)))
        }
        return hits
    }

    private static func snippet(_ text: String, words: [String]) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let chars = Array(collapsed)
        if chars.count <= wholeLimit { return collapsed }

        var start = 0
        for w in words {
            if let r = collapsed.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) {
                let offset = collapsed.distance(from: collapsed.startIndex, to: r.lowerBound)
                let len = collapsed.distance(from: r.lowerBound, to: r.upperBound)
                start = offset - max(0, windowSize - len) / 2
                break
            }
        }
        start = min(max(0, start), chars.count - windowSize)
        let end = start + windowSize
        var out = String(chars[start..<end])
        if start > 0 { out = "…" + out }
        if end < chars.count { out += "…" }
        return out
    }

    /// Groups hits under Recordings, Notes and Settings, in that order, keeping at most `limit` in all.
    static func sections(_ hits: [SearchHit], limit: Int = 8) -> [SearchSection] {
        var recordings: [SearchHit] = [], notes: [SearchHit] = [], settings: [SearchHit] = []
        for hit in hits {
            switch hit {
            case .recording: recordings.append(hit)
            case .note: notes.append(hit)
            case .destination: settings.append(hit)
            }
        }
        var left = max(0, limit)
        var out: [SearchSection] = []
        for (title, group) in [("Recordings", recordings), ("Notes", notes), ("Settings", settings)] {
            let taken = Array(group.prefix(left))
            left -= taken.count
            if !taken.isEmpty { out.append(SearchSection(title: title, hits: taken)) }
        }
        return out
    }

    /// Where each word of `query` appears in `text`, ignoring case and accents, merged and in text order,
    /// so the results can show why they matched.
    static func matchRanges(of query: String, in text: String) -> [Range<String.Index>] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var found: [Range<String.Index>] = []
        for w in words {
            var from = text.startIndex
            while from < text.endIndex,
                  let r = text.range(of: w, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
                found.append(r)
                from = r.upperBound > r.lowerBound ? r.upperBound : text.index(after: r.lowerBound)
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for r in found {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        return merged
    }
}
