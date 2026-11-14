// earshot-convert IN OUT.wav — any audio or video file macOS reads → 16 kHz mono 16-bit WAV for
// whisper-cli (ADR-2611141800). `transcribe` uses it in place of ffmpeg.
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: earshot-convert INPUT OUTPUT.wav\n".utf8))
    exit(2)
}
do {
    let samples = try AudioDecode.samples(URL(fileURLWithPath: args[1]))
    try AudioDecode.writeWAV(samples, to: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write(Data("earshot-convert: \(error.localizedDescription)\n".utf8))
    exit(1)
}
