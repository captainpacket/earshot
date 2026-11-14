# ADR-2611141600: Sign releases with Developer ID and notarize them

**Status:** Accepted
**Date:** 2026-11-14
**Drivers:** Installing from the DMG ended at a Gatekeeper wall. Running `open` on a fresh install did
nothing (`spctl -a -vv` reported `rejected`, and the app kept `com.apple.quarantine`), and the user had
to find **System Settings → Privacy & Security → Open Anyway**. The owner's verdict: "we are not making
it easy to install". ADR-2611130933 also found that the ad-hoc signature is why macOS refuses
Earshot's notifications.

## Decision

1. **Every build uses the hardened runtime** with `EarshotApp/Earshot.entitlements`, which grants only
   `com.apple.security.device.audio-input`. Without that key the hardened runtime silently blocks
   the microphone, so local builds use it too and a missing entitlement shows up in development.
2. **`EARSHOT_SIGN_IDENTITY` switches `build.sh` to Developer ID signing** with a secure timestamp.
   Unset, the build is ad hoc with the fixed designated requirement, as before.
3. **`make-dmg.sh` signs the DMG** with the same identity. **`notarize.sh`** checks that the app inside
   is signed with Developer ID, uses the hardened runtime and has a timestamp. It then submits the
   DMG with `notarytool --wait`, prints the notary log on rejection, staples the ticket and runs
   `spctl --assess`. It takes a keychain profile (`EARSHOT_NOTARY_PROFILE`) or an App Store Connect
   API key (`NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`).
4. **CI signs and notarizes tag builds and fails without the secrets** (`DEVELOPER_ID_P12`,
   `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`). A release that
   Gatekeeper blocks is never published quietly. Branch and pull-request builds stay ad hoc.

## Consequences

- A downloaded DMG opens with a double-click, and so does the app inside it. INSTALL.md loses its
  "Open Anyway" step.
- Notifications work, so the call offer can post a system notification as well as its panel.
- The signing identity changes once, from ad hoc to Developer ID. The old TCC entries were stored
  against `identifier "com.gaberger.earshot"`, which the new signature still satisfies, so the
  Microphone and Accessibility permissions should carry over. If macOS asks again, that happens one
  time only. *(Amended by ADR-2611142000: the bundle ID is now `org.sticksandstrings.earshot`, so
  permissions are granted once more with the first Developer ID release.)*
- Releases depend on an Apple Developer Program membership and five repository secrets.

## Gate

`EARSHOT_APP=<scratch>/Earshot.app bash EarshotApp/build.sh` must produce an app where
`codesign -dvv --entitlements -` shows `flags=…runtime` and the `audio-input` key, and where
`codesign --verify --strict` passes. For a release, `notarize.sh` itself is the gate: it exits non-zero
unless the DMG is accepted, stapled, and assessed as accepted by `spctl`.
