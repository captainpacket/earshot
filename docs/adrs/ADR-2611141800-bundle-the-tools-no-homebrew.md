# ADR-2611141800: Bundle the tools in the app, so installing needs no Homebrew

**Status:** Accepted
**Date:** 2026-11-14
**Builds on:** ADR-2611141600 (notarization), ADR-2611141630 (in-app model download)
**Drivers:** After the models moved into the app, installing still started with
`brew install whisper-cpp ffmpeg uv`. Users without Homebrew had to install it first. The first
speaker detection also downloaded Python packages through `uv`, so a Mac set up offline could not
label speakers. The owner asked for the Homebrew step to go.

## Decision

1. **whisper-cli is built from source and bundled.** `EarshotApp/vendor.sh` clones whisper.cpp at a
   pinned commit (`v1.9.5`, `d1be6fd…`) and builds it statically with Metal embedded, using
   `GGML_NATIVE=OFF` so it runs on every Apple silicon Mac. It fails if the binary links anything
   outside `/usr/lib` and `/System`.
2. **ffmpeg is replaced by AVFoundation.** `earshot-convert` (`Tools/convert`) decodes any file
   macOS can read into 16 kHz mono 16-bit WAV, with the downmix and resampling done by
   `AVAssetReaderAudioMixOutput`. Ogg and WebM, which AVFoundation can't read, still go through
   ffmpeg when one is installed; otherwise the error says to install it. `transcribe -r`, a
   terminal-only recorder, still needs ffmpeg.
3. **Speaker detection is native.** `speakers` (`Tools/speakers`) is a Swift port of the Python
   script. It calls the sherpa-onnx C API directly through a bridging header. The official macOS
   arm64 build of sherpa-onnx 2.0.1 (pinned by SHA-256) ships `libsherpa-onnx-c-api.dylib` and
   `libonnxruntime.dylib` in `Contents/Frameworks`. The merge logic (`SpeakerMerge.swift`) is pure,
   and the Python script and its test are deleted.
4. **The terminal keeps its commands.** `build.sh` writes `~/.local/bin/transcribe`, `speakers` and
   `earshot-speak` as two-line wrappers that exec the app's own copies, so the terminal and the app
   never drift apart.
5. **All nested code is signed inside out with the hardened runtime.** Ad-hoc builds give `speakers`
   `disable-library-validation`, because library validation requires a team ID and an ad-hoc
   signature has none. Developer ID builds don't need it: every file is signed by the same team.

## Consequences

- Install is: drag the app (or `brew install --cask`), open it, click Download. Nothing else.
- Speaker detection works on a Mac that has never been online since the models downloaded.
- The app grows from about 3 MB to 44 MB, of which ONNX Runtime is 29 MB.
- Building from source needs `cmake` as well as Xcode. CI caches `.vendor` keyed on `vendor.sh`.
- AVFoundation drops AAC priming samples that ffmpeg keeps, so the audio is about 20 ms shorter.
  Whisper and the speaker model both read the same decoded audio, so their timings still agree.

## Gate

- `bash EarshotApp/Tests/run.sh`, where `Tests/SpeakerMergeTests.swift` (written against the Python
  oracle before the port was trusted) feeds the original script's turns and word timings into the
  port and requires its exact output, byte for byte. The fixtures come from a synthetic three-voice
  meeting made with `say`. The test also checks the atomic rewrite, which was the old
  `scripts/speakers-test`, and checks that a WAV written by `writeWAV` decodes back to the same
  samples. It fails itself if fewer than 25 checks ran.
- End to end, with `PATH=/usr/bin:/bin`, the bundle's `transcribe` and then `speakers` on that
  meeting produce exactly the Python pipeline's transcript. The meeting was also imported through
  the GUI: transcribe, speakers and summary all finished with no Homebrew tool on PATH.
