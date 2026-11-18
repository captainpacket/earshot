// Notes typed while a meeting records (ADR-2611142100): where they are kept and how the summary reads them.
// Foundation only.
import Foundation

enum MeetingNotes {
    /// The most of the notes the summary reads, so they cannot crowd out the transcript.
    static let limit = 2000

    /// `<recording>.notes.md`, beside the audio file.
    static func url(for audio: URL) -> URL {
        URL(fileURLWithPath: audio.deletingPathExtension().path + ".notes.md")
    }

    /// The text the summary reads: the notes first, labelled as the recorder's own, then the transcript.
    static func compose(transcript: String, notes: String?) -> String {
        let trimmed = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return transcript }
        let kept = trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
        return "Notes the person recording typed during the meeting:\n\(kept)\n\nTranscript:\n\(transcript)"
    }
}
