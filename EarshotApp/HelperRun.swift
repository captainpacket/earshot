// Runs Earshot's helper tools (transcribe, speakers) with a time limit (ADR-2611072100 A1, A2).
// Foundation and Darwin only, so the tests can drive it with /bin/sh one-liners.
import Darwin
import Foundation

/// How a helper run ended. `tail` is the end of its error output: it is shown to the user and never logged,
/// because a helper's error output can quote what was said.
struct HelperOutcome: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case ok
        case failed(Int32)
        case timedOut
        case couldNotStart
    }

    let kind: Kind
    let tail: String
    let timeout: TimeInterval

    /// What to show in the app, or nil on success.
    var userMessage: String? {
        switch kind {
        case .ok:
            return nil
        case .failed(let code):
            return tail.isEmpty ? "It stopped with exit code \(code)." : tail
        case .timedOut:
            return "It took too long (more than \(Self.describe(timeout))) and was stopped."
        case .couldNotStart:
            return tail.isEmpty ? "It could not be started." : tail
        }
    }

    /// The line for Earshot.log: the helper's name and how it ended, never its output.
    func logLine(_ name: String) -> String {
        switch kind {
        case .ok: return "\(name) finished: ok"
        case .failed(let code): return "\(name) failed: exit \(code)"
        case .timedOut: return "\(name) timed out after \(Int(timeout)) s"
        case .couldNotStart: return "\(name) could not start"
        }
    }

    static func describe(_ seconds: TimeInterval) -> String {
        if seconds < 120 { return "\(Int(seconds)) seconds" }
        if seconds < 7200 { return "\(Int(seconds / 60)) minutes" }
        return "\(Int(seconds / 3600)) hours"
    }
}

enum HelperRun {
    /// The time limit for a job on a recording: three times its length, at least 15 minutes. Transcribing runs
    /// many times faster than real time, so only a stuck helper reaches it. Unknown length: six hours.
    static func timeout(audioSeconds: Double?) -> TimeInterval {
        guard let s = audioSeconds, s.isFinite, s > 0 else { return 6 * 3600 }
        return max(15 * 60, 3 * s)
    }

    /// The time limit for a dictation or a note clip, which is seconds of speech.
    static let clipTimeout: TimeInterval = 120

    /// Runs `args[0]` with the rest as arguments, off the calling thread. When `timeout` passes, the helper and
    /// every process it started get SIGTERM, then SIGKILL after `grace` seconds.
    static func run(_ args: [String], timeout: TimeInterval, grace: TimeInterval = 5,
                    environment: [String: String]? = nil) async -> HelperOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(args, timeout: timeout, grace: grace, environment: environment))
            }
        }
    }

    private static func runBlocking(_ args: [String], timeout: TimeInterval, grace: TimeInterval,
                                    environment: [String: String]?) -> HelperOutcome {
        guard let first = args.first else { return HelperOutcome(kind: .couldNotStart, tail: "", timeout: timeout) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: first)
        p.arguments = Array(args.dropFirst())
        if let environment { p.environment = environment }
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err

        // Read error output as it comes, so a chatty helper never blocks on a full pipe. Only the end is kept.
        let tail = TailBuffer(limit: 16 * 1024)
        let eof = DispatchSemaphore(value: 0)
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                eof.signal()
            } else {
                tail.append(data)
            }
        }
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }

        do {
            try p.run()
        } catch {
            err.fileHandleForReading.readabilityHandler = nil
            return HelperOutcome(kind: .couldNotStart, tail: error.localizedDescription, timeout: timeout)
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            signalTree(p.processIdentifier, SIGTERM)
            if exited.wait(timeout: .now() + grace) == .timedOut {
                signalTree(p.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // The last chunk may still be on its way; a child that kept the pipe open must not hang us.
        _ = eof.wait(timeout: .now() + 2)
        err.fileHandleForReading.readabilityHandler = nil

        if timedOut { return HelperOutcome(kind: .timedOut, tail: "", timeout: timeout) }
        guard p.terminationReason == .exit else {
            return HelperOutcome(kind: .failed(128 + p.terminationStatus), tail: tail.lastLines(3), timeout: timeout)
        }
        if p.terminationStatus == 0 { return HelperOutcome(kind: .ok, tail: "", timeout: timeout) }
        return HelperOutcome(kind: .failed(p.terminationStatus), tail: tail.lastLines(3), timeout: timeout)
    }

    /// Sends `sig` to `pid` and all its descendants, children first. The tree is listed before anything is
    /// signalled, because a child whose parent dies is re-parented to launchd and could no longer be found.
    static func signalTree(_ pid: pid_t, _ sig: Int32) {
        for p in descendants(of: pid).reversed() { kill(p, sig) }
        kill(pid, sig)
    }

    static func descendants(of pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var queue = [pid]
        while let next = queue.popLast() {
            let children = childPIDs(of: next)
            out.append(contentsOf: children)
            queue.append(contentsOf: children)
            if out.count > 4096 { break }
        }
        return out
    }

    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBytes { raw in
            proc_listchildpids(pid, raw.baseAddress, Int32(raw.count))
        }
        guard n > 0 else { return [] }
        return Array(buffer.prefix(Int(n))).filter { $0 > 0 }
    }
}

/// The last `limit` bytes written to it, safe to append from the pipe's reader thread.
private final class TailBuffer: @unchecked Sendable {
    private var data = Data()
    private let limit: Int
    private let lock = NSLock()

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > limit { data = Data(data.suffix(limit)) }
    }

    func lastLines(_ n: Int) -> String {
        lock.lock(); defer { lock.unlock() }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return lines.suffix(n).joined(separator: "\n")
    }
}
