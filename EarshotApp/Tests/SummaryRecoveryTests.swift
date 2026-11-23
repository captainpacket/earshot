// Tests for PartRecovery (ADR-2611230908): a part Apple's safety filter refuses is halved until only the
// refused passage is left, that passage is skipped and counted, and the rest of the summary survives.
// The model is a fake that refuses any text containing "BAD". Written before the code.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

enum Fake: Error { case refused, tooLong, undecodable, other }

func classify(_ e: Error) -> PartFailure {
    switch e as? Fake {
    case .refused: return .unsafe
    case .tooLong: return .tooLong
    case .undecodable: return .undecodable
    default: return .other
    }
}

/// The fake tokenizer: one token per word.
func count(_ text: String) async throws -> Int { text.split(whereSeparator: \.isWhitespace).count }

/// One section whose only point is the text it was given, so the test can see what reached the model.
func echo(_ text: String) -> SummaryPart {
    SummaryPart(sections: [SummarySection(heading: "Discussion", points: [text])], actions: [])
}

final class Calls: @unchecked Sendable { var texts: [String] = [] }

func words(_ n: Int, from start: Int = 0) -> String { (start..<start + n).map { "w\($0)" }.joined(separator: " ") }
func points(_ r: PartRecoveryResult) -> [String] { r.parts.flatMap { $0.sections.flatMap(\.points) } }

@main struct SummaryRecoveryTests {
    static func main() async {
        // A part with nothing flagged goes through in one call, untouched.
        do {
            let calls = Calls()
            let r = try await PartRecovery.run(words(16), generate: { calls.texts.append($0); return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("a clean part is one call", calls.texts.count == 1, "\(calls.texts.count)")
            checkTrue("a clean part skips nothing", r.skipped == 0)
            checkTrue("a clean part keeps its text", points(r) == [words(16)])
        } catch { checkTrue("a clean part does not throw", false, "\(error)") }

        // One flagged word in a 16-word part: halved 3 times to pieces of 2 words; only the piece with it is lost.
        do {
            var text = words(16).split(separator: " ").map(String.init)
            text[5] = "BAD"
            let r = try await PartRecovery.run(text.joined(separator: " "),
                                               generate: { if $0.contains("BAD") { throw Fake.refused }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            let kept = points(r).joined(separator: " ").split(separator: " ").map(String.init)
            checkTrue("one refused passage is counted once", r.skipped == 1, "\(r.skipped)")
            checkTrue("the refused word is not in the summary", !kept.contains("BAD"))
            checkTrue("only the refused piece is lost (14 of 16 words kept)", kept.count == 14, "\(kept.count): \(kept)")
            checkTrue("the kept words stay in order", kept == text.filter { $0 != "BAD" && $0 != "w4" }, "\(kept)")
            checkTrue("the depth limit is 3", PartRecovery.maxDepth == 3)
        } catch { checkTrue("a part with one refused passage does not throw", false, "\(error)") }

        // Two flagged passages far apart are two skips.
        do {
            var text = words(16).split(separator: " ").map(String.init)
            text[1] = "BAD"; text[14] = "BAD"
            let r = try await PartRecovery.run(text.joined(separator: " "),
                                               generate: { if $0.contains("BAD") { throw Fake.refused }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("two refused passages are counted twice", r.skipped == 2, "\(r.skipped)")
            checkTrue("the rest survives two refusals", points(r).joined(separator: " ").split(separator: " ").count == 12)
        } catch { checkTrue("two refused passages do not throw", false, "\(error)") }

        // A part refused at every size is skipped, not thrown: the run itself never fails on a refusal.
        do {
            let r = try await PartRecovery.run(words(16), generate: { _ in throw Fake.refused },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("an all-refused part has no points", r.parts.isEmpty)
            checkTrue("an all-refused part counts each smallest piece", r.skipped == 8, "\(r.skipped)")
        } catch { checkTrue("an all-refused part does not throw from run", false, "\(error)") }

        // The 2026-11-23 real-model run: a refused chunk far under the part budget was "halved" by the budget,
        // came back whole, and was skipped entire. Halving goes by the chunk's own size, lines first.
        do {
            let lines = ["Speaker 1: budget is 240 thousand", "Speaker 2: cut Brightline to two",
                         "Speaker 1: podcast BAD graphic detail", "Speaker 2: book Denver room today"]
            let r = try await PartRecovery.run(lines.joined(separator: "\n"),
                                               generate: { if $0.contains("BAD") { throw Fake.refused }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            let kept = points(r).joined(separator: "\n")
            checkTrue("a short refused chunk is halved, not skipped whole", r.skipped == 1, "\(r.skipped)")
            checkTrue("the lines around a refused line survive",
                      kept.contains(lines[0]) && kept.contains(lines[1]) && kept.contains(lines[3]), kept)
            checkTrue("the refused line is left out", !kept.contains("BAD"), kept)
        } catch { checkTrue("a short refused chunk does not throw", false, "\(error)") }

        // A piece that cannot be split further is at the limit: refused is skipped after one call, too long throws.
        do {
            let calls = Calls()
            let r = try await PartRecovery.run("BAD", generate: { calls.texts.append($0); throw Fake.refused },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("an unsplittable refused piece is skipped", r.skipped == 1 && r.parts.isEmpty)
            checkTrue("an unsplittable refused piece is tried once", calls.texts == ["BAD"], "\(calls.texts)")
        } catch { checkTrue("an unsplittable refused piece does not throw", false, "\(error)") }
        do {
            _ = try await PartRecovery.run("long", generate: { _ in throw Fake.tooLong }, classify: classify, count: count, minPiece: 1)
            checkTrue("an unsplittable too-long piece throws", false)
        } catch { checkTrue("an unsplittable too-long piece throws", (error as? Fake) == .tooLong, "\(error)") }

        // The second real-model run: halving a 205-word transcript down to one-line pieces made the model invent
        // 72 bullets. A refused chunk is not split into halves under minPiece tokens; it is skipped instead.
        do {
            let calls = Calls()
            let r = try await PartRecovery.run(words(16), generate: { calls.texts.append($0); throw Fake.refused },
                                               classify: classify, count: count, minPiece: 10)
            checkTrue("a refused chunk whose halves would be under the floor is skipped whole", r.skipped == 1 && r.parts.isEmpty)
            checkTrue("a chunk under the floor is not split", calls.texts == [words(16)], "\(calls.texts)")
        } catch { checkTrue("a refused chunk under the floor does not throw", false, "\(error)") }
        do {
            var text = words(40).split(separator: " ").map(String.init)
            text[3] = "BAD"
            let calls = Calls()
            let r = try await PartRecovery.run(text.joined(separator: " "),
                                               generate: { calls.texts.append($0); if $0.contains("BAD") { throw Fake.refused }; return echo($0) },
                                               classify: classify, count: count, minPiece: 10)
            let sizes = calls.texts.map { $0.split(separator: " ").count }
            checkTrue("no piece sent to the model is under the floor", sizes.allSatisfy { $0 >= 10 }, "\(sizes)")
            checkTrue("above the floor a refused chunk is still halved", r.skipped == 1 && points(r).joined(separator: " ").split(separator: " ").count == 30, "\(sizes)")
        } catch { checkTrue("a refused chunk above the floor does not throw", false, "\(error)") }
        checkTrue("the default floor is 100 tokens", PartRecovery.minPieceTokens == 100)

        // Too long: halved as before.
        do {
            let r = try await PartRecovery.run(words(16),
                                               generate: { if $0.split(separator: " ").count > 8 { throw Fake.tooLong }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("a too-long part is halved", points(r) == [words(8), words(8, from: 8)], "\(points(r))")
            checkTrue("a too-long part skips nothing", r.skipped == 0)
        } catch { checkTrue("a too-long part does not throw", false, "\(error)") }

        // Too long at every size: still thrown, as before (nothing to skip honestly).
        do {
            _ = try await PartRecovery.run(words(16), generate: { _ in throw Fake.tooLong },
                                           classify: classify, count: count, minPiece: 1)
            checkTrue("too long at every depth throws", false)
        } catch { checkTrue("too long at every depth throws", (error as? Fake) == .tooLong, "\(error)") }

        // Undecodable once: retried on the same text, not halved.
        do {
            let calls = Calls()
            let r = try await PartRecovery.run(words(16),
                                               generate: { calls.texts.append($0)
                                                   if calls.texts.count == 1 { throw Fake.undecodable }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("a decoding failure is retried on the same text", calls.texts == [words(16), words(16)], "\(calls.texts)")
            checkTrue("a retried part keeps its text", points(r) == [words(16)])
        } catch { checkTrue("a decoding failure retried does not throw", false, "\(error)") }

        // Undecodable twice: halved.
        do {
            let calls = Calls()
            let r = try await PartRecovery.run(words(16),
                                               generate: { calls.texts.append($0)
                                                   if calls.texts.count <= 2 { throw Fake.undecodable }; return echo($0) },
                                               classify: classify, count: count, minPiece: 1)
            checkTrue("a second decoding failure halves", points(r) == [words(8), words(8, from: 8)], "\(points(r))")
        } catch { checkTrue("a second decoding failure does not throw", false, "\(error)") }

        // Any other error still fails the summary.
        do {
            _ = try await PartRecovery.run(words(16), generate: { _ in throw Fake.other },
                                           classify: classify, count: count, minPiece: 1)
            checkTrue("another error throws", false)
        } catch { checkTrue("another error throws", (error as? Fake) == .other, "\(error)") }

        // Whole recording: refused everywhere is a plain failure; partly refused is fine.
        do {
            try PartRecovery.checkNotAllRefused(parts: [], skipped: 3)
            checkTrue("all refused throws", false)
        } catch {
            let m = error.localizedDescription
            checkTrue("all refused throws", error is SummaryRefused, "\(error)")
            checkTrue("the all-refused message names Apple's on-device model", m.contains("Apple") && m.contains("on-device"), m)
            checkTrue("the all-refused message is not Apple's raw text", !m.contains("likely to be unsafe"), m)
        }
        do {
            try PartRecovery.checkNotAllRefused(parts: [echo("x")], skipped: 3)
            try PartRecovery.checkNotAllRefused(parts: [echo("x")], skipped: 0)
            try PartRecovery.checkNotAllRefused(parts: [], skipped: 0)
            checkTrue("partly refused, clean or empty does not throw here", true)
        } catch { checkTrue("partly refused, clean or empty does not throw here", false, "\(error)") }

        // The note under the overview.
        let minutes = SummaryTemplate.find("minutes")
        let m = SummaryFormat.merge([echo("A point.")], template: minutes)
        let date = Date(timeIntervalSince1970: 0)
        let clean = SummaryFormat.render(title: "T", overview: "O.", merged: m, template: minutes,
                                         date: date, seconds: nil, speakers: [])
        let one = SummaryFormat.render(title: "T", overview: "O.", merged: m, template: minutes,
                                       date: date, seconds: nil, speakers: [], skipped: 1)
        let two = SummaryFormat.render(title: "T", overview: "O.", merged: m, template: minutes,
                                       date: date, seconds: nil, speakers: [], skipped: 2)
        checkTrue("no note when nothing was skipped", !clean.contains("would not summarize"), clean)
        checkTrue("a note when one passage was skipped", one.contains("1 passage ") && one.contains("would not summarize"), one)
        checkTrue("the note says how many", two.contains("2 passages"), two)
        let lines = one.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let o = lines.firstIndex(of: "O."), let n = lines.firstIndex(where: { $0.contains("would not summarize") }),
           let first = lines.firstIndex(where: { $0.hasPrefix("## ") && !$0.hasPrefix("## Overview") }) {
            checkTrue("the note sits after the overview and before the sections", o < n && n < first, one)
        } else { checkTrue("the note sits after the overview and before the sections", false, one) }
        if let note = SummaryFormat.skippedNote(1) {
            checkTrue("the rest of the render is unchanged when the note is added",
                      one.replacingOccurrences(of: note + "\n\n", with: "") == clean, one)
        } else { checkTrue("skippedNote is set for 1", false) }
        checkTrue("skippedNote is nil for 0", SummaryFormat.skippedNote(0) == nil)

        let minimum = 40
        print("\(checks) checks, \(failures) failed")
        if checks < minimum { print("VACUOUS: fewer than \(minimum) checks ran"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
