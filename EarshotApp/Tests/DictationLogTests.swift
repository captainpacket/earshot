// Tests for DictationLog (ADR-2611062250). Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func tmp() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("DictationLogTests-\(UUID().uuidString)/dictations.json")
}
func entry(_ text: String, _ t: TimeInterval, app: String? = "Mail", seconds: Double? = 6) -> DictationLog.Entry {
    DictationLog.Entry(id: UUID().uuidString, date: Date(timeIntervalSince1970: t), text: text, app: app, seconds: seconds)
}

@main struct DictationLogTests {
    static func main() {
        // MARK: adding
        var log = DictationLog()
        checkTrue("a new log is empty", log.entries.isEmpty)
        log.add(entry("first", 100)); log.add(entry("second", 200)); log.add(entry("third", 150))
        checkTrue("newest first, by date, whatever order they were added", log.entries.map(\.text) == ["second", "third", "first"],
                  "\(log.entries.map(\.text))")
        log.add(entry("   \n ", 300))
        checkTrue("an entry with only spaces is not kept", log.entries.count == 3)
        log.add(entry("  padded text \n", 400))
        checkTrue("the text is trimmed", log.entries.first?.text == "padded text", log.entries.first?.text ?? "")

        // MARK: limit
        var small = DictationLog(limit: 3)
        for i in 1...5 { small.add(entry("n\(i)", Double(i))) }
        checkTrue("only the newest are kept when the limit is reached", small.entries.map(\.text) == ["n5", "n4", "n3"], "\(small.entries.map(\.text))")
        checkTrue("the default limit is 10000", DictationLog().limit == 10000)

        // MARK: what the limit removes is reported (ADR-2611072100 A6)
        var full = DictationLog(limit: 2)
        checkTrue("adding below the limit removes nothing", full.add(entry("a", 1)).isEmpty)
        _ = full.add(entry("b", 2))
        let dropped = full.add(entry("c", 3))
        checkTrue("adding past the limit returns the oldest note", dropped.map(\.text) == ["a"], "\(dropped.map(\.text))")
        checkTrue("a note older than all the rest is the one returned", full.add(entry("old", 0)).map(\.text) == ["old"])
        var blank = DictationLog(limit: 1)
        _ = blank.add(entry("kept", 1))
        checkTrue("a blank note removes nothing", blank.add(entry("  ", 2)).isEmpty && blank.entries.map(\.text) == ["kept"])
        checkTrue("no notice when nothing was removed", DictationLog.droppedNotice(count: 0, limit: 10000) == nil)
        checkTrue("one removed note is reported",
                  DictationLog.droppedNotice(count: 1, limit: 10000)
                    == "Notes keeps the newest 10,000 notes, so the oldest one was removed.",
                  DictationLog.droppedNotice(count: 1, limit: 10000) ?? "nil")
        checkTrue("several removed notes are counted",
                  DictationLog.droppedNotice(count: 3, limit: 2000)
                    == "Notes keeps the newest 2,000 notes, so the oldest 3 were removed.",
                  DictationLog.droppedNotice(count: 3, limit: 2000) ?? "nil")
        checkTrue("a small limit has no comma", DictationLog.droppedNotice(count: 1, limit: 500)
                    == "Notes keeps the newest 500 notes, so the oldest one was removed.")

        // MARK: removing
        var r = DictationLog()
        let keep = entry("keep", 10), drop = entry("drop", 20)
        r.add(keep); r.add(drop)
        r.remove(id: drop.id)
        checkTrue("remove deletes one entry", r.entries.map(\.text) == ["keep"])
        r.remove(id: "no-such-id")
        checkTrue("removing an unknown id changes nothing", r.entries.count == 1)
        r.clear()
        checkTrue("clear empties the log", r.entries.isEmpty)

        // MARK: saving and loading
        let url = tmp()
        var saved = DictationLog()
        saved.add(entry("Hello there, “quoted” café", 1000, app: "Notes", seconds: 3.5))
        saved.add(entry("no app known", 2000, app: nil, seconds: nil))
        checkTrue("save succeeds and creates the folder", saved.save(to: url))
        let loaded = DictationLog.load(from: url)
        checkTrue("a saved log loads back the same", loaded.entries == saved.entries, "\(loaded.entries)")
        checkTrue("unicode and missing fields survive", loaded.entries.contains { $0.text == "Hello there, “quoted” café" && $0.app == "Notes" }
                  && loaded.entries.contains { $0.app == nil && $0.seconds == nil })
        checkTrue("a missing file loads empty", DictationLog.load(from: tmp()).entries.isEmpty)

        // MARK: a damaged file is moved aside, never overwritten
        let bad = tmp()
        try? FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "this is not json".write(to: bad, atomically: true, encoding: .utf8)
        let fromBad = DictationLog.load(from: bad)
        checkTrue("a damaged file loads empty", fromBad.entries.isEmpty)
        let aside = URL(fileURLWithPath: bad.path + ".bad")
        checkTrue("and the damaged file is kept as .bad", (try? String(contentsOf: aside, encoding: .utf8)) == "this is not json")
        checkTrue("and the original is gone so a new log starts clean", !FileManager.default.fileExists(atPath: bad.path))

        // MARK: the file holds text only
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        checkTrue("the file is readable JSON with the words in it", text.contains("Hello there") && text.hasPrefix("[") || text.hasPrefix("{"))

        print("\(checks) checks, \(failures) failed")
        if checks < 25 { print("VACUOUS: only \(checks) checks ran, need 25"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
