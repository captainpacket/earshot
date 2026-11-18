import Combine
import Foundation

/// The notes log (ADR-2611062250) as an observable object: wraps `DictationLog` and its file.
/// Text only; it never writes the text anywhere but the log file.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var items: [NoteItem] = []
    /// True once a save has failed; the in-memory log is kept.
    @Published private(set) var saveFailed = false

    private var log: DictationLog
    private let url: URL

    init(url: URL = DictationLog.defaultURL) {
        self.url = url
        self.log = DictationLog.load(from: url)
        refresh()
    }

    /// How many notes the log keeps; past it, the oldest are removed.
    var limit: Int { log.limit }

    /// Adds a note and returns how many old notes the limit removed (ADR-2611072100 A6).
    @discardableResult
    func add(text: String, seconds: Double?) -> Int {
        let removed = log.add(DictationLog.Entry(id: UUID().uuidString, date: Date(), text: text, app: nil, seconds: seconds))
        commit()
        return removed.count
    }

    func remove(id: String) {
        log.remove(id: id)
        commit()
    }

    func clear() {
        log.clear()
        try? FileManager.default.removeItem(atPath: url.path + ".bad")
        commit()
    }

    private func commit() {
        saveFailed = !log.save(to: url)
        refresh()
    }

    private func refresh() {
        items = log.entries.map { NoteItem(id: $0.id, date: $0.date, text: $0.text, seconds: $0.seconds) }
    }
}
