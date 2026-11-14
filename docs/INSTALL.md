# Install Earshot

Earshot is one app. It carries the tools it runs, and it downloads its speech and speaker models
the first time you open it. You don't need Homebrew or the terminal. Plan on about 2 GB of downloads.

Back to the [README](../README.md). Next: the [user guide](GUIDE.md).

## What you need

- A Mac with **Apple silicon** (M1 or later)
- **macOS 26.4** or later
- **Apple Intelligence** turned on, in System Settings → Apple Intelligence & Siri (for summaries)
- About **3 GB** of free disk space for the models

## Step 1: Install the app

Choose one.

### Option A: Homebrew

If you use [Homebrew](https://brew.sh):

```bash
brew tap gaberger/earshot
brew install --cask earshot
```

If Homebrew says the tap is not trusted, run `brew trust --tap gaberger/earshot` and try again.
Updates come with `brew upgrade`.

### Option B: Download the disk image

1. Download **Earshot-&lt;version&gt;.dmg** from the latest
   [**release**](https://github.com/gaberger/earshot/releases/latest).
   (For a build of the newest commit instead, open the latest successful
   [**Build** run](https://github.com/gaberger/earshot/actions/workflows/build.yml), download the
   **Earshot-&lt;version&gt;** artifact while signed in to GitHub, and unzip it.)
2. Open the disk image and drag **Earshot** onto **Applications**.
3. Eject the disk image.

### Option C: Build from source

This needs **Xcode** (from the App Store; the command-line tools alone don't include `actool`) and
`cmake` (`brew install cmake`), which builds the bundled whisper.cpp.

```bash
git clone https://github.com/gaberger/earshot.git
cd earshot
bash EarshotApp/build.sh
```

This builds `Earshot.app`, installs it in `~/Applications`, and puts `transcribe` and `speakers`
commands in `~/.local/bin` so you can use them from the terminal too. To make your own disk image
afterwards, run `bash EarshotApp/make-dmg.sh` (→ `Earshot-<version>.dmg`).

## Step 2: Open Earshot and download the models

1. **Open the app.** Releases are signed with an Apple Developer ID and notarized, so Earshot opens
   with a double-click. (Releases before notarization, 1.2.1 and earlier, were not notarized, and
   macOS says it can't check the app. For those, click **Done**, then go to
   **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.)
2. **Click Download** on the card at the top of **Recordings**. It fetches the speech model, the
   silence detector and the two speaker models (1.7 GB together). Each file is checked against a
   fixed SHA-256 fingerprint before it is installed in `~/Models/whisper` and `~/Models/speakers`.
   After this, nothing needs the internet.
3. **Allow the microphone.** The first time you click **Record**, macOS asks. Click **Allow**.
   To change it later: System Settings → Privacy & Security → Microphone.
4. **Pick your microphone** in **Settings** (<kbd>⌘</kbd> <kbd>,</kbd>) if you don't want the
   system default.

Translate uses one more model (1.1 GB). Earshot offers it the first time you turn **Translate** on.

| Model | Needed for | If it's missing |
|---|---|---|
| `ggml-large-v3-turbo.bin` | Every transcript | Recordings wait, and are transcribed as soon as it arrives |
| `ggml-silero-v5.1.2.bin` | Skipping silence | Same as above (it downloads with the speech model) |
| `ggml-large-v3-q5_0.bin` | **Translate** | Earshot offers it when you turn Translate on |
| `sherpa-onnx-pyannote-segmentation-3-0/`, `wespeaker_en_voxceleb_resnet34_LM.onnx` | Speaker labels | Transcripts have no speaker names |

<details>
<summary>Prefer the terminal, or setting up a Mac without a window?</summary>

```bash
mkdir -p ~/Models/whisper && cd ~/Models/whisper
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin   # 1.6 GB, required
curl -LO https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin      # 1 MB, skips silence
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin     # 1.1 GB, only for Translate
mkdir -p ~/Models/speakers && cd ~/Models/speakers
curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2 | tar xj
curl -LO https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
```

Earshot finds files placed this way and does not download them again.
</details>

## Check that it works

Record a few seconds of speech and click **Stop**. The status bar at the bottom shows
*Transcribing*, then *Finding speakers*, then *Summarizing*, and the summary appears.

If a step fails, Earshot shows the error above the tabs:

| Error | Fix |
|---|---|
| `Download the speech models first` | Click **Download** on the card at the top of Recordings |
| `Model not found: …/ggml-large-v3-turbo.bin` | The same: the card downloads it to exactly that folder |
| `cannot read … Ogg and WebM files need ffmpeg` | Earshot reads every audio and video format macOS does. For Ogg and WebM, `brew install ffmpeg` |
| `Speaker detection failed: … model files missing` | Click **Download** on the card at the top of Recordings |
| `Apple Intelligence is off` | Turn it on in System Settings → Apple Intelligence & Siri |
| `Apple's on-device model is still downloading` | Wait for macOS to finish downloading it, then click **Summarize** |

`~/Library/Logs/Earshot.log` records each step and its result (never what was said).

## Update

To see which version you have, choose **Earshot → About Earshot**, or look at the bottom of the
menu bar panel. It reads like `1.0.0 (16, 3113bfa)`: the version, the build number, and the commit
it was built from.

- **Homebrew:** `brew upgrade --cask earshot`.
- **Disk image:** download the new one and drag it onto **Applications** again. Choose **Replace**.
- **From source:** `git pull`, then `bash EarshotApp/build.sh`.

Your recordings, summaries, models and settings stay where they are.

## Uninstall

1. Quit Earshot, then drag it from Applications to the Trash (or `brew uninstall --cask earshot`).
2. Remove the parts you no longer want:

   ```bash
   rm -f ~/.local/bin/transcribe ~/.local/bin/speakers ~/.local/bin/earshot-speak  # terminal commands (source builds only)
   rm -rf ~/Models/whisper ~/Models/speakers             # models, about 3 GB
   rm -f ~/Library/Logs/Earshot.log                      # activity log
   defaults delete com.gaberger.earshot                  # settings
   defaults delete local.whisper.transcribe 2>/dev/null  # settings from versions before the Earshot name
   ```

   With Homebrew, `brew uninstall --cask --zap earshot` removes the log and settings too. It leaves
   the models, because other whisper.cpp tools may use the same `~/Models` folders.

3. Your recordings are in `~/Recordings/whisper`. Delete that folder only if you don't want them.

## Where things live

| What | Where |
|---|---|
| The app | `/Applications/Earshot.app` (Homebrew or disk image) or `~/Applications/Earshot.app` (built from source) |
| Recordings and results | `~/Recordings/whisper/` — per recording: audio, `.txt`, `.srt`, `.json`, `.summary.md`, `.name` |
| Bundled tools | Inside the app: `whisper-cli`, `earshot-convert` and `speakers` in `Contents/MacOS`, the sherpa-onnx libraries in `Contents/Frameworks`, the `transcribe` script in `Contents/Resources`. Source builds also put terminal commands in `~/.local/bin`. |
| Models | `~/Models/whisper/`, `~/Models/speakers/` |
| Activity log | `~/Library/Logs/Earshot.log` — clicks, file names and results, never what was said |
