// Tests for SummaryFormat (ADR-2611181715): parts of a long recording merge into one detailed summary,
// with repeats removed and sections in the template's order. Written before the code.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

func sec(_ heading: String, _ points: [String]) -> SummarySection { SummarySection(heading: heading, points: points) }
func act(_ owner: String, _ task: String, _ due: String = "") -> SummaryAction { SummaryAction(owner: owner, task: task, due: due) }
func part(_ sections: [SummarySection], _ actions: [SummaryAction] = []) -> SummaryPart {
    SummaryPart(sections: sections, actions: actions)
}
func headings(_ m: MergedSummary) -> [String] { m.sections.map(\.heading) }
func bullets(_ md: String) -> Int { md.split(separator: "\n").filter { $0.hasPrefix("- ") }.count }

@main struct SummaryFormatTests {
    static func main() {
        let minutes = SummaryTemplate.find("minutes")
        let sales = SummaryTemplate.find("sales")
        let interview = SummaryTemplate.find("interview")

        // The repeats from the 2026-11-18_120610 summary the owner rejected.
        let loop = "Exonius needs to rethink the way they apply their solutions to today's problems."
        let shorter = "Exonius needs to rethink how to apply their solutions."

        // samePoint
        checkTrue("identical points are the same", SummaryFormat.samePoint(loop, loop))
        checkTrue("case and punctuation do not matter",
                  SummaryFormat.samePoint("The bank uses Skybox.", "the bank uses skybox"))
        checkTrue("a shorter wording inside a longer one is the same", SummaryFormat.samePoint(shorter, loop))
        checkTrue("the same, in either order", SummaryFormat.samePoint(loop, shorter))
        checkTrue("different numbers are different points",
                  !SummaryFormat.samePoint("Speaker 2 proposed a single 15-node cluster for the bank.",
                                           "Speaker 2 proposed a single 5-node cluster for the bank."))
        checkTrue("distinct points are different",
                  !SummaryFormat.samePoint("The bank's Skybox deployment missed its SLA.",
                                           "Speaker 1 wants to hire an FTE to drive the platform."))
        checkTrue("short points need an exact match, not overlap",
                  !SummaryFormat.samePoint("Budget is approved.", "Budget is not approved yet."))
        checkTrue("an empty point equals nothing real", !SummaryFormat.samePoint("", loop))

        // dedupe
        let looped = SummaryFormat.dedupe([shorter, loop, loop, loop, loop, loop])
        checkTrue("six looped points become one", looped.count == 1, "\(looped)")
        checkTrue("the longer wording is kept", looped.first == loop, "\(looped)")
        let kept = SummaryFormat.dedupe(["A 15-node cluster.", "Skybox missed the SLA.", "A 15-node cluster."])
        checkTrue("first-seen order is kept", kept == ["A 15-node cluster.", "Skybox missed the SLA."], "\(kept)")
        checkTrue("blank points are dropped", SummaryFormat.dedupe(["  ", "", "Real point here."]) == ["Real point here."])

        // sameHeading
        checkTrue("headings ignore case", SummaryFormat.sameHeading("Open Questions", "open questions"))
        checkTrue("headings ignore a trailing s", SummaryFormat.sameHeading("Decision", "Decisions"))
        checkTrue("headings ignore punctuation", SummaryFormat.sameHeading("Pain points:", "Pain points"))
        checkTrue("different headings differ", !SummaryFormat.sameHeading("Integration", "Deployment"))

        // merge: same heading across parts
        let m1 = SummaryFormat.merge([
            part([sec("Integration", ["Axonius will build glue to use the bank's data."])]),
            part([sec("integration", ["The bank needs switch and port data from Axonius."])]),
        ], template: minutes)
        checkTrue("same heading in two parts merges", m1.sections.count == 1, "\(headings(m1))")
        checkTrue("merged points keep part order", m1.sections.first?.points.count == 2
                  && m1.sections.first?.points.first?.hasPrefix("Axonius will") == true)
        checkTrue("the first heading's wording is kept", m1.sections.first?.heading == "Integration")

        // merge: trailing headings go last even if an early part had them
        let m2 = SummaryFormat.merge([
            part([sec("Pricing", ["The bank asked for a three-year price."]),
                  sec("Decisions", ["Use one 15-node cluster."])]),
            part([sec("Deployment", ["Rollout starts in January."]),
                  sec("Open questions", ["Who owns the integration?"]),
                  sec("Decision", ["Hire an FTE to drive the platform."])]),
        ], template: minutes)
        checkTrue("minutes: topics first, then Decisions, then Open questions",
                  headings(m2) == ["Pricing", "Deployment", "Decisions", "Open questions"], "\(headings(m2))")
        checkTrue("Decisions from both parts are together",
                  m2.sections.first { $0.heading == "Decisions" }?.points.count == 2)

        // merge: leading headings in the template's order
        let m3 = SummaryFormat.merge([
            part([sec("Next steps", ["Send the proposal by Friday."]),
                  sec("Pain points", ["Skybox missed the SLA twice this year."])]),
            part([sec("Customer and attendees", ["The bank's network team, two engineers."])]),
        ], template: sales)
        checkTrue("sales: sections follow the template's order",
                  headings(m3) == ["Customer and attendees", "Pain points", "Next steps"], "\(headings(m3))")
        let m4 = SummaryFormat.merge([
            part([sec("Notable quotes", ["\"We are not a services company.\""]),
                  sec("Career path", ["Speaker 2 moved from ops to sales engineering in 2021."])]),
            part([sec("Background", ["Speaker 2 has ten years in network security."])]),
        ], template: interview)
        checkTrue("interview: Background first, topics, Notable quotes last",
                  headings(m4) == ["Background", "Career path", "Notable quotes"], "\(headings(m4))")

        // merge: repeats across the whole summary, empty sections, model's own action-items section
        let m5 = SummaryFormat.merge([
            part([sec("Strategy", [shorter])]),
            part([sec("Reevaluating solutions", [loop, loop, loop, loop, loop]),
                  sec("Empty", []),
                  sec("Action items", ["Speaker 1 to call the bank."])]),
        ], template: minutes)
        checkTrue("a point already in an earlier section is not repeated later",
                  m5.sections.flatMap(\.points).count == 1, "\(m5.sections)")
        checkTrue("a section left empty by dedupe is dropped",
                  !headings(m5).contains("Reevaluating solutions"), "\(headings(m5))")
        checkTrue("an empty section is dropped", !headings(m5).contains("Empty"))
        checkTrue("the model's own Action items section is dropped", !headings(m5).contains("Action items"))
        checkTrue("the earlier point takes the longer wording", m5.sections.first?.points == [loop])

        // merge: action items
        let m6 = SummaryFormat.merge([
            part([], [act("Speaker 1", "Rethink how to apply the solutions to today's problems"),
                      act("Speaker 1", "Rethink how to apply the solutions to today's problems"),
                      act("Speaker 2", "Send the bank a 15-node cluster quote", "Friday")]),
            part([], [act("Speaker 1", "Rethink how to apply the solutions to today's problems."),
                      act("Speaker 2", "Find a way to OEM into Axonius")]),
        ], template: minutes)
        checkTrue("repeated action items become one", m6.actions.count == 3, "\(m6.actions)")
        checkTrue("action items keep part order", m6.actions.map(\.owner) == ["Speaker 1", "Speaker 2", "Speaker 2"])
        checkTrue("a due date survives the merge", m6.actions[1].due == "Friday")
        let m7 = SummaryFormat.merge([part([], [act("Speaker 1", "Send the quote to the bank"),
                                                act("Speaker 2", "Send the quote to the bank")])], template: minutes)
        checkTrue("the same task for two owners is kept twice", m7.actions.count == 2)

        // render: format unchanged
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let md = SummaryFormat.render(title: "## \"Bank cluster sizing\"", overview: "Two speakers sized a cluster.",
                                      merged: m2, template: minutes, date: date, seconds: 56 * 60 + 10,
                                      speakers: ["Speaker 1", "Speaker 2"])
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        checkTrue("first line names the template", lines.first == "<!-- template: minutes -->", lines.first ?? "")
        checkTrue("title line, stripped of # and quotes", lines.count > 1 && lines[1] == "# Bank cluster sizing", lines[1])
        checkTrue("info line has the template, length and speakers",
                  md.contains("*Meeting minutes · ") && md.contains(" · 56 min · Speakers: Speaker 1, Speaker 2*"))
        checkTrue("overview section", md.contains("## Overview\nTwo speakers sized a cluster.\n"))
        checkTrue("sections in merged order",
                  (md.range(of: "## Pricing")?.lowerBound ?? md.endIndex) < (md.range(of: "## Decisions")?.lowerBound ?? md.startIndex))
        checkTrue("points are bullets", md.contains("- Use one 15-node cluster.\n"))
        checkTrue("no action items: says so", md.hasSuffix("## Action items\n- None mentioned\n"), String(md.suffix(60)))
        let md2 = SummaryFormat.render(title: "T", overview: "O", merged: m6, template: minutes, date: date,
                                       seconds: nil, speakers: [])
        checkTrue("action items are checkboxes with owner and due",
                  md2.contains("- [ ] **Speaker 2** — Send the bank a 15-node cluster quote *(due Friday)*\n"))
        checkTrue("no length or speakers when unknown", !md2.contains(" min ·") && !md2.contains(" min*") && !md2.contains("Speakers:"))
        checkTrue("exactly one Action items heading", md2.components(separatedBy: "## Action items").count == 2)

        // detail scales with length: nothing caps the body
        let many = (1...6).map { p in
            part((1...3).map { s in sec("Topic \(p)-\(s)", (1...5).map { "In part \(p), topic \(s), Speaker \(p % 2 + 1) gave figure \(p * 100 + s * 10 + $0)." }) })
        }
        let big = SummaryFormat.render(title: "T", overview: "O", merged: SummaryFormat.merge(many, template: minutes),
                                       template: minutes, date: date, seconds: 3600, speakers: [])
        checkTrue("6 parts x 3 sections x 5 points keeps all 90 points", bullets(big) == 91, "\(bullets(big)) bullets")

        // overview input: bounded by points per section
        let ov = SummaryFormat.overviewInput(SummaryFormat.merge(many, template: minutes), pointsPerSection: 2)
        checkTrue("overview input has every heading", ov.contains("Topic 1-1") && ov.contains("Topic 6-3"))
        checkTrue("overview input keeps only the first points of each section",
                  ov.contains("figure 111") && ov.contains("figure 112") && !ov.contains("figure 113"))

        // speaker names
        let t = "[00:00:01] Speaker 1: hi\n[00:00:04] Gary: hello\nno label\n[00:00:09] Speaker 1: again\n"
        checkTrue("speakers in order of first appearance", SummaryFormat.speakerNames(in: t) == ["Speaker 1", "Gary"])
        checkTrue("no speakers in plain text", SummaryFormat.speakerNames(in: "plain words").isEmpty)

        // templates
        checkTrue("every template has a non-empty name and sections",
                  SummaryTemplate.all.allSatisfy { !$0.name.isEmpty && !$0.sections.isEmpty })
        checkTrue("minutes trails with Decisions and Open questions", minutes.trailing == ["Decisions", "Open questions"])
        checkTrue("an unknown id falls back to the first template", SummaryTemplate.find("nope").id == SummaryTemplate.all[0].id)

        // splitTurns: a long turn is cut at sentence ends and every piece keeps the speaker label
        let sentence = "We sized the bank cluster at fifteen nodes for the next year. "
        let longTurn = "Speaker 1: " + String(repeating: sentence, count: 30)   // 12 words x 30 = 360 words
        let split = SummaryFormat.splitTurns(longTurn + "\nSpeaker 2: Short reply.", maxWords: 80)
        let pieces = split.split(separator: "\n").map(String.init)
        checkTrue("a 360-word turn becomes several lines", pieces.count >= 5, "\(pieces.count) lines")
        checkTrue("every piece of the long turn keeps its label",
                  pieces.dropLast().allSatisfy { $0.hasPrefix("Speaker 1: ") }, pieces.first ?? "")
        checkTrue("pieces end at sentence ends", pieces.dropLast().allSatisfy { $0.hasSuffix(".") })
        checkTrue("no piece is over the limit",
                  pieces.allSatisfy { $0.split(separator: " ").count <= 80 + 2 }, "\(pieces.map { $0.split(separator: " ").count })")
        checkTrue("a short turn is left as it is", pieces.last == "Speaker 2: Short reply.")
        func words(_ s: String) -> [Substring] {
            s.split(separator: "\n").flatMap { line -> [Substring] in
                var l = Substring(line); if l.hasPrefix("Speaker 1: ") { l = l.dropFirst(11) }
                return l.split(separator: " ")
            }
        }
        checkTrue("every word is kept, in order", words(split) == words(longTurn + "\nSpeaker 2: Short reply."))
        let runOn = "Speaker 2: " + (1...200).map { "w\($0)" }.joined(separator: " ")
        let runPieces = SummaryFormat.splitTurns(runOn, maxWords: 50).split(separator: "\n")
        checkTrue("a turn with no sentence ends is still cut, by words",
                  runPieces.count == 4 && runPieces.allSatisfy { $0.hasPrefix("Speaker 2: ") }, "\(runPieces.count)")
        let plain = String(repeating: "No label here at all. ", count: 40)
        let plainPieces = SummaryFormat.splitTurns(plain, maxWords: 50).split(separator: "\n")
        checkTrue("an unlabelled long line is cut without inventing a label",
                  plainPieces.count >= 3 && plainPieces.allSatisfy { $0.hasPrefix("No label") })

        print("\(checks) checks, \(failures) failed")
        if checks < 48 { print("VACUOUS: only \(checks) checks ran, need 48"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
