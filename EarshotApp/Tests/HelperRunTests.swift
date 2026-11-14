// Tests for HelperRun (ADR-2611072100 A1, A2): a helper that hangs is stopped with its children, and the
// log line for a helper never carries what the helper printed. Run: bash EarshotApp/Tests/run.sh
// Expected answers are written out by hand. The helpers are /bin/sh one-liners, not the real tools.
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func sh(_ script: String) -> [String] { ["/bin/sh", "-c", script] }

func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

@main struct HelperRunTests {
    static func main() async {
        // MARK: the timeout policy
        checkTrue("a short recording gets the 15-minute floor", HelperRun.timeout(audioSeconds: 60) == 900)
        checkTrue("an hour of audio gets three hours", HelperRun.timeout(audioSeconds: 3600) == 10800)
        checkTrue("an unknown length gets six hours", HelperRun.timeout(audioSeconds: nil) == 21600)
        checkTrue("a zero length counts as unknown", HelperRun.timeout(audioSeconds: 0) == 21600)
        checkTrue("a NaN length counts as unknown", HelperRun.timeout(audioSeconds: .nan) == 21600)
        checkTrue("a dictation clip gets two minutes", HelperRun.clipTimeout == 120)

        // MARK: outcomes
        let ok = await HelperRun.run(sh("exit 0"), timeout: 10)
        checkTrue("exit 0 is ok", ok.kind == .ok, "\(ok)")
        checkTrue("ok has no message for the user", ok.userMessage == nil)

        let bad = await HelperRun.run(sh("echo one >&2; echo two >&2; echo three >&2; echo four >&2; exit 3"), timeout: 10)
        checkTrue("exit 3 is failed(3)", bad.kind == .failed(3), "\(bad)")
        checkTrue("the user sees the last three lines of error output",
                  bad.userMessage == "two\nthree\nfour", "\(String(describing: bad.userMessage))")

        let missing = await HelperRun.run(["/usr/bin/env", "earshot-no-such-helper-\(UUID().uuidString)"], timeout: 10)
        checkTrue("a helper that is not installed fails with 127", missing.kind == .failed(127), "\(missing)")

        let noExec = await HelperRun.run(["/nonexistent/\(UUID().uuidString)"], timeout: 10)
        checkTrue("a path that cannot run is couldNotStart", noExec.kind == .couldNotStart, "\(noExec)")
        checkTrue("couldNotStart still tells the user something", noExec.userMessage?.isEmpty == false)

        // A helper that writes a lot of error output and then exits must not deadlock on a full pipe.
        let loud = await HelperRun.run(sh("i=0; while [ $i -lt 4000 ]; do echo line $i >&2; i=$((i+1)); done; echo last >&2; exit 1"), timeout: 20)
        checkTrue("lots of error output does not hang the helper", loud.kind == .failed(1), "\(loud)")
        checkTrue("the tail is still the end of the output", loud.userMessage?.hasSuffix("last") == true,
                  "\(String(describing: loud.userMessage))")

        // MARK: the timeout stops the helper and its children
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("helperrun-\(UUID().uuidString).pid")
        let start = Date()
        let hung = await HelperRun.run(sh("sleep 60 & echo $! > '\(pidFile.path)'; wait"), timeout: 1)
        let took = Date().timeIntervalSince(start)
        checkTrue("a hung helper reports timedOut", hung.kind == .timedOut, "\(hung)")
        checkTrue("it returns soon after the timeout, not after the helper's 60 s", took < 8, "took \(took) s")
        checkTrue("the user is told it took too long", hung.userMessage?.contains("too long") == true,
                  "\(String(describing: hung.userMessage))")
        let childPID = Int32((try? String(contentsOf: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        checkTrue("the child's pid was recorded", childPID > 0)
        var childGone = false
        for _ in 0..<30 where !childGone { if !alive(childPID) { childGone = true } else { usleep(100_000) } }
        checkTrue("the helper's child process is stopped too", childGone, "pid \(childPID) still running")
        try? FileManager.default.removeItem(at: pidFile)

        // A helper that ignores SIGTERM is killed after the grace period.
        let stubborn = await HelperRun.run(sh("trap '' TERM; sleep 60"), timeout: 1, grace: 1)
        checkTrue("a helper that ignores SIGTERM still ends as timedOut", stubborn.kind == .timedOut, "\(stubborn)")

        // MARK: log lines never carry helper output
        let canary = "CANARY-what-was-said-\(UUID().uuidString)"
        let leaky = await HelperRun.run(sh("echo '\(canary)' >&2; exit 2"), timeout: 10)
        let line = leaky.logLine("transcribe")
        checkTrue("the log line names the helper and the exit code", line == "transcribe failed: exit 2", line)
        checkTrue("the log line does not contain the helper's output", !line.contains(canary), line)
        checkTrue("the user message does", leaky.userMessage?.contains(canary) == true)
        checkTrue("ok logs as finished", ok.logLine("speakers") == "speakers finished: ok")
        checkTrue("a timeout logs the seconds it waited", hung.logLine("transcribe") == "transcribe timed out after 1 s",
                  hung.logLine("transcribe"))
        checkTrue("couldNotStart logs without the reason", noExec.logLine("speakers") == "speakers could not start")

        print(failures == 0 ? "HelperRunTests: all \(checks) passed" : "HelperRunTests: \(failures) of \(checks) FAILED")
        if checks < 27 { print("VACUOUS: only \(checks) checks ran, need 27"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
