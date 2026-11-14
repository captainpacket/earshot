# ADR-2611141900: Distribute Earshot as a Homebrew cask from its own tap

**Status:** Accepted
**Date:** 2026-11-14
**Builds on:** ADR-2611141600 (notarized DMG), ADR-2611141800 (no Homebrew dependencies)
**Drivers:** Most people who try a developer-made Mac app have Homebrew. One command is the shortest
install there is, and `brew upgrade` gives them updates, which Earshot has no other way to deliver.

## Decision

1. **A tap of our own, `gaberger/homebrew-earshot`.** The official `homebrew/cask` repo needs a
   notability bar Earshot doesn't meet yet. A tap needs nothing. Users run
   `brew tap gaberger/earshot && brew install --cask earshot`.
2. **The cask is generated, not hand-edited.** `packaging/homebrew/earshot.rb.template` is the
   source. `scripts/update-cask <version> <dmg>` fills in the version and the SHA-256 of the exact
   DMG. Each tagged release's CI `homebrew` job runs it after the release is published and pushes
   `Casks/earshot.rb` to the tap with `HOMEBREW_TAP_TOKEN`, a fine-grained token scoped to that repo.
   If the token is missing, the job fails visibly.
3. **The cask states the real limits:** `depends_on arch: :arm64` and `macos: :tahoe` (macOS 26).
   Homebrew cannot express 26.4, so the app's own `LSMinimumSystemVersion` still enforces it.
4. **`zap` removes the log and the preferences, never `~/Models`.** Other whisper.cpp tools often
   share `~/Models/whisper`. Deleting it would break software that isn't ours.

## Consequences

- Release builds need a sixth secret, and the tap repository has to exist before the first release
  that uses it.
- Homebrew 7 asks users to trust third-party taps. INSTALL.md gives the `brew trust --tap` command
  for when it does.
- The cask is only as good as the DMG. It should point at a notarized release (ADR-2611141600) that
  bundles its tools (ADR-2611141800); otherwise the user hits Gatekeeper or a missing `whisper-cli`.

## Gate

`brew style` and `brew audit --cask --online --strict` pass on the generated cask in a throwaway
local tap (checked on 2026-11-14 against the 1.2.1 DMG: no offenses, and the download and SHA-256
verified).
