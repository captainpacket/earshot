// Tests for MeetingNotes (ADR-2611142100): notes typed during a meeting go before the transcript the
// summary reads. Run: bash EarshotApp/Tests/run.sh. Expected text is written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct MeetingNotesTests {
    static func main() {
        checkTrue("no notes leaves the transcript as it is",
                  MeetingNotes.compose(transcript: "Speaker 1: hi", notes: nil) == "Speaker 1: hi")
        checkTrue("blank notes leave the transcript as it is",
                  MeetingNotes.compose(transcript: "Speaker 1: hi", notes: " \n\t ") == "Speaker 1: hi")
        let both = MeetingNotes.compose(transcript: "Speaker 1: hi", notes: "  Priya owns the launch date\n")
        checkTrue("notes come first, labelled, then the transcript",
                  both == "Notes the person recording typed during the meeting:\nPriya owns the launch date\n\nTranscript:\nSpeaker 1: hi",
                  both)
        let long = String(repeating: "a", count: 2500)
        let capped = MeetingNotes.compose(transcript: "t", notes: long)
        checkTrue("notes are capped at 2,000 characters", capped.contains(String(repeating: "a", count: 2000) + "…\n"))
        checkTrue("and not one more", !capped.contains(String(repeating: "a", count: 2001)))
        checkTrue("the cap is 2000", MeetingNotes.limit == 2000)
        checkTrue("the notes file sits beside the recording",
                  MeetingNotes.url(for: URL(fileURLWithPath: "/r/2026-11-14 10.00.wav")).path == "/r/2026-11-14 10.00.notes.md")
        print("\(checks) checks, \(failures) failed")
        if checks < 7 { print("VACUOUS: only \(checks) checks ran, need 7"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
