// speakers — label who spoke when, offline, and merge it with a whisper.cpp transcript.
//
//     speakers AUDIO [-n NUM_SPEAKERS] [-t THRESHOLD]
//
// Reads AUDIO and the whisper.cpp word-level JSON beside it (AUDIO-base.json, written by
// `transcribe`), finds speaker turns with sherpa-onnx (pyannote segmentation + WeSpeaker voice
// embeddings), and rewrites AUDIO-base.txt as "[00:01:23] Speaker 1: words...".
// Nothing leaves this Mac. Models live in ~/Models/speakers.
//
// Native since ADR-2611141800: it links sherpa-onnx's C library from the app bundle, so it needs no
// Python, no uv and no package download.
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}
func note(_ message: String) { FileHandle.standardError.write(Data("\(message)\n".utf8)) }

let usage = """
    usage: speakers [-h] [-n NUM_SPEAKERS] [-t THRESHOLD] audio

    Label speakers in a whisper.cpp transcript, offline.

    positional arguments:
      audio

    options:
      -h, --help            show this help message and exit
      -n, --num-speakers NUM_SPEAKERS
                            exact number of speakers (default: auto)
      -t, --threshold THRESHOLD
                            auto mode: lower finds more speakers, higher fewer
                            (default 0.7)
    """

// MARK: arguments
var numSpeakers = -1
var threshold = SpeakerMerge.defaultThreshold
var audioPath: String?
var rest = Array(CommandLine.arguments.dropFirst())
while !rest.isEmpty {
    let a = rest.removeFirst()
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "-n", "--num-speakers":
        guard let v = rest.first.flatMap({ Int($0) }) else { fail("speakers: -n needs a whole number") }
        numSpeakers = v; rest.removeFirst()
    case "-t", "--threshold":
        guard let v = rest.first.flatMap({ Float($0) }) else { fail("speakers: -t needs a number") }
        threshold = v; rest.removeFirst()
    default:
        guard audioPath == nil, !a.hasPrefix("-") else { fail(usage) }
        audioPath = a
    }
}
guard let audioPath else { fail(usage) }

let audio = URL(fileURLWithPath: audioPath)
let base = audio.deletingPathExtension()
let jsonURL = URL(fileURLWithPath: base.path + ".json")
let txtURL = URL(fileURLWithPath: base.path + ".txt")
guard FileManager.default.fileExists(atPath: jsonURL.path) else {
    fail("speakers: no word timings at \(jsonURL.path); run transcribe first")
}

let models = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SPEAKER_MODEL_DIR"]
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models/speakers").path)
let segmentation = models.appendingPathComponent("sherpa-onnx-pyannote-segmentation-3-0/model.int8.onnx").path
let embedding = models.appendingPathComponent("wespeaker_en_voxceleb_resnet34_LM.onnx").path
guard FileManager.default.fileExists(atPath: segmentation), FileManager.default.fileExists(atPath: embedding) else {
    fail("speakers: model files missing or invalid in \(models.path)")
}

let words: [TimedWord]
do { words = try SpeakerMerge.words(fromWhisperJSON: Data(contentsOf: jsonURL)) } catch {
    fail("speakers: cannot read \(jsonURL.path): \(error.localizedDescription)")
}
guard !words.isEmpty else { fail("speakers: transcript is empty") }

let samples: [Float]
do { samples = try AudioDecode.samples(audio) } catch { fail("speakers: \(error.localizedDescription)") }

// MARK: diarize
func diarize(provider: String) -> [SpeakerTurn]? {
    segmentation.withCString { seg in embedding.withCString { emb in provider.withCString { prov in
        var config = SherpaOnnxOfflineSpeakerDiarizationConfig()
        config.segmentation.pyannote.model = seg
        config.segmentation.num_threads = 8
        config.segmentation.provider = prov
        config.embedding.model = emb
        config.embedding.num_threads = 8
        config.embedding.provider = prov
        config.clustering.num_clusters = Int32(numSpeakers)
        config.clustering.threshold = threshold
        config.min_duration_on = 0.3
        config.min_duration_off = 0.5
        guard let sd = SherpaOnnxCreateOfflineSpeakerDiarization(&config) else { return nil }
        defer { SherpaOnnxDestroyOfflineSpeakerDiarization(sd) }
        guard let result = samples.withUnsafeBufferPointer({
            SherpaOnnxOfflineSpeakerDiarizationProcess(sd, $0.baseAddress, Int32($0.count))
        }) else { return nil }
        defer { SherpaOnnxOfflineSpeakerDiarizationDestroyResult(result) }
        let n = Int(SherpaOnnxOfflineSpeakerDiarizationResultGetNumSegments(result))
        guard n > 0, let segs = SherpaOnnxOfflineSpeakerDiarizationResultSortByStartTime(result) else { return [] }
        defer { SherpaOnnxOfflineSpeakerDiarizationDestroySegment(segs) }
        return (0..<n).map { SpeakerTurn(start: Double(segs[$0].start), end: Double(segs[$0].end), speaker: Int(segs[$0].speaker)) }
    } } }
}

// CoreML runs on the Mac's GPU / Neural Engine, about twice as fast as CPU.
var turns = diarize(provider: "coreml")
if turns == nil {
    note("speakers: CoreML failed; using CPU")
    turns = diarize(provider: "cpu")
}
guard var turns else { fail("speakers: model files missing or invalid in \(models.path)") }
if turns.isEmpty {
    note("speakers: no speech turns found; transcript left as is")
    exit(0)
}
if SpeakerMerge.mergesTinySpeakers(numSpeakers: numSpeakers) {
    turns = SpeakerMerge.dropTinySpeakers(turns)
}

let out = SpeakerMerge.transcript(words: words, turns: turns)
do { try SpeakerMerge.writeAtomic(out.text, to: txtURL) } catch {
    fail("speakers: cannot write \(txtURL.path): \(error.localizedDescription)")
}
note("speakers: \(out.speakers) speaker(s), \(out.lines) turns → \(txtURL.path)")
