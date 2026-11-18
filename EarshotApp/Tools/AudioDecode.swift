// Decodes any audio or video file macOS can read into 16 kHz mono samples, the format Whisper and
// the speaker models want (ADR-2611141800). This replaces the ffmpeg conversion for everything
// AVFoundation opens: WAV, M4A/AAC, MP3, AIFF, CAF, FLAC, MP4, MOV, M4V. For the rest (Ogg, WebM),
// it uses ffmpeg when one is installed and otherwise says what to do.
import AVFoundation
import Foundation

enum AudioDecodeError: LocalizedError {
    case noAudio(String)
    case unreadable(String, String)

    var errorDescription: String? {
        switch self {
        case let .noAudio(path): return "no audio track in \(path)"
        case let .unreadable(path, why):
            return "cannot read \(path) (\(why)). Ogg and WebM files need ffmpeg: brew install ffmpeg"
        }
    }
}

enum AudioDecode {
    static let sampleRate = 16_000

    /// 16 kHz mono float samples in -1...1.
    static func samples(_ url: URL) throws -> [Float] {
        do {
            return try avFoundation(url)
        } catch {
            guard let ffmpeg = findFFmpeg() else {
                throw AudioDecodeError.unreadable(url.path, error.localizedDescription)
            }
            return try viaFFmpeg(url, ffmpeg: ffmpeg)
        }
    }

    private static func avFoundation(_ url: URL) throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try blocking { try await asset.loadTracks(withMediaType: .audio) }
        guard !tracks.isEmpty else { throw AudioDecodeError.noAudio(url.path) }
        let reader = try AVAssetReader(asset: asset)
        // The mix output downmixes every audio track to one channel and resamples, like ffmpeg -ac 1 -ar 16000.
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw AudioDecodeError.unreadable(url.path, "unsupported audio") }
        reader.add(output)
        guard reader.startReading() else {
            throw AudioDecodeError.unreadable(url.path, reader.error?.localizedDescription ?? "cannot start reading")
        }
        var out: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            let start = out.count
            out.append(contentsOf: repeatElement(0, count: count))
            _ = out.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
        }
        if reader.status == .failed {
            throw AudioDecodeError.unreadable(url.path, reader.error?.localizedDescription ?? "read failed")
        }
        return out
    }

    /// ffmpeg, if one is installed where Homebrew puts it or on PATH.
    static func findFFmpeg() -> String? {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in path + ["/opt/homebrew/bin", "/usr/local/bin"] {
            let candidate = (dir as NSString).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func viaFFmpeg(_ url: URL, ffmpeg: String) throws -> [Float] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("earshot-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-hide_banner", "-loglevel", "error", "-y", "-i", url.path,
                       "-ac", "1", "-ar", String(sampleRate), "-c:a", "pcm_s16le", tmp.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw AudioDecodeError.unreadable(url.path, "ffmpeg failed") }
        return try avFoundation(tmp)
    }

    /// A 16-bit PCM mono WAV at 16 kHz, the file whisper-cli reads. Written beside `url`, then renamed.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        var data = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            let clamped = max(-1, min(1, s))
            u16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        try data.write(to: url, options: .atomic)
    }

    /// Runs an async call to completion from synchronous command-line code.
    private static func blocking<T>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<T, Error>!
        Task.detached {
            do { result = .success(try await work()) } catch { result = .failure(error) }
            done.signal()
        }
        done.wait()
        return try result.get()
    }
}
