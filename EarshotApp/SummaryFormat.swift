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
                + "Then a section named Decisions with what was agreed. Then Open questions, if any were raised.",
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

    private static func dropPlural(_ s: String) -> String { s.hasSuffix("s") ? String(s.dropLast()) : s }

    /// Two headings name the same section: equal after normalizing and dropping one trailing "s".
    static func sameHeading(_ a: String, _ b: String) -> Bool {
        dropPlural(normalize(a)) == dropPlural(normalize(b))
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
        // Group by heading, first wording wins, points in part order.
        var groups: [SummarySection] = []
        for part in parts {
            for s in part.sections where !s.heading.localizedCaseInsensitiveContains("action item") {
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
        for a in parts.flatMap(\.actions) {
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
