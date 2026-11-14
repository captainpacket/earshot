// Tests for PrivateFiles (ADR-2611072100 A3): the notes file, its folder and the activity log are readable
// by their owner only. Run: bash EarshotApp/Tests/run.sh. Expected modes are written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func mode(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber)?.intValue ?? -1
}
func octal(_ m: Int) -> String { String(m, radix: 8) }

@main struct PrivateFilesTests {
    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("privatefiles-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // MARK: appendLine (the activity log)
        let log = root.appendingPathComponent("Earshot.log")
        PrivateFiles.appendLine("first\n", to: log)
        checkTrue("a new log is created owner-only (600)", mode(log) == 0o600, octal(mode(log)))
        PrivateFiles.appendLine("second\n", to: log)
        checkTrue("lines are appended, not replaced",
                  (try? String(contentsOf: log, encoding: .utf8)) == "first\nsecond\n")

        let old = root.appendingPathComponent("old.log")
        try? "kept\n".write(to: old, atomically: true, encoding: .utf8)
        chmod(old.path, 0o644)
        PrivateFiles.appendLine("more\n", to: old)
        checkTrue("an existing world-readable log is tightened to 600", mode(old) == 0o600, octal(mode(old)))
        checkTrue("its earlier lines are kept", (try? String(contentsOf: old, encoding: .utf8)) == "kept\nmore\n")

        // A symlink in place of the log is not followed: the line must not land in the link's target.
        let target = root.appendingPathComponent("target.txt")
        try? "target\n".write(to: target, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("link.log")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        PrivateFiles.appendLine("leak\n", to: link)
        checkTrue("a symlinked log is not written through",
                  (try? String(contentsOf: target, encoding: .utf8)) == "target\n")

        // MARK: writeAtomically (notes.json)
        let dir = root.appendingPathComponent("Earshot")
        let notes = dir.appendingPathComponent("notes.json")
        let wrote = PrivateFiles.writeAtomically(Data("[1]".utf8), to: notes)
        checkTrue("the write succeeds", wrote)
        checkTrue("the notes file is 600", mode(notes) == 0o600, octal(mode(notes)))
        checkTrue("the folder it creates is 700", mode(dir) == 0o700, octal(mode(dir)))
        _ = PrivateFiles.writeAtomically(Data("[2]".utf8), to: notes)
        checkTrue("a rewrite is still 600", mode(notes) == 0o600, octal(mode(notes)))
        checkTrue("a rewrite replaces the contents", (try? Data(contentsOf: notes)) == Data("[2]".utf8))
        let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "notes.json" }
        checkTrue("no temporary file is left beside it", leftovers.isEmpty, "\(leftovers)")

        chmod(dir.path, 0o755)
        _ = PrivateFiles.writeAtomically(Data("[3]".utf8), to: notes)
        checkTrue("an existing open folder is tightened to 700", mode(dir) == 0o700, octal(mode(dir)))

        // MARK: DictationLog uses it
        let logURL = root.appendingPathComponent("Notes2/notes.json")
        var dl = DictationLog()
        dl.add(.init(id: "a", date: Date(), text: "hello", app: nil, seconds: nil))
        checkTrue("DictationLog.save succeeds", dl.save(to: logURL))
        checkTrue("DictationLog.save writes 600", mode(logURL) == 0o600, octal(mode(logURL)))
        checkTrue("DictationLog.save makes its folder 700", mode(logURL.deletingLastPathComponent()) == 0o700)

        print(failures == 0 ? "PrivateFilesTests: all \(checks) passed" : "PrivateFilesTests: \(failures) of \(checks) FAILED")
        if checks < 15 { print("VACUOUS: only \(checks) checks ran, need 15"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
