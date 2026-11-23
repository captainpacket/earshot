// How one part of a summary recovers when Apple's on-device model fails on it (ADR-2611230908).
// Pure: the model, the error classifier and the splitter are passed in, so this is tested with a
// fake model (Tests/SummaryRecoveryTests.swift). Foundation only.

import Foundation

/// What went wrong with one call, in the terms recovery cares about.
enum PartFailure { case tooLong, undecodable, unsafe, other }

struct PartRecoveryResult {
    var parts: [SummaryPart]
    /// Passages Apple's safety filter still refused at the smallest size; they are left out.
    var skipped: Int
}

/// Every passage of the recording was refused, so there is nothing to summarize.
struct SummaryRefused: LocalizedError {
    var errorDescription: String? {
        "Apple's on-device model would not summarize any part of this recording, so there is no summary."
    }
}

enum PartRecovery {
    /// How many times a part may be halved. At this depth a part is a few hundred tokens.
    static let maxDepth = 3
    /// Halves are never smaller than this. A few speaker turns: from one-line pieces the model invents
    /// content (a 205-word test transcript gave 72 bullets), which is worse than leaving a passage out.
    static let minPieceTokens = 100

    /// Sections and action items for one chunk. Too long or refused: halved and each half tried, one level
    /// deeper. Undecodable: tried once more, then halved. A piece still refused at `maxDepth`, or too small
    /// to split into halves of at least `minPiece` tokens, is skipped and counted. Anything else, or too
    /// long / undecodable at the limit, is thrown.
    static func run(_ chunk: String,
                    generate: (String) async throws -> SummaryPart,
                    classify: (Error) -> PartFailure,
                    count: TokenChunker.Count,
                    minPiece: Int = minPieceTokens) async throws -> PartRecoveryResult {
        try await run(chunk, depth: 0, retried: false, generate: generate, classify: classify, count: count,
                      minPiece: minPiece)
    }

    /// Two pieces of about half the chunk's own tokens, split at lines, then words (TokenChunker), or none
    /// if a half would be under `minPiece`. Halving by the part budget instead returned a short chunk
    /// whole, so a refusal skipped all of it.
    static func halve(_ chunk: String, count: TokenChunker.Count, minPiece: Int) async throws -> [String] {
        let half = (try await count(chunk) + 1) / 2
        if half < max(1, minPiece) { return [] }
        return try await TokenChunker.split(chunk, budget: half, count: count)
    }

    private static func run(_ chunk: String, depth: Int, retried: Bool,
                            generate: (String) async throws -> SummaryPart,
                            classify: (Error) -> PartFailure,
                            count: TokenChunker.Count, minPiece: Int) async throws -> PartRecoveryResult {
        do {
            return PartRecoveryResult(parts: [try await generate(chunk)], skipped: 0)
        } catch {
            let failure = classify(error)
            if failure == .undecodable && !retried {
                return try await run(chunk, depth: depth, retried: true,
                                     generate: generate, classify: classify, count: count, minPiece: minPiece)
            }
            guard failure != .other else { throw error }
            let pieces = depth < maxDepth ? try await halve(chunk, count: count, minPiece: minPiece) : []
            if pieces.count < 2 {
                // At the limit: a refusal is left out and counted; anything else cannot be summarized.
                if failure == .unsafe { return PartRecoveryResult(parts: [], skipped: 1) }
                throw error
            }
            var out = PartRecoveryResult(parts: [], skipped: 0)
            for piece in pieces {
                let r = try await run(piece, depth: depth + 1, retried: false,
                                      generate: generate, classify: classify, count: count, minPiece: minPiece)
                out.parts += r.parts
                out.skipped += r.skipped
            }
            return out
        }
    }

    /// A summary with some passages left out is still a summary; one with every passage refused is not.
    static func checkNotAllRefused(parts: [SummaryPart], skipped: Int) throws {
        if parts.isEmpty && skipped > 0 { throw SummaryRefused() }
    }
}
