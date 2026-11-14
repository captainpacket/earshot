# ADR-2611141630: Download the models from inside the app

**Status:** Accepted
**Date:** 2026-11-14
**Drivers:** Step 2 of INSTALL.md was a block of `mkdir`/`curl`/`tar` commands that had to be pasted
into Terminal before Earshot could do anything. If any file was missing, the first recording failed
with `Model not found: …`. Most of the friction in installing Earshot came from this step.

## Decision

1. **`ModelCatalog.swift` lists the five model files**, with each file's URL, size, SHA-256 and group:
   `speech` (turbo + Silero VAD), `speakers` (WeSpeaker + pyannote segmentation, a .tar.bz2) and
   `translate` (large-v3 q5_0). Hugging Face URLs are pinned to a commit. The hashes were
   cross-checked against Hugging Face's `X-Linked-ETag`.
2. **A plain file counts as installed only at exactly its expected size**, so a download that was cut
   off is not mistaken for the model. An unpacked archive member counts when it is not empty. The
   paths are the ones the scripts already read (`~/Models/whisper`, `~/Models/speakers`), so setups
   made with the old curl steps are recognized and nothing downloads again.
3. **The app offers the required groups (speech + speakers, 1.7 GB) on a card** at the top of
   Recordings and Settings. The card shows progress, can be cancelled, and shows any error with a
   Try Again button. Translate is offered separately (1.1 GB) the first time Translate is turned on.
4. **Downloads never leave a bad file where the scripts read.** Each file goes to
   `~/Models/.earshot-download`, is checked against its SHA-256, and only then moves into place. An
   archive is unpacked in staging first. The app checks free space before it starts.
5. **Recordings made before the models arrived wait for them.** `transcribe` records them and
   transcribes them when the download finishes. Missing speaker models skip straight to the summary
   instead of failing.

## Consequences

- Install is: open the DMG, drag the app, open it, click Download, allow the microphone.
- Earshot now makes network requests, but only when the user clicks Download, only to Hugging Face
  and GitHub, and it sends nothing about the user. Help and PRIVACY.md say so.
- When upstream replaces a file, its hash no longer matches and the download fails with a clear
  message. The catalog must then be updated, which is deliberate.
- The tools themselves were still external (Homebrew `whisper-cli`, `ffmpeg`, `uv`) until
  ADR-2611141800 bundled them.

## Gate

`bash EarshotApp/Tests/run.sh`, where `Tests/ModelCatalogTests.swift` (written first) checks the
catalog against the scripts' paths, the installed-vs-missing rule (absent, truncated, empty archive
member, all present), the required set excluding Translate, the destinations, and SHA-256 against
known answers in chunks smaller than the file. It fails itself if fewer than 25 checks ran.
`Tests/render.sh` renders the card in all three states (`model-setup`, `window-first-run`).
