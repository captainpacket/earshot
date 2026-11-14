// The model files Earshot needs, and how to tell whether each is installed (ADR-2611141630).
// Pure Foundation + CryptoKit, so Tests/ModelCatalogTests.swift can run it without the app.
//
// The scripts read these paths: `transcribe` reads ~/Models/whisper, `speakers` reads ~/Models/speakers.
// Each download is pinned by SHA-256, so a changed or tampered file upstream fails the check instead
// of being installed.
import CryptoKit
import Foundation

enum ModelGroup: String, Sendable {
    case speech    // every transcript, plus the silence detector
    case speakers  // speaker labels
    case translate // only when Translate is on
}

struct ModelFile: Equatable, Sendable {
    let name: String           // shown while downloading
    let url: URL
    /// Relative to the models folder. The file whose presence means "installed".
    let installedPath: String
    /// Size of the download, in bytes.
    let bytes: Int64
    /// SHA-256 of the download (for an archive, of the archive itself).
    let sha256: String
    let group: ModelGroup
    /// A .tar.bz2 that unpacks into the folder named by the first part of `installedPath`.
    let archive: Bool
}

enum ModelCatalog {
    static let required: Set<ModelGroup> = [.speech, .speakers]

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Models")
    }

    // Hugging Face URLs are pinned to a commit, so "main" moving on cannot change what is downloaded.
    // Hashes cross-checked against Hugging Face's X-Linked-ETag (its SHA-256) on 2026-11-14.
    static let all: [ModelFile] = [
        ModelFile(name: "Speech to text",
                  url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo.bin")!,
                  installedPath: "whisper/ggml-large-v3-turbo.bin", bytes: 1_624_555_275,
                  sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
                  group: .speech, archive: false),
        ModelFile(name: "Silence detector",
                  url: URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v5.1.2.bin")!,
                  installedPath: "whisper/ggml-silero-v5.1.2.bin", bytes: 885_098,
                  sha256: "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf",
                  group: .speech, archive: false),
        ModelFile(name: "Speaker voices",
                  url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx")!,
                  installedPath: "speakers/wespeaker_en_voxceleb_resnet34_LM.onnx", bytes: 26_530_550,
                  sha256: "e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012",
                  group: .speakers, archive: false),
        ModelFile(name: "Speaker turns",
                  url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2")!,
                  installedPath: "speakers/sherpa-onnx-pyannote-segmentation-3-0/model.int8.onnx", bytes: 6_958_444,
                  sha256: "24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488",
                  group: .speakers, archive: true),
        ModelFile(name: "Translation",
                  url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin")!,
                  installedPath: "whisper/ggml-large-v3-q5_0.bin", bytes: 1_081_140_203,
                  sha256: "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
                  group: .translate, archive: false),
    ]

    static func files(_ groups: Set<ModelGroup>) -> [ModelFile] {
        all.filter { groups.contains($0.group) }
    }

    /// The size of the file at a path, or nil when there is none.
    static func fileSize(_ path: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
    }

    /// Files in `groups` that are not installed, in catalog order. A plain file counts only at exactly
    /// its expected size, so a download cut off by hand is not mistaken for the model. An unpacked
    /// archive member counts when it is not empty.
    static func missing(_ groups: Set<ModelGroup>, root: URL = defaultRoot,
                        size: (String) -> Int64? = fileSize) -> [ModelFile] {
        files(groups).filter { f in
            let have = size(root.appendingPathComponent(f.installedPath).path)
            return f.archive ? (have ?? 0) <= 0 : have != f.bytes
        }
    }

    static func totalBytes(_ files: [ModelFile]) -> Int64 { files.reduce(0) { $0 + $1.bytes } }

    /// Where a plain file is installed.
    static func destination(for f: ModelFile, root: URL) -> URL { root.appendingPathComponent(f.installedPath) }

    /// The folder an archive unpacks into: the first part of its installed path.
    static func extractDirectory(for f: ModelFile, root: URL) -> URL {
        root.appendingPathComponent(String(f.installedPath.split(separator: "/").first ?? ""))
    }

    /// SHA-256 of a file as lowercase hex, read in chunks so a 1.6 GB model does not sit in memory.
    static func sha256(of url: URL, chunk: Int = 4 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: chunk), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// "1.6 GB", "27 MB": decimal units, as Finder shows them.
    static func size(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1e9 { return String(format: "%.1f GB", b / 1e9) }
        if b >= 1e6 { return String(format: "%.0f MB", b / 1e6) }
        return String(format: "%.0f KB", max(1, b / 1e3))
    }
}
