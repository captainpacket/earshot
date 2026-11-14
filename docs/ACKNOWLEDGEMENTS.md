# Acknowledgements

Earshot was designed and built on its own.
While building it we looked at other open-source projects for inspiration,
and a few features were shaped by what we saw there.
Thank you to the people behind them.

## Inspiration

- [OpenSuperWhisper](https://github.com/my-monkeys/OpenSuperWhisper) (MIT): the idea of a dictionary for words that dictation mishears, a tap-to-start, tap-to-stop mode, and the card-style layout.
- [Voicebox](https://github.com/jamiepine/voicebox) (MIT): the ideas of tidying dictated text with a local model, letting agents read recordings through an MCP server, and naming each stage on the dictation pill.
- Super Whisper: the idea of marking the window your dictation will land in. We know this one only by description, so there is no link.

No code was copied from any of these projects.
The design decisions that record each idea are in [docs/adrs](adrs/).

## Components Earshot uses

These are the projects and models Earshot uses, with their licenses as we understand them.

| Project | What Earshot uses it for | License |
|---|---|---|
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and the Whisper models | Speech to text. `whisper-cli` is built from source and bundled in the app | MIT |
| [Silero VAD](https://github.com/snakers4/silero-vad) | Skipping silence | MIT |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | The runtime that finds who spoke when. Its C library is bundled in the app | Apache 2.0 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | Runs the speaker models for sherpa-onnx; bundled in the app | MIT |
| pyannote segmentation 3.0 model | Splitting speech into speakers | MIT |
| [WeSpeaker](https://github.com/wenet-e2e/wespeaker) | The speaker voice model | Apache 2.0 for the code. The terms of the specific trained model file are not checked. |
| [uv](https://github.com/astral-sh/uv) | Ran the speaker script before 1.3, when speakers became native | Apache 2.0 |
| ffmpeg | Optional: reads Ogg and WebM files, which macOS can't. Everything else is decoded by macOS itself | Installed separately through Homebrew and not bundled with Earshot, so its own license applies |
| Apple Foundation Models | The on-device summaries and Tidy up | Apple terms |

Earshot itself is MIT licensed, see [LICENSE](../LICENSE).
