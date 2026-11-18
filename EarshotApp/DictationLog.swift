// The notes log of dictations (ADR-2611062250): pure logic, Foundation only.
import Foundation

struct DictationLog: Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var date: Date
        var text: String
        var app: String?
        var seconds: Double?
    }

    /// Newest first.
    var entries: [Entry]
    let limit: Int

    init(entries: [Entry] = [], limit: Int = 10_000) {
        self.limit = limit
        self.entries = entries.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        if self.entries.count > limit { self.entries = Array(self.entries.prefix(max(limit, 0))) }
    }

    /// Adds a note and returns the oldest notes the limit removed, so the caller can say so (ADR-2611072100 A6).
    @discardableResult
    mutating func add(_ entry: Entry) -> [Entry] {
        var e = entry
        e.text = e.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.text.isEmpty else { return [] }
        // Insert after every entry that is as new or newer, so equal dates keep the order they arrived in.
        let index = entries.firstIndex { $0.date < e.date } ?? entries.count
        entries.insert(e, at: index)
        guard entries.count > limit else { return [] }
        let removed = Array(entries.suffix(entries.count - max(limit, 0)))
        entries.removeLast(removed.count)
        return removed
    }

    /// What to tell the user when the limit removed `count` notes, or nil when it removed none.
    static func droppedNotice(count: Int, limit: Int) -> String? {
        guard count > 0 else { return nil }
        let which = count == 1 ? "the oldest one was removed" : "the oldest \(count) were removed"
        return "Notes keeps the newest \(grouped(limit)) notes, so \(which)."
    }

    /// 10000 → "10,000", whatever the Mac's region, so the message reads the same in tests and in the app.
    private static func grouped(_ n: Int) -> String {
        let digits = Array(String(n))
        var out = ""
        for (i, d) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return out
    }

    mutating func remove(id: String) { entries.removeAll { $0.id == id } }

    mutating func clear() { entries.removeAll() }

    @discardableResult
    func save(to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return false }
        // Owner-only file in an owner-only folder (ADR-2611072100 A3).
        return PrivateFiles.writeAtomically(data, to: url)
    }

    static func load(from url: URL) -> DictationLog {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return DictationLog() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let entries = try? decoder.decode([Entry].self, from: data) {
            return DictationLog(entries: entries)
        }
        // Damaged: keep the bytes aside (replacing an older .bad) so a new log never overwrites them.
        let aside = URL(fileURLWithPath: url.path + ".bad")
        try? fm.removeItem(at: aside)
        try? fm.moveItem(at: url, to: aside)
        return DictationLog()
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Earshot/notes.json")
    }
}
