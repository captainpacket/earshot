# ADR-2611072100: What the independent reviews found and we did not fix yet

**Status:** Proposed
**Date:** 2026-11-07
**Drivers:** The owner asked to finish. Three read-only reviews (design, privacy, Swift; see ADR-2611071900)
were run on the Notes, Dictation and paste-guard work. The confirmed blockers were fixed in the same
session (see Done). This records the rest, so it is not lost and not promised for "next session".

## Done in this pass (for the record)

Wrong-window paste: the guard now also covers retry, a dictation begun in Earshot, and the Return key; the
Accessibility calls have a timeout. Notes: a recording stops and is saved when you leave the page; dictation
refuses to start during a note; a failed save says so; Clear all also removes the damaged-file backup; a
hung transcription times out after 120 s; leftover temporary audio is deleted at launch. Notes are searched
by ⌘K. README, Settings and Help wording corrected where they promised more than the code does.

## Decision: do these, in this order, each as its own gated change

### A. Safety and privacy (first)

*Done 2026-11-14:* A1 (`HelperRun`: a time limit from the recording's length, 15 minutes at least,
two minutes for a clip; on timeout the helper and its child processes get SIGTERM, then SIGKILL), A2 (log
lines carry the helper's name and exit code, or an error's domain and code, never its text) and A3
(`PrivateFiles`: `Earshot.log` and `notes.json` are 600, the notes folder 700). Gated by `HelperRunTests`
and `PrivateFilesTests`.

*Done 2026-11-14:* A4 (turning Dictation off sends `.disable`: a capture is discarded, and a transcription
still running is dropped by a generation check, so nothing is typed), A5 (`meetingHoldsMicrophone` is true from
the click on Record, including the permission prompt, and gates notes and dictation), A6 (notes keep 10,000;
when the limit removes old notes the app says how many) and A7 (`DictationCleanup.firstResult` resumes at the
limit and cancels the model without awaiting it; a task group waited for the model, which a test now shows).

1. `Library.run` has no timeout and blocks a thread on a stuck helper (`Earshot.swift`, the run function).
2. Logs: `Earshot.swift` logs `\(error)` and the last stderr lines of the helpers at three places; log a
   fixed message and the exit code, keep the tail for the UI only.
3. `notes.json` and `Earshot.log` have default file permissions; set 0600.
4. Turning dictation off mid-capture still transcribes and pastes (`unregister()`); it should discard.
5. A meeting recording started while the microphone permission is being requested lets a note start
   (`startRecording` awaits before `recording` is set).
6. Notes at 2,000 are dropped silently; tell the user, or raise the limit.
7. The Tidy-up timeout (`DictationService`, `withTaskGroup`) may not fire if the model call ignores
   cancellation; verify with a test, and race with a continuation if it does not.

### B. Design (from the design review, worst first)

*Done 2026-11-14:* B1 (Home rows show Transcribe, or Try Again and Move to Trash; Try Again retries the
step that failed, tracked in `Library.failedStep`; `HomeActionTests`, scenes `home-actions` and
`home-actions-narrow`) and the delete confirmation in B8 (Notes asks before deleting one note).

*Done 2026-11-14, the rest of B:* B2 (Settings is cards, `SettingsPage.swift`), B3 (Translate is in Settings →
Transcription and kept between launches; the toolbar is gone), B4 (menu bar panel `MenuBarPanelView.swift` and
the Listening pill restyled; Tidying shows sparkles), B5 (Your notes while recording, ADR-2611142100), B6 (9-10 pt
labels raised to 12 pt, the breadcrumb slash to secondary), B7 (search results grouped under Recordings, Notes,
Settings, with the matched words highlighted) and B8 (Add Correction label, roomier correction rows). Each has a
render scene at the real width and at 380 pt.

1. Failed and untranscribed rows on Home need a visible action (Retry, Transcribe, Delete); today it is a
   context menu only.
2. Settings is still the old grouped form; give it card pages like Dictation.
3. Toolbar: the Translate toggle is the only item left; move it into the recording header or Settings.
4. Menu bar panel and the Listening pill are not restyled.
5. A Notes box to type into while recording a meeting, used by the summary.
6. Contrast and size: record bar labels, row metadata, breadcrumb, shortcut badge (about 9-10 pt grey).
7. Search results: show why a recording matched (highlight), order sections, add headers.
8. Dictation page: correction rows padding, "Add" label; Notes: delete has no confirmation.

### C. Performance
1. Search `hits` is recomputed on every ContentView pass (including each resource-monitor tick); cache it.
2. `loadSearchTexts` can overwrite a newer load; cancel the old task.
3. Notes file IO is on the main thread; move the write off it.

## Not a bug, but worth knowing

The paste guard cannot protect an app that exposes no focused window or field to Accessibility (some
Electron apps): it falls back to pasting. This is documented in the README.

## Consequences

Small, ordered, each gated. Nothing here blocks using the app today.

## References

- ADR-2611071800-never-paste-into-the-wrong-window
- ADR-2611071900-agent-and-skill-library-and-self-learning
- ADR-2611062250-notes-log-of-dictations
