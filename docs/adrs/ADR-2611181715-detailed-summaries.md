# ADR-2611181715: Summaries keep the detail of every part of a long recording

**Status:** Accepted
**Date:** 2026-11-18
**Amends:** the summary-chunking work of 2026-11-02 (`Summarizer.reduce`, `TokenChunker`)
**Drivers:** The owner called the summary of a 56-minute meeting (`2026-11-18_120610`, 8,373 words,
about 11,000 tokens) "shit, we need more detail". It had about 15 vague points. One section repeated
"Exonius needs to rethink the way they apply their solutions to today's problems" five times, and the
action items repeated it three more times. Points said "the speaker" instead of naming who said it, and
every action item was given to Speaker 1.

The causes are in the code, not in the model alone:

1. **One call writes the whole summary.** `GeneratedSummary` allows at most 6 sections of 6 points,
   within `summaryReserve` (1,200 tokens). A transcript longer than one context is boiled into notes
   ("3 to 8 short bullet points" per chunk), sometimes for several rounds, and the notes are boiled
   again into those 36 slots. Detail falls as the recording gets longer.
2. **Nothing removes repeats.** When a small model runs out of material it loops, and `render` writes
   whatever comes back.
3. **The prompts never ask for names or specifics**, so the model writes "the speaker".

## Decision

1. **Each part of the transcript writes its own sections.** The transcript is split by `TokenChunker`
   into parts that fit one call (about 1,500 words, roughly ten minutes of speech). Each part is given
   to the model with the template's instructions and returns a `GeneratedPart`: up to 5 sections of up
   to 8 points, plus its action items. These parts *are* the summary's body. They are merged, not
   summarized again, so a longer recording gets more points, not fewer.
   **Long turns are cut first** (`SummaryFormat.splitTurns`). The diarized transcript of that meeting
   has 13 lines, and one of them is a single 26,915-character turn. Splitting a turn that long happens
   mid-sentence and drops the speaker label from every piece after the first. So before chunking, a turn
   over 120 words is cut at sentence ends (or at word boundaries if it has none) into lines of at most
   120 words, and each line keeps its `Speaker N:` label.
2. **One last, small call writes only the title and overview**, from the merged headings and points.
   If those are too long for one call, it gets the first points of each section, as many as fit.
3. **Merging is a pure function** (`SummaryFormat.swift`, Foundation only):
   - Sections with the same heading merge, ignoring case, punctuation and a trailing "s"
     ("Decision" and "decisions" are one section).
   - Order: the template's *leading* headings first, in the template's order (Sales call: Customer and
     attendees, Current situation, …). Then topic headings, in order of first appearance. Then the
     template's *trailing* headings (Minutes: Decisions, Open questions). Decisions from part 1 stay at
     the end, not between the topics of parts 1 and 2.
   - **Repeats are removed across the whole summary.** Two points are the same if they match after
     normalizing, or if at least 85% of the shorter one's words are in the longer one, the shorter one has
     at least 5 words, and both have the same numbers. The longer wording is kept, in the first one's
     place. "15-node cluster" and "5-node cluster" are kept apart because their numbers differ.
   - Action items are deduplicated by owner and task in the same way.
   - Sections left empty are dropped. A section the model calls "Action items" is dropped, because the
     app writes that section itself.
4. **The prompts ask for specifics.** Each point is one full sentence with the names, numbers, products,
   dates and reasons said, and it names who said it with the speaker label at the start of the line
   ("Speaker 2 said…"), never "the speaker". Owners of action items come from the same labels.
5. **The file format does not change:** first line `<!-- template: id -->`, then `# Title`, the italic
   info line, `## Overview`, the sections, and `## Action items`. Old summaries still open, and editing,
   renaming speakers and choosing a template work as before.
6. **The model code moves to `Summarizer.swift`** (FoundationModels and Foundation, no SwiftUI), so a
   command-line check (`scripts/summarize-file`) can run the real on-device model on a real transcript.
   It stays on-device: `SystemLanguageModel`, never Private Cloud Compute.

7. **Second round, from the first real run.** `scripts/summarize-file` on `2026-11-18_120610` gave 29
   sections and 178 points, up from about 15, with the specifics the old summary dropped (Bank of
   America's 15-node cluster, $50 against $600 a license, Sunil and the IBM co-sell, the ServiceNow
   ticketing gap). It also showed four new faults, fixed as follows:
   - **Due dates the speakers never said** ("Next quarter", "Immediately") and placeholders ("N/A",
     "None", "Not specified"). `SummaryFormat.groundedDue(_:in:)` keeps a due date only if its words
     appear, as whole words, in the part of the transcript the item came from. Placeholders are always
     dropped.
   - **Decisions and Open questions invented for every part**, because the template names them. The
     part instructions say to write a section the template names only if this part has something for
     it. Decisions are only what the speakers explicitly agreed. Open questions are only questions
     asked and not answered. Action items are only tasks a speaker committed to or asked someone to do,
     at most 4 per part.
   - **A title and overview about the first two minutes** ("Evan's Work"). The header instructions say
     that the sections cover the whole recording in order, and that the title and overview are about
     all of it. The header gets 2, then 1, then 0 points per section.
   - **An intermittent "Failed to deserialize a Generable type"** from one part, which failed the whole
     summary. A part that fails to decode is tried once more, then as two halves. The header falls back
     to a plain title rather than fail.
   - **Points that only say nothing happened** ("Speaker 1 does not explicitly make any decisions"), speaker labels in headings, and "Decision Points" beside Decisions. merge drops absences (SummaryFormat.isAbsence), takes labels off headings, and lets a heading that starts with a slot name fill that slot.

## Consequences

- A 56-minute meeting gets about 6 parts, which means up to 30 sections of 240 points before merging. A
  summary for a long recording is longer, which is what was asked for.
- A summary takes one model call per part plus one more, instead of a notes round plus a final call.
  For long recordings that is about the same number of calls. A recording that fits one part takes
  two calls instead of one.
- A part ends at a size limit, not a topic boundary. A topic that spans two parts is merged only if
  both parts give it the same heading. Otherwise it shows as two neighbouring sections.
- Repeat removal can merge two genuinely different points that share most of their words and have no
  numbers. That costs less than the eight repeats it removes.

## Gate

`cd EarshotApp && bash Tests/run.sh`, which now runs `Tests/SummaryFormatTests.swift` (written before
the code, at least 40 checks, fails itself if fewer ran). The command-line check against the real model
is `scripts/summarize-file ~/Recordings/whisper/2026-11-18_120610.txt`. It needs Apple Intelligence,
so it is a manual check, not part of the gate.
