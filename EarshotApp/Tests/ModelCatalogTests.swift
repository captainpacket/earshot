// Tests for ModelCatalog (ADR-2611141630): which model files Earshot needs, when one counts as
// installed, where a download goes, and the SHA-256 check that guards every download.
// Run: bash EarshotApp/Tests/run.sh
import Foundation

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

@main struct ModelCatalogTests {
    static func main() {
        let root = URL(fileURLWithPath: "/m")
        let all = ModelCatalog.all

        // The catalog matches what the scripts read: transcribe reads ~/Models/whisper, speakers ~/Models/speakers.
        let paths = Set(all.map(\.installedPath))
        for p in ["whisper/ggml-large-v3-turbo.bin", "whisper/ggml-silero-v5.1.2.bin", "whisper/ggml-large-v3-q5_0.bin",
                  "speakers/sherpa-onnx-pyannote-segmentation-3-0/model.int8.onnx",
                  "speakers/wespeaker_en_voxceleb_resnet34_LM.onnx"] {
            checkTrue("catalog has \(p)", paths.contains(p))
        }
        checkTrue("five model files", all.count == 5, "\(all.count)")
        checkTrue("every hash is 64 lowercase hex digits",
                  all.allSatisfy { $0.sha256.count == 64 && $0.sha256.allSatisfy { "0123456789abcdef".contains($0) } })
        checkTrue("every URL is https", all.allSatisfy { $0.url.scheme == "https" })
        checkTrue("every size is positive", all.allSatisfy { $0.bytes > 0 })
        checkTrue("the translate model is not in the required set",
                  ModelCatalog.files(ModelCatalog.required).allSatisfy { $0.group != .translate })
        checkTrue("the required set is speech and speakers", ModelCatalog.required == [.speech, .speakers])
        checkTrue("only the segmentation model is an archive", all.filter(\.archive).map(\.installedPath)
                  == ["speakers/sherpa-onnx-pyannote-segmentation-3-0/model.int8.onnx"])

        // Missing: nothing on disk means everything in the asked-for groups is missing.
        let none: (String) -> Int64? = { _ in nil }
        checkTrue("empty disk: all required files missing",
                  ModelCatalog.missing(ModelCatalog.required, root: root, size: none).count == 4)
        checkTrue("empty disk: translate alone is one file",
                  ModelCatalog.missing([.translate], root: root, size: none).map(\.installedPath) == ["whisper/ggml-large-v3-q5_0.bin"])

        // A file of exactly the expected size counts as installed; any other size (a cut-off curl) does not.
        let full: (String) -> Int64? = { path in
            all.first { root.appendingPathComponent($0.installedPath).path == path }.map { $0.archive ? 1 : $0.bytes }
        }
        checkTrue("everything present: nothing missing", ModelCatalog.missing([.speech, .speakers, .translate], root: root, size: full).isEmpty)
        let turbo = all.first { $0.installedPath.hasSuffix("turbo.bin") }!
        let partial: (String) -> Int64? = { path in
            path.hasSuffix("turbo.bin") ? turbo.bytes / 2 : full(path)
        }
        checkTrue("a half-downloaded turbo model is missing",
                  ModelCatalog.missing(ModelCatalog.required, root: root, size: partial).map(\.installedPath) == [turbo.installedPath])
        let empty: (String) -> Int64? = { path in path.hasSuffix("model.int8.onnx") ? 0 : full(path) }
        checkTrue("an empty extracted segmentation model is missing",
                  ModelCatalog.missing(ModelCatalog.required, root: root, size: empty).count == 1)
        checkTrue("missing keeps catalog order (biggest required download first)",
                  ModelCatalog.missing(ModelCatalog.required, root: root, size: none).first?.installedPath == turbo.installedPath)

        checkTrue("total bytes adds the sizes",
                  ModelCatalog.totalBytes(Array(all.prefix(2))) == all[0].bytes + all[1].bytes)

        // Where things go.
        let seg = all.first(where: \.archive)!
        checkTrue("an archive extracts into the folder of its first path part",
                  ModelCatalog.extractDirectory(for: seg, root: root).path == "/m/speakers")
        checkTrue("a plain file lands at its installed path",
                  ModelCatalog.destination(for: turbo, root: root).path == "/m/whisper/ggml-large-v3-turbo.bin")

        // SHA-256 of a real file, against a known answer, read in chunks smaller than the file.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-sha-\(getpid())")
        try? Data("abc".utf8).write(to: tmp)
        let abc = (try? ModelCatalog.sha256(of: tmp, chunk: 2)) ?? ""
        checkTrue("sha256(\"abc\") in 2-byte chunks", abc == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", abc)
        let big = Data(repeating: 0x61, count: 1_000_000)
        try? big.write(to: tmp)
        let million = (try? ModelCatalog.sha256(of: tmp)) ?? ""
        checkTrue("sha256 of a million 'a's", million == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", million)
        try? FileManager.default.removeItem(at: tmp)
        checkTrue("sha256 of a missing file throws", (try? ModelCatalog.sha256(of: tmp)) == nil)

        checkTrue("human sizes", ModelCatalog.size(1_624_555_275) == "1.6 GB" && ModelCatalog.size(26_530_550) == "27 MB",
                  "\(ModelCatalog.size(1_624_555_275)) \(ModelCatalog.size(26_530_550))")

        if checks < 25 { print("VACUOUS: only \(checks) checks ran"); exit(1) }
        print(failures == 0 ? "ModelCatalogTests: all \(checks) passed" : "ModelCatalogTests: \(failures) of \(checks) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
