// Tests for SetupChecklist (ADR-2611142200): what the first-launch setup card shows.
// Run: bash EarshotApp/Tests/run.sh. Every expected state is written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct SetupChecklistTests {
    static func main() {
        func c(_ mic: SetupChecklist.Mic, enabled: Bool = false, trusted: Bool = false, skipped: Bool = false) -> SetupChecklist {
            SetupChecklist(microphone: mic, dictationEnabled: enabled, accessibilityTrusted: trusted, dictationSkipped: skipped)
        }

        // MARK: first launch
        let fresh = c(.notAsked)
        checkTrue("first launch: the microphone needs asking", fresh.microphoneStep == .needed)
        checkTrue("first launch: dictation is offered", fresh.dictationStep == .needed)
        checkTrue("first launch: the card shows", fresh.showsCard)

        // MARK: microphone
        checkTrue("an allowed microphone is done", c(.allowed).microphoneStep == .done)
        checkTrue("a refused microphone says so (Open Settings)", c(.refused).microphoneStep == .refused)

        // MARK: dictation
        checkTrue("dictation on but not yet allowed is waiting for the switch in Settings",
                  c(.allowed, enabled: true).dictationStep == .waiting)
        checkTrue("dictation on and allowed is done", c(.allowed, enabled: true, trusted: true).dictationStep == .done)
        checkTrue("allowed even with dictation off counts as done", c(.allowed, trusted: true).dictationStep == .done)
        checkTrue("Not Now sets dictation aside", c(.allowed, skipped: true).dictationStep == .skipped)
        checkTrue("turning dictation on later wins over Not Now",
                  c(.allowed, enabled: true, skipped: true).dictationStep == .waiting)

        // MARK: when the card goes away
        checkTrue("all done hides the card", !c(.allowed, enabled: true, trusted: true).showsCard)
        checkTrue("microphone done and dictation set aside hides the card", !c(.allowed, skipped: true).showsCard)
        checkTrue("waiting for Accessibility keeps the card", c(.allowed, enabled: true).showsCard)
        checkTrue("a refused microphone keeps the card", c(.refused, trusted: true).showsCard)
        checkTrue("an unasked microphone keeps the card even with dictation done", c(.notAsked, trusted: true).showsCard)

        print("\(checks) checks, \(failures) failed")
        if checks < 15 { print("VACUOUS: only \(checks) checks ran, need 15"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
