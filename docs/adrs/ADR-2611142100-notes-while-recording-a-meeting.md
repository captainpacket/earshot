# ADR-2611142100: Type notes while a meeting records, and the summary uses them

**Status:** Accepted
**Date:** 2026-11-14
**Drivers:** ADR-2611072100 B5. People write down decisions and names during a meeting. The summary only
had the transcript, so a note like "Priya owns the launch date" never reached it.

## Decision

1. **The recording screen has a "Your notes" box.** What you type there belongs to the meeting being
   recorded. It is part of Recordings, not of the Notes page (the three functions share no data).
2. **When the recording stops, the notes are saved beside it** as `<recording>.notes.md`, mode 600. An
   empty box saves nothing. Move to Trash takes the notes file with the recording.
3. **The summary reads them.** `MeetingNotes.compose` puts the notes before the transcript, labelled as
   the recorder's own notes, capped at 2,000 characters so they cannot crowd out the transcript.
4. **Nothing new leaves the Mac.** The notes go to Apple's on-device model with the transcript, as the
   transcript already does.

## Consequences

- A fourth text file can sit beside a recording. The MCP server lists only transcripts and summaries,
  so it does not expose the notes.
- Notes typed during a recording that fails to save are lost with it.

## Gate

`MeetingNotesTests` pass in `Tests/run.sh`, the `recording-notes` scenes render, and `Earshot.swift` saves
the notes with `PrivateFiles.writeAtomically` and passes them to the summarizer.
