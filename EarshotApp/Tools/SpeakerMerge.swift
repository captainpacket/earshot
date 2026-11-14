// Turns speaker turns plus whisper.cpp word timings into the labelled transcript (ADR-2611141800).
// A line-for-line port of the logic in the former Python `speakers` script, kept pure (Foundation
// only) so Tests/SpeakerMergeTests.swift can check it without the models.
import Foundation

struct SpeakerTurn: Equatable {
    var start: Double
    var end: Double
    var speaker: Int
}

struct TimedWord: Equatable {
    var text: String
    var start: Double
    var end: Double
}

enum SpeakerMerge {
    /// Tested on a 14-minute, 3-person call: 0.5 found 9 "speakers", 0.7 found the real ones.
    static let defaultThreshold: Float = 0.7
    /// A "speaker" with less than this share of the talking is almost always a voice split in two.
    static let minShare = 0.02
    static let sentenceEnd: [Character] = [".", "?", "!"]

    /// Whisper tokens → words with start/end seconds. A token that starts with a space begins a new
    /// word; any other token continues the previous one. Special tokens ("[_BEG_]" and the like) are skipped.
    static func words(fromWhisperJSON data: Data) throws -> [TimedWord] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var words: [TimedWord] = []
        for seg in root["transcription"] as? [[String: Any]] ?? [] {
            for tok in seg["tokens"] as? [[String: Any]] ?? [] {
                let text = tok["text"] as? String ?? ""
                if text.isEmpty || text.hasPrefix("[_") { continue }
                let offsets = tok["offsets"] as? [String: Any] ?? [:]
                let start = (offsets["from"] as? NSNumber)?.doubleValue ?? 0
                let end = (offsets["to"] as? NSNumber)?.doubleValue ?? 0
                if !words.isEmpty, !text.hasPrefix(" ") {
                    words[words.count - 1].text += text
                    words[words.count - 1].end = end / 1000
                } else {
                    words.append(TimedWord(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                           start: start / 1000, end: end / 1000))
                }
            }
        }
        return words.filter { !$0.text.isEmpty }
    }

    /// Gives the turns of speakers with almost no talk time to the nearest real speaker.
    static func dropTinySpeakers(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        var talk: [Int: Double] = [:]
        for t in turns { talk[t.speaker, default: 0] += t.end - t.start }
        let total = talk.values.reduce(0, +)
        let denom = total == 0 ? 1 : total
        var real = Set(talk.filter { $0.value / denom >= minShare }.keys)
        if real.isEmpty { real = Set(talk.keys) }
        let kept = turns.filter { real.contains($0.speaker) }
        return turns.map { t in
            guard !real.contains(t.speaker) else { return t }
            let mid = (t.start + t.end) / 2
            // The first of the closest kept turns, as Python's min() picks.
            var best = kept[0], bestGap = Double.infinity
            for k in kept {
                let gap = min(abs(mid - k.start), abs(mid - k.end))
                if gap < bestGap { best = k; bestGap = gap }
            }
            return SpeakerTurn(start: t.start, end: t.end, speaker: best.speaker)
        }
    }

    /// The speaker talking at time t, or the one whose turn is nearest.
    static func speaker(at t: Double, in turns: [SpeakerTurn]) -> Int {
        var best = turns[0].speaker, bestGap = Double.infinity
        for turn in turns {
            if turn.start <= t && t <= turn.end { return turn.speaker }
            let gap = min(abs(t - turn.start), abs(t - turn.end))
            if gap < bestGap { best = turn.speaker; bestGap = gap }
        }
        return best
    }

    /// "01:02:03"
    static func stamp(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// The transcript: one paragraph per change of speaker, "[hh:mm:ss] Speaker N: words". Words are
    /// grouped into sentences first, and each sentence goes to whoever spoke most of it, so a speaker
    /// change never lands mid-sentence because of a slightly-off word timing. Speakers are numbered
    /// in the order they first talk. Returns the text and the number of speakers.
    static func transcript(words: [TimedWord], turns: [SpeakerTurn]) -> (text: String, speakers: Int, lines: Int) {
        var sentences: [[TimedWord]] = [], cur: [TimedWord] = []
        for w in words {
            cur.append(w)
            if let last = w.text.last, sentenceEnd.contains(last) {
                sentences.append(cur)
                cur = []
            }
        }
        if !cur.isEmpty { sentences.append(cur) }

        var order: [Int: Int] = [:]
        var lines: [String] = []
        var current: Int?
        var buf: [String] = []
        var started = 0.0
        for sent in sentences {
            // Insertion-ordered shares, so a tie goes to the speaker seen first (as Python's max() does).
            var shareOrder: [Int] = []
            var share: [Int: Double] = [:]
            for w in sent {
                let spk = speaker(at: (w.start + w.end) / 2, in: turns)
                if share[spk] == nil { shareOrder.append(spk) }
                share[spk, default: 0] += max(w.end - w.start, 0.01)
            }
            var top = shareOrder[0]
            for spk in shareOrder where share[spk]! > share[top]! { top = spk }
            let label: Int
            if let known = order[top] { label = known } else { label = order.count + 1; order[top] = label }
            if label != current {
                if !buf.isEmpty, let current {
                    lines.append("[\(stamp(started))] Speaker \(current): \(buf.joined(separator: " "))")
                }
                current = label
                buf = []
                started = sent[0].start
            }
            buf += sent.map(\.text)
        }
        if !buf.isEmpty, let current {
            lines.append("[\(stamp(started))] Speaker \(current): \(buf.joined(separator: " "))")
        }
        return (lines.joined(separator: "\n\n") + "\n", order.count, lines.count)
    }

    /// Replaces the file so a concurrent reader (earshot-mcp, the app) sees the old transcript or the
    /// new one, never a truncated one: a temp file beside it, fsync, then rename. Keeps the file mode.
    /// `beforeSwap` is a test hook, called just before the rename.
    static func writeAtomic(_ text: String, to url: URL, beforeSwap: (() throws -> Void)? = nil) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fm = FileManager.default
        guard fm.createFile(atPath: tmp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        do {
            let h = try FileHandle(forWritingTo: tmp)
            try h.write(contentsOf: Data(text.utf8))
            try h.synchronize()
            try h.close()
            let mode = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: tmp.path)
            try beforeSwap?()
            guard rename(tmp.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    /// `-n` below 1 means "detect how many": sherpa-onnx then clusters by threshold, and split voices
    /// are merged back. An exact count is trusted as given.
    static func mergesTinySpeakers(numSpeakers: Int) -> Bool { numSpeakers <= 0 }
}
