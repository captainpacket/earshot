// SummaryFormat (ADR-2611181715): the pure part of a detailed summary. Parts of a long recording are
// merged into one summary, repeats removed, sections placed in the template's order, then rendered.
// Foundation only, so the tests build it without SwiftUI or FoundationModels.
import Foundation

/// A Plaud-style summary format: which sections the model should write.
struct SummaryTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let sections: String
    /// Section headings the merge places first, in this order.
    var leading: [String] = []
    /// Section headings the merge places last, in this order.
    var trailing: [String] = []

    static let all: [SummaryTemplate] = [
        .init(id: "minutes", name: "Meeting minutes", icon: "person.3",
              sections: "One section per main topic discussed, with the topic as its heading. "
                + "Then a section named Decisions, only for what the speakers explicitly agreed. "
                + "Then Open questions, only for questions asked and not answered.",
              trailing: ["Decisions", "Open questions"]),
        .init(id: "quick", name: "Quick summary", icon: "text.alignleft",
              sections: "One section named Key points.",
              leading: ["Key points"]),
        .init(id: "sales", name: "Sales call", icon: "briefcase",
              sections: "Use these sections, and leave out any the text says nothing about: "
                + "Customer and attendees, Current situation, Pain points, Requirements, "
                + "Objections and risks, Competitors mentioned, Budget timeline and buying process, Next steps.",
              leading: ["Customer and attendees", "Current situation", "Pain points", "Requirements",
                        "Objections and risks", "Competitors mentioned", "Budget timeline and buying process",
                        "Next steps"]),
        .init(id: "oneonone", name: "One-on-one", icon: "person.2",
              sections: "Sections: Updates, Challenges, Feedback, Decisions. Leave out any with nothing in the text.",
              leading: ["Updates", "Challenges", "Feedback", "Decisions"]),
        .init(id: "standup", name: "Daily stand-up", icon: "checklist",
              sections: "One section per person, with the name as heading. Points start with "
                + "Done:, Next: or Blocked:."),
        .init(id: "interview", name: "Interview", icon: "mic",
              sections: "A section named Background. Then one section per main question or theme. "
                + "Then Notable quotes, using the speaker's own words.",
              leading: ["Background"], trailing: ["Notable quotes"]),
        .init(id: "lecture", name: "Lecture or class notes", icon: "graduationcap",
              sections: "One section per concept taught, with the concept as heading and the explanation as points. "
                + "Then Examples, then Questions to review.",
              trailing: ["Examples", "Questions to review"]),
        .init(id: "brainstorm", name: "Brainstorm", icon: "lightbulb",
              sections: "One section per group of related ideas. Then Most promising ideas, then Next steps.",
              trailing: ["Most promising ideas", "Next steps"]),
        .init(id: "memo", name: "Voice memo", icon: "waveform",
              sections: "Sections: Main points, Ideas. Put to-dos in the action items.",
              leading: ["Main points", "Ideas"]),
    ]

    static func find(_ id: String) -> SummaryTemplate { all.first { $0.id == id } ?? all[0] }
}

struct SummarySection: Equatable {
    var heading: String
    var points: [String]
}

struct SummaryAction: Equatable {
    var owner: String
    var task: String
    var due: String
}

/// What the model wrote for one part of the transcript.
struct SummaryPart {
    var sections: [SummarySection]
    var actions: [SummaryAction]
}

/// All parts merged: sections in the template's order, repeats removed.
struct MergedSummary {
    var sections: [SummarySection]
    var actions: [SummaryAction]
}

enum SummaryFormat {
    /// Lowercased, apostrophes removed, every other non-alphanumeric character a space, spaces collapsed.
    static func normalize(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch == "'" || ch == "\u{2019}" || ch == "\u{2018}" { continue }
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        return out.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    /// The due date as the model wrote it, only if it is a real date the source text says.
    /// Placeholders such as "none" or "TBD", and dates the text never mentions, become "".
    static func groundedDue(_ due: String, in source: String) -> String {
        let trimmed = due.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let n = normalize(trimmed)
        let placeholders: Set<String> = ["n a", "na", "none", "not specified", "unspecified", "tbd", "tba",
                                         "unknown", "no date", "not stated", "not mentioned"]
        if n.isEmpty || placeholders.contains(n) { return "" }
        return (" " + normalize(source) + " ").contains(" " + n + " ") ? trimmed : ""
    }

    private static func dropPlural(_ s: String) -> String { s.hasSuffix("s") ? String(s.dropLast()) : s }

    /// Two headings name the same section: equal after normalizing and dropping one trailing "s".
    static func sameHeading(_ a: String, _ b: String) -> Bool {
        dropPlural(normalize(a)) == dropPlural(normalize(b))
    }

    /// A point or task that only says nothing happened ("No decisions were made", "None mentioned").
    static func isAbsence(_ s: String) -> Bool {
        let n = normalize(s)
        let empties: Set<String> = ["none", "none mentioned", "nothing", "nothing mentioned", "not specified", "n a"]
        if n.isEmpty || empties.contains(n) { return true }
        let pattern = #"\b(no|not|never|none|without|doesnt|didnt|dont|wasnt|werent)\b( \w+){0,6} (decisions?|questions?|tasks?|action items?)\b"#
        return n.range(of: pattern, options: .regularExpression) != nil
    }

    /// A heading without a leading speaker label ("Speaker 1: Pricing" is "Pricing"); a bare label stays.
    static func unlabeled(_ heading: String) -> String {
        guard let m = heading.wholeMatch(of: #/[^:]{1,40}:\s+(.+)/#) else { return heading }
        let rest = String(m.1).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? heading : rest
    }

    /// The heading fills the slot: the same heading, or it starts with the slot name, singular or
    /// plural, then a word boundary ("Decision Points" fills Decisions, "Open questions raised" Open questions).
    static func fills(_ heading: String, slot: String) -> Bool {
        if sameHeading(heading, slot) { return true }
        let base = dropPlural(normalize(slot))
        let n = normalize(heading)
        return !base.isEmpty && (n.hasPrefix(base + " ") || n.hasPrefix(base + "s "))
    }

    /// Two points say the same thing: equal once normalized, or the shorter (at least five words, the
    /// same numbers) has at least 85% of its distinct words in the longer one.
    static func samePoint(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        if na.isEmpty || nb.isEmpty { return false }
        if na == nb { return true }
        let wa = na.split(separator: " ").map(String.init)
        let wb = nb.split(separator: " ").map(String.init)
        func numbers(_ w: [String]) -> Set<String> { Set(w.filter { $0.allSatisfy { $0.isASCII && $0.isNumber } }) }
        guard numbers(wa) == numbers(wb) else { return false }
        let (short, long) = wa.count <= wb.count ? (wa, wb) : (wb, wa)
        guard short.count >= 5 else { return false }
        let distinct = Set(short), longSet = Set(long)
        let shared = distinct.filter { longSet.contains($0) }.count
        return Double(shared) >= 0.85 * Double(distinct.count)
    }

    /// Drops blanks and repeats, keeping first-seen order; a repeat's longer wording wins the earlier slot.
    static func dedupe(_ points: [String]) -> [String] {
        var kept: [String] = []
        for p in points where !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let i = kept.firstIndex(where: { samePoint($0, p) }) {
                if p.count > kept[i].count { kept[i] = p }
            } else {
                kept.append(p)
            }
        }
        return kept
    }

    /// Merges every part's sections and action items into one summary.
    static func merge(_ parts: [SummaryPart], template: SummaryTemplate) -> MergedSummary {
        // Group by heading, first wording wins, points in part order. Absences are dropped, speaker
        // labels taken off headings, and a heading that fills a template slot takes the slot's wording.
        let slots = template.leading + template.trailing
        var groups: [SummarySection] = []
        for part in parts {
            for var s in part.sections where !s.heading.localizedCaseInsensitiveContains("action item") {
                s.points = s.points.filter { !isAbsence($0) }
                s.heading = unlabeled(s.heading)
                if let slot = slots.first(where: { fills(s.heading, slot: $0) }) { s.heading = slot }
                if let i = groups.firstIndex(where: { sameHeading($0.heading, s.heading) }) {
                    groups[i].points += s.points
                } else {
                    groups.append(s)
                }
            }
        }

        // Order: leading in template order, then the rest as they appeared, then trailing in template order.
        func slot(_ list: [String], _ heading: String) -> Int? { list.firstIndex { sameHeading($0, heading) } }
        let leading = groups.compactMap { g in slot(template.leading, g.heading).map { ($0, g) } }
            .sorted { $0.0 < $1.0 }.map(\.1)
        let trailing = groups.filter { slot(template.leading, $0.heading) == nil }
            .compactMap { g in slot(template.trailing, g.heading).map { ($0, g) } }
            .sorted { $0.0 < $1.0 }.map(\.1)
        let middle = groups.filter {
            slot(template.leading, $0.heading) == nil && slot(template.trailing, $0.heading) == nil
        }
        var ordered = leading + middle + trailing

        // Dedupe across the whole summary in the final order.
        var keptAt: [(section: Int, point: Int)] = []
        for si in ordered.indices {
            let points = ordered[si].points
            ordered[si].points = []
            for p in points where !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let k = keptAt.first(where: { samePoint(ordered[$0.section].points[$0.point], p) }) {
                    if p.count > ordered[k.section].points[k.point].count { ordered[k.section].points[k.point] = p }
                } else {
                    ordered[si].points.append(p)
                    keptAt.append((si, ordered[si].points.count - 1))
                }
            }
        }
        let sections = ordered.filter { !$0.points.isEmpty }

        // Action items: same owner and same task are one; the longer task and the first due date win.
        var actions: [SummaryAction] = []
        for a in parts.flatMap(\.actions) where !isAbsence(a.task) {
            if let i = actions.firstIndex(where: { sameHeading($0.owner, a.owner) && samePoint($0.task, a.task) }) {
                if a.task.count > actions[i].task.count { actions[i].task = a.task }
                if actions[i].due.trimmingCharacters(in: .whitespaces).isEmpty { actions[i].due = a.due }
            } else {
                actions.append(a)
            }
        }
        return MergedSummary(sections: sections, actions: actions)
    }

    /// The Markdown the Summary tab shows and the .summary.md file keeps.
    static func render(title: String, overview: String, merged: MergedSummary, template: SummaryTemplate,
                       date: Date, seconds: Double?, speakers: [String]) -> String {
        var info = [date.formatted(date: .abbreviated, time: .shortened)]
        if let seconds, seconds.isFinite { info.append("\(max(1, Int((seconds / 60).rounded()))) min") }
        if !speakers.isEmpty { info.append("Speakers: " + speakers.joined(separator: ", ")) }

        var md = "<!-- template: \(template.id) -->\n"
        md += "# \(title.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "#*\""))))\n\n"
        md += "*\(template.name) · \(info.joined(separator: " · "))*\n\n"
        md += "## Overview\n\(overview)\n\n"
        for section in merged.sections
        where !section.points.isEmpty && !section.heading.localizedCaseInsensitiveContains("action item") {
            md += "## \(section.heading)\n"
            md += section.points.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        md += "## Action items\n"
        if merged.actions.isEmpty {
            md += "- None mentioned\n"
        } else {
            for a in merged.actions {
                let due = a.due.trimmingCharacters(in: .whitespaces)
                md += "- [ ] **\(a.owner)** — \(a.task)" + (due.isEmpty ? "" : " *(due \(due))*") + "\n"
            }
        }
        return md
    }

    /// A bounded digest of the merged summary for the model to write the overview from.
    static func overviewInput(_ merged: MergedSummary, pointsPerSection: Int) -> String {
        var lines: [String] = []
        for s in merged.sections {
            lines.append("## \(s.heading)")
            lines += s.points.prefix(max(0, pointsPerSection)).map { "- \($0)" }
        }
        if !merged.actions.isEmpty {
            lines.append("## Action items")
            lines += merged.actions.prefix(8).map { "\($0.owner): \($0.task)" }
        }
        return lines.joined(separator: "\n")
    }

    /// Long turns are cut first: each line whose body is over `maxWords` words is split at sentence ends
    /// into pieces of at most `maxWords` words, each keeping the line's speaker label. Every word is kept.
    static func splitTurns(_ text: String, maxWords: Int) -> String {
        let limit = max(1, maxWords)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { line -> String in
            if line.isEmpty { return String(line) }
            var label = ""
            var body = Substring(line)
            if let m = line.prefixMatch(of: #/([^:]{1,40}): /#) {
                label = String(m.0)
                body = line[m.range.upperBound...]
            }
            let words = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if words.count <= limit { return String(line) }

            // Sentences: runs of words ending with a word that ends in . ! or ?
            var sentences: [[String]] = []
            var current: [String] = []
            for w in words {
                current.append(w)
                if let last = w.last, last == "." || last == "!" || last == "?" {
                    sentences.append(current)
                    current = []
                }
            }
            if !current.isEmpty { sentences.append(current) }

            var pieces: [[String]] = []
            var piece: [String] = []
            for s in sentences {
                if s.count > limit {
                    if !piece.isEmpty { pieces.append(piece); piece = [] }
                    var i = 0
                    while i < s.count {
                        pieces.append(Array(s[i..<min(i + limit, s.count)]))
                        i += limit
                    }
                } else if piece.count + s.count > limit {
                    pieces.append(piece)
                    piece = s
                } else {
                    piece += s
                }
            }
            if !piece.isEmpty { pieces.append(piece) }
            return pieces.map { label + $0.joined(separator: " ") }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    /// The speaker names used in a transcript, in order of first appearance ("Speaker 1", or a renamed "Gary").
    static func speakerNames(in transcript: String) -> [String] {
        var names: [String] = []
        for line in transcript.split(separator: "\n") {
            if let m = line.firstMatch(of: #/^\[\d\d:\d\d:\d\d\] ([^:]{1,40}):/#) {
                let name = String(m.1)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }
}
