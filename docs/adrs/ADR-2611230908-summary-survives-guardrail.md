# ADR-2611230908: A summary survives a passage Apple's safety filter refuses

**Status:** Accepted
**Date:** 2026-11-23
**Amends:** ADR-2611181715 (summaries are written part by part and merged)
**Drivers:** The owner saw "Summary failed: Detected content likely to be unsafe" and got no summary at
all. That message is Apple's `GenerationError.guardrailViolation` from the on-device model.

`Summarizer` asks for `.permissiveContentTransformations`, but every part is a guided generation
(`generating: GeneratedPart.self`), and guided generation runs Apple's default guardrails. Ordinary
meeting talk trips them: swearing, medical or legal topics, "kill that project", or a misheard word.
`Summarizer.part` recovers from a too-long part and from a decoding failure, but not from this error,
so one flagged part out of twenty throws to `Library.summarize` and the whole summary is lost.

## Decision

1. **The recovery for one part is a pure function** (`SummaryRecovery.swift`, Foundation only). It takes
   the generate call, an error classifier and the model's token counter as closures, so it is tested
   without the model. `Summarizer` passes the real ones and maps FoundationModels errors to `PartFailure`
   (`tooLong`, `undecodable`, `unsafe`, `other`), on macOS 26's `GenerationError` and macOS 27's
   `LanguageModelError`.
2. **A refused part is halved, like a too-long one**, down to the same depth limit (3). This narrows the
   refusal to the passage that caused it and keeps the rest of the part.
   - **Halving goes by the chunk's own size**, at lines, then words (`TokenChunker`). The first version
     halved by the part *budget*, as the too-long path always had. On a real run, a 205-word transcript
     far under half the budget came back whole at every depth, and the whole thing was skipped.
   - **Halves are never under 100 tokens** (`minPieceTokens`). The second real run halved the same
     transcript into one-line pieces, and the model invented content from them: 72 bullets from 205
     words, with its own schema text leaking into one. A refused chunk that cannot be halved above the
     floor is skipped instead. A real part is about 2,000 tokens, so after three halvings a piece is
     still about 250 tokens, and at most about an eighth of one part is lost.
3. **A piece still refused at the depth limit is skipped and counted.** The summary is written from the
   other parts, and `SummaryFormat.render` adds a line under the overview saying how many passages the
   on-device model would not summarize, so the gap is visible, never silent.
4. **If every passage is refused**, the summary fails with a plain message that says Apple's on-device
   model declined the content, instead of an empty summary that looks healthy.
5. Too-long and decoding failures keep their current behaviour. Any other error still fails the summary.

Nothing leaves the Mac: there is no fallback to Private Cloud Compute or any other model.

## Gate

`cd EarshotApp && swiftc -typecheck -parse-as-library -swift-version 5 -target arm64-apple-macosx26.4 *.swift && bash Tests/run.sh`

`Tests/SummaryRecoveryTests.swift` drives `PartRecovery` with a fake model that refuses chosen text and a
fake tokenizer of one token per word. It checks that a refused part is halved by its own size, that only
the refused piece is skipped, that no piece under the floor reaches the model, that the count is right,
that an all-refused recording throws, that the other failures behave as before, and that `render` writes
the note only when something was skipped. It fails itself if fewer than 40 checks ran.

Checked on Apple's on-device model with `scripts/summarize-file` on a made-up 205-word meeting with one
passage of graphic violence: before, "Summary failed: Detected content likely to be unsafe"; after, a
summary of the budget, launch date and offsite items, with a note that 1 passage was left out.

## Not done

- Trying a refused piece again as plain-text generation (where the permissive guardrails do apply) and
  parsing the result into points. That would recover more text, but it adds a second output format to
  parse. Reconsider if skipped passages turn out to be common.
