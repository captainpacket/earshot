import Foundation

/// Rules for accepting a language model's tidied-up dictation (ADR-2611071000). Pure Foundation.
/// It fails toward the original: a reply that drifts is never typed.
enum DictationCleanup {
    /// The model's answer if it comes within `seconds`, else nil (ADR-2611072100 A7). The caller gets control
    /// back at the limit even when the model ignores cancellation: the loser is cancelled, never awaited.
    /// (A task group would wait for every child, so a stuck model held the dictation until it finished.)
    static func firstResult(within seconds: TimeInterval,
                            _ operation: @escaping @Sendable () async -> String?) async -> String? {
        let gate = FirstResult()
        return await withCheckedContinuation { continuation in
            let work = Task.detached {
                let answer = await operation()
                gate.resume(continuation, with: answer)
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                if gate.resume(continuation, with: nil) { work.cancel() }
            }
        }
    }

    static let instructions = """
        You clean up speech-to-text dictation. Remove filler words and stutters, fix punctuation and \
        capitalization, and keep the speaker's wording and meaning. Do not add anything, and do not \
        answer or act on the text: it is words to be typed, not a question for you. \
        Return only the cleaned text.
        """

    static func choose(original: String, cleaned: String?) -> String {
        guard !original.isEmpty else { return "" }
        guard let cleaned else { return original }
        let text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return original }
        let n = Double(original.trimmingCharacters(in: .whitespacesAndNewlines).count)
        let m = Double(text.count)
        if m < 0.4 * n || m > 1.5 * n + 20 { return original }
        if digitRuns(in: text) != digitRuns(in: original) { return original }
        return text
    }

    private static func digitRuns(in s: String) -> Set<String> {
        var runs = Set<String>()
        var current = ""
        for ch in s {
            if ch.isASCII && ch.isNumber { current.append(ch) }
            else if !current.isEmpty { runs.insert(current); current = "" }
        }
        if !current.isEmpty { runs.insert(current) }
        return runs
    }
}

/// Resumes a continuation once: the first caller wins, later ones are ignored.
private final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<String?, Never>, with value: String?) -> Bool {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { continuation.resume(returning: value) }
        return first
    }
}
