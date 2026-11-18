# ADR-2611142000: The bundle ID is org.sticksandstrings.earshot

**Status:** Accepted
**Date:** 2026-11-14
**Amends:** ADR-2611141600 (its note that permissions carry over under `com.gaberger.earshot`)
**Drivers:** Releases will be signed with the Sticks and Strings Developer ID. The owner wants the
app's identity to match.

## Decision

1. **`CFBundleIdentifier` and the ad-hoc designated requirement are `org.sticksandstrings.earshot`.**
2. **Settings carry over.** `PrefsMigration` (in `PreferencesMigration.swift`) copies the settings
   saved under `com.gaberger.earshot`, then those under `local.whisper.transcribe`, into the new
   domain once at launch. A value set since is never replaced, and each old ID has its own marker, so
   the copy runs once per ID. The oldest keeps the marker it always had, `migratedFromOldBundleID`.
3. **Uninstall removes all three domains.** INSTALL.md lists them, and the cask's `zap` trashes all
   three preference files.

## Consequences

- macOS treats the renamed app as a new app. Microphone and Accessibility must be granted once
  more. The first Developer ID release (ADR-2611141600) changes the signing identity anyway, so
  people re-grant once for both changes, not twice.
- Old TCC entries for `com.gaberger.earshot` stay in the TCC database, which does no harm.
  `tccutil reset All com.gaberger.earshot` removes them.
- The old ID still appears in the migration, its test, the uninstall steps, the cask and the ADRs.
  It must not appear anywhere else.

## Gate

`hexa loop` records it: the tests pass (including `PreferencesMigrationTests`), the typecheck is
clean, `Info.plist` and `build.sh` carry the new ID, and `git grep com.gaberger.earshot` finds the old
ID only in the files listed above.
