# Developing Earshot

Back to the [README](../README.md).

## Build from source

Install the tools and models first, then build. The steps are in [INSTALL.md](INSTALL.md) (Step 3, Option B):

```bash
bash EarshotApp/build.sh
```

`build.sh` builds and installs the app and the scripts. `bash EarshotApp/make-dmg.sh` packs the built app into `Earshot-<version>.dmg`.

## Running the tests

The editor tests run in a real text view:

```bash
bash EarshotApp/Tests/run.sh
```

`scripts/readme-check` guards the README and these docs (structure, links, images and wording): `python3 -I scripts/readme-check`.

## Versions and releases

The version lives in one place, the [`VERSION`](../VERSION) file, as `MAJOR.MINOR.PATCH`
([semantic versioning](https://semver.org)): bump PATCH for fixes, MINOR for new features,
MAJOR for changes that break how things worked before. `build.sh` stamps it into the app with a
build number (the commit count, so it only goes up) and the commit hash, marked `-dirty` when
built from uncommitted changes.

To release, write the notes in `docs/releases/<version>.md` (they must name `Earshot-<version>.dmg`
and say the About version reads `<version>`), then, from `main`:

```bash
scripts/release minor -m "what's new"    # or patch, major, or an exact version like 1.1.0
scripts/release minor --dry-run          # check everything, change nothing
scripts/release minor -m "..." --push    # also push main and the tag to origin and github
```

The script refuses unless you're on `main` with a clean tree, the notes exist, the version is newer
and the tests pass. It bumps `VERSION`, commits it with the notes, and tags `v<version>`. Without
`--push` it prints the push commands. `scripts/release-test` checks the script itself.

The tag makes CI build the disk image and publish it as a
[GitHub release](https://github.com/gaberger/earshot/releases) with the notes file.
CI stops if the tag and `VERSION` don't match.

### Signing and notarization

Tag builds are signed with Developer ID and notarized, so the DMG opens with a double-click
(ADR-2611141600). CI stops a tag build that is missing any of these repository secrets
(Settings → Secrets and variables → Actions):

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12` | The **Developer ID Application** certificate and its private key, exported from Keychain Access as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you gave that .p12 when exporting it |
| `NOTARY_KEY_P8` | An App Store Connect API key (Users and Access → Integrations → Team Keys, role Developer), `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | That key's Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID shown above the keys list |

| `HOMEBREW_TAP_TOKEN` | A fine-grained GitHub token with **Contents: read and write** on `gaberger/homebrew-earshot` only. CI uses it to update the cask after each release |

To sign and notarize on your own Mac instead:

```bash
xcrun notarytool store-credentials earshot-notary --apple-id <you@example.com> --team-id <TEAMID>  # once
export EARSHOT_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
bash EarshotApp/build.sh && bash EarshotApp/make-dmg.sh
EARSHOT_NOTARY_PROFILE=earshot-notary bash EarshotApp/notarize.sh Earshot-<version>.dmg
```

Without `EARSHOT_SIGN_IDENTITY`, `build.sh` signs ad hoc, as it always has. Every build uses the
hardened runtime and `EarshotApp/Earshot.entitlements`. Set `EARSHOT_APP=<path>` to build somewhere
other than `~/Applications`, without touching `~/.local/bin`.

Design decisions are recorded as ADRs in `docs/adrs`, and release notes live in `docs/releases`.
`scripts/readme-check` guards this README (structure, links, images and wording).

## Project layout

```
.
├── VERSION                the app's version (MAJOR.MINOR.PATCH); see Versions and releases
├── .github/workflows/     CI: build, test and disk image on every push; a release for each v* tag
├── EarshotApp/
│   ├── Earshot.swift      the whole app: timeline, tabs, recording, speakers, summaries
│   ├── RichText.swift     the rich summary editor, and Markdown ↔ formatted text
│   ├── Tests/             editor tests in a real text view: bash EarshotApp/Tests/run.sh
│   ├── Info.plist         name, icon, microphone permission text, file types it opens
│   ├── Tools/             the bundled helpers: earshot-convert (audio decoding) and speakers (native sherpa-onnx)
│   ├── vendor.sh          fetches and builds what the app bundles: whisper-cli, sherpa-onnx (→ .vendor/)
│   ├── build.sh           builds and installs the app and the helpers
│   ├── make-dmg.sh        packs the built app into Earshot-<version>.dmg (drag to Applications)
│   └── notarize.sh        notarizes and staples a Developer ID-signed DMG
├── scripts/
│   ├── transcribe         whisper.cpp wrapper
│   ├── earshot-mcp        read-only MCP server
│   ├── earshot-speak      spoken replies hook for Claude Code
│   ├── release            version bump, tag and release
│   └── readme-check       gate for the README and docs: python3 -I scripts/readme-check
├── docs/
│   ├── INSTALL.md, GUIDE.md, PRIVACY.md, AGENTS.md, DEVELOPMENT.md
│   ├── adrs/              design decisions, one ADR each
│   ├── releases/          release notes, one file per version
│   ├── brand/             logo and brand explorations
│   └── website/           website copy and screenshot notes
└── assets/
    ├── Earshot.icon/      the app icon: layered Icon Composer file (background + glass layers)
    ├── badges/            the README badges (assets/badges/*.svg)
    ├── menubar.svg        the menu bar ear (a template image macOS tints)
    ├── earshot-logo.png   the app icon as macOS draws it, used as the README logo
    └── screenshots/       the five app screenshots in the README (sample data)
```
