// Tests for HomeAction.choices (ADR-2611072100 B1): which buttons a Home row shows.
// Run: bash EarshotApp/Tests/run.sh. Every expected list is written out by hand.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct HomeActionTests {
    static func main() {
        typealias K = HomeAction.Kind
        func kinds(_ transcript: Bool, _ state: HomeItem.State, step: HomeAction.Step? = nil, waiting: Bool = false) -> [K] {
            HomeAction.choices(hasTranscript: transcript, state: state, failedStep: step, waitingForModels: waiting).map(\.kind)
        }

        // MARK: rows that need nothing
        checkTrue("a finished recording shows no buttons", kinds(true, .done).isEmpty)
        checkTrue("a recording being transcribed shows no buttons", kinds(false, .working).isEmpty)
        checkTrue("a recording waiting for the models shows no buttons (the download card is the action)",
                  kinds(false, .done, waiting: true).isEmpty)
        checkTrue("waiting, even with an error message, shows no buttons",
                  kinds(false, .failed("Download the speech models first"), step: .transcribe, waiting: true).isEmpty)

        // MARK: never transcribed
        checkTrue("a recording with no transcript offers Transcribe", kinds(false, .done) == [.transcribe])

        // MARK: failures retry the step that failed, then offer the Trash
        checkTrue("a failed transcription offers Try Again (transcribe) and Move to Trash",
                  kinds(false, .failed("x"), step: .transcribe) == [.retry(.transcribe), .trash])
        checkTrue("failed speaker detection retries speakers",
                  kinds(true, .failed("x"), step: .speakers) == [.retry(.speakers), .trash])
        checkTrue("a failed summary retries the summary",
                  kinds(true, .failed("x"), step: .summary) == [.retry(.summary), .trash])
        checkTrue("speakers or a summary cannot be retried without a transcript, so transcribe instead",
                  kinds(false, .failed("x"), step: .summary) == [.retry(.transcribe), .trash])
        checkTrue("an error with no known step retries transcription",
                  kinds(true, .failed("x"), step: nil) == [.retry(.transcribe), .trash])

        // MARK: wording and roles
        let retry = HomeAction.choices(hasTranscript: false, state: .failed("x"), failedStep: .transcribe, waitingForModels: false)
        checkTrue("the retry button says Try Again", retry.first?.title == "Try Again", retry.first?.title ?? "")
        checkTrue("the Trash button says Move to Trash", retry.last?.title == "Move to Trash", retry.last?.title ?? "")
        checkTrue("only the Trash button is destructive", retry.map(\.destructive) == [false, true])
        checkTrue("Transcribe says Transcribe",
                  HomeAction.choices(hasTranscript: false, state: .done, failedStep: nil, waitingForModels: false).first?.title == "Transcribe")
        checkTrue("every button in a row has its own id", Set(retry.map(\.id)).count == retry.count)

        print("\(checks) checks, \(failures) failed")
        if checks < 15 { print("VACUOUS: only \(checks) checks ran, need 15"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
