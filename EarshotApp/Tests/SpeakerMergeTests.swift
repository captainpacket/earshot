// Tests for the native speakers tool (ADR-2611141800): the merge of speaker turns and word timings,
// and the atomic transcript rewrite that replaced the Python script's write_atomic.
//
// The oracle is independent of this code: fixtures/speakers-meeting.* are the word timings, turns and
// output of the ORIGINAL Python `speakers` on a synthetic three-voice meeting (made with `say`). The
// port must turn the same turns and words into the same transcript, byte for byte.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct SpeakerMergeTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures")

        // MARK: the Python oracle
        let words = try SpeakerMerge.words(fromWhisperJSON: Data(contentsOf: fixtures.appendingPathComponent("speakers-meeting.json")))
        let turnsJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("speakers-meeting.turns.json"))) as! [String: Any]
        let turns = (turnsJSON["turns"] as! [[NSNumber]]).map {
            SpeakerTurn(start: $0[0].doubleValue, end: $0[1].doubleValue, speaker: $0[2].intValue)
        }
        let expected = try String(contentsOf: fixtures.appendingPathComponent("speakers-meeting.expected"), encoding: .utf8)
        checkTrue("oracle fixture has words and turns", words.count > 50 && turns.count == 6, "\(words.count) words, \(turns.count) turns")
        let out = SpeakerMerge.transcript(words: words, turns: SpeakerMerge.dropTinySpeakers(turns))
        checkTrue("same transcript as the Python speakers, byte for byte", out.text == expected, "got:\n\(out.text)")
        checkTrue("2 speakers, 5 turns, as Python reported", out.speakers == 2 && out.lines == 5, "\(out.speakers) \(out.lines)")

        // MARK: words from whisper tokens
        let json = """
            {"transcription":[{"tokens":[
              {"text":"[_BEG_]","offsets":{"from":0,"to":0}},
              {"text":" Hel","offsets":{"from":100,"to":200}},
              {"text":"lo","offsets":{"from":200,"to":300}},
              {"text":" world.","offsets":{"from":400,"to":900}},
              {"text":"","offsets":{"from":900,"to":900}},
              {"text":"[_TT_50]","offsets":{"from":900,"to":900}}]}]}
            """
        let w = try SpeakerMerge.words(fromWhisperJSON: Data(json.utf8))
        checkTrue("a token without a leading space joins the previous word", w.map(\.text) == ["Hello", "world."], "\(w.map(\.text))")
        checkTrue("the joined word ends where its last token ends", w.first?.start == 0.1 && w.first?.end == 0.3)
        checkTrue("special and empty tokens are skipped", w.count == 2)
        checkTrue("no transcription key gives no words", (try SpeakerMerge.words(fromWhisperJSON: Data("{}".utf8))).isEmpty)

        // MARK: tiny speakers
        let tiny = [SpeakerTurn(start: 0, end: 50, speaker: 0), SpeakerTurn(start: 50, end: 50.5, speaker: 2),
                    SpeakerTurn(start: 51, end: 100, speaker: 1)]
        let dropped = SpeakerMerge.dropTinySpeakers(tiny)
        checkTrue("a speaker with under 2% of the talk goes to the nearest real one", dropped.map(\.speaker) == [0, 0, 1], "\(dropped.map(\.speaker))")
        checkTrue("tiny-speaker merge keeps the times", dropped[1].start == 50 && dropped[1].end == 50.5)
        let allTiny = [SpeakerTurn(start: 0, end: 0, speaker: 3)]
        checkTrue("when nobody has talk time, nobody is dropped", SpeakerMerge.dropTinySpeakers(allTiny) == allTiny)
        checkTrue("tiny-speaker merge runs for -n -1 and -n 0, not for an exact count",
                  SpeakerMerge.mergesTinySpeakers(numSpeakers: -1) && SpeakerMerge.mergesTinySpeakers(numSpeakers: 0)
                  && !SpeakerMerge.mergesTinySpeakers(numSpeakers: 2))

        // MARK: speaker at a time
        let two = [SpeakerTurn(start: 0, end: 5, speaker: 7), SpeakerTurn(start: 10, end: 15, speaker: 8)]
        checkTrue("inside a turn: that speaker", SpeakerMerge.speaker(at: 12, in: two) == 8)
        checkTrue("in a gap: the nearer turn", SpeakerMerge.speaker(at: 6, in: two) == 7 && SpeakerMerge.speaker(at: 9, in: two) == 8)
        checkTrue("before everything: the first turn", SpeakerMerge.speaker(at: -3, in: two) == 7)

        // MARK: the transcript shape
        let ws = [TimedWord(text: "Hi", start: 0, end: 1), TimedWord(text: "there.", start: 1, end: 2),
                  TimedWord(text: "Hello", start: 11, end: 12), TimedWord(text: "back.", start: 12, end: 13),
                  TimedWord(text: "Again", start: 3665, end: 3666)]
        let t3 = [SpeakerTurn(start: 0, end: 5, speaker: 9), SpeakerTurn(start: 10, end: 15, speaker: 4),
                  SpeakerTurn(start: 3660, end: 3670, speaker: 9)]
        let r = SpeakerMerge.transcript(words: ws, turns: t3)
        checkTrue("speakers are numbered in the order they first talk, paragraphs split by a blank line",
                  r.text == "[00:00:00] Speaker 1: Hi there.\n\n[00:00:11] Speaker 2: Hello back.\n\n[01:01:05] Speaker 1: Again\n",
                  r.text)
        let straddle = [TimedWord(text: "One", start: 4, end: 4.5), TimedWord(text: "two", start: 9, end: 12),
                        TimedWord(text: "three.", start: 12, end: 14)]
        let r2 = SpeakerMerge.transcript(words: straddle, turns: two)
        checkTrue("a sentence goes to whoever spoke most of it, never split mid-sentence",
                  r2.text == "[00:00:04] Speaker 1: One two three.\n" && r2.speakers == 1, r2.text)
        checkTrue("stamp formats hours", SpeakerMerge.stamp(3723.9) == "01:02:03")

        // MARK: atomic rewrite (was scripts/speakers-test)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-speakers-\(getpid())")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = dir.appendingPathComponent("rec.txt")
        try "ORIGINAL\n".write(to: p, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: p.path)
        let inode = (try FileManager.default.attributesOfItem(atPath: p.path)[.systemFileNumber] as? NSNumber)?.intValue
        var seen: [String] = []
        try SpeakerMerge.writeAtomic("NEW\n", to: p) { seen.append((try? String(contentsOf: p, encoding: .utf8)) ?? "?") }
        checkTrue("old content intact until the atomic swap", seen == ["ORIGINAL\n"], "\(seen)")
        checkTrue("new content written", (try? String(contentsOf: p, encoding: .utf8)) == "NEW\n")
        let inode2 = (try FileManager.default.attributesOfItem(atPath: p.path)[.systemFileNumber] as? NSNumber)?.intValue
        checkTrue("replaced by a new inode, not truncated in place", inode != nil && inode != inode2)
        let mode = (try FileManager.default.attributesOfItem(atPath: p.path)[.posixPermissions] as? NSNumber)?.intValue
        checkTrue("file mode preserved", mode == 0o640, "\(String(mode ?? 0, radix: 8))")
        checkTrue("no temp files left behind", (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["rec.txt"])
        struct Boom: Error {}
        do { try SpeakerMerge.writeAtomic("LOST\n", to: p) { throw Boom() } } catch {}
        checkTrue("a failed write keeps the original and leaves no temp",
                  (try? String(contentsOf: p, encoding: .utf8)) == "NEW\n"
                  && (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["rec.txt"])
        let fresh = dir.appendingPathComponent("new.txt")
        try SpeakerMerge.writeAtomic("X\n", to: fresh)
        checkTrue("a new file gets mode 644", (try FileManager.default.attributesOfItem(atPath: fresh.path)[.posixPermissions] as? NSNumber)?.intValue == 0o644)

        // MARK: decoding (earshot-convert's path): a WAV written by writeWAV reads back the same
        let tone = (0..<16_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 16_000) * 0.5) }
        let wav = dir.appendingPathComponent("tone.wav")
        try AudioDecode.writeWAV(tone, to: wav)
        let size = (try FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? NSNumber)?.intValue
        checkTrue("WAV is a 44-byte header plus 2 bytes a sample", size == 44 + 32_000, "\(size ?? -1)")
        let back = try AudioDecode.samples(wav)
        let worst = zip(tone, back).map { abs($0 - $1) }.max() ?? 1
        checkTrue("decoding it gives the same 16 kHz samples (within 16-bit rounding)",
                  back.count == tone.count && worst < 0.001, "\(back.count) samples, worst error \(worst)")

        if checks < 25 { print("VACUOUS: only \(checks) checks ran"); exit(1) }
        print(failures == 0 ? "SpeakerMergeTests: all \(checks) passed" : "SpeakerMergeTests: \(failures) of \(checks) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
