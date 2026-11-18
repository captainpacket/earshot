// Summaries from Apple's on-device model (ADR-2611181715). Map-reduce: every part of the
// transcript gets its own detailed sections and action items; SummaryFormat merges them and
// a last call writes only the title and overview. Foundation and FoundationModels only.

import Foundation
import FoundationModels

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// The shapes the model must fill in. Typed fields keep a small model on track far better
// than asking it for free-form Markdown (it used to copy the instructions into the output).
@Generable
struct GeneratedPart {
    @Guide(description: "The sections the instructions ask for that this part of the text covers, in that order. One section per topic this part spends real time on",
           .maximumCount(5))
    var sections: [GeneratedSection]
    @Guide(description: "Tasks a speaker said they or someone else will do in this part. Empty if there are none",
           .maximumCount(6))
    var actionItems: [GeneratedAction]
}

@Generable
struct GeneratedSection {
    @Guide(description: "The section heading: a specific topic name, or the section name the instructions give")
    var heading: String
    @Guide(description: "Detailed points, one full sentence each, with the specifics said: names, numbers, products, dates and reasons. Name who said it with the label at the start of the line, such as Speaker 2, never the speaker. Each point says something no other point says",
           .maximumCount(8))
    var points: [String]
}

@Generable
struct GeneratedAction {
    @Guide(description: "The speaker label, such as Speaker 1, or the name of the person the text says will do it. Unassigned if the text does not say who")
    var owner: String
    @Guide(description: "The task, starting with a verb, with the specifics said")
    var task: String
    @Guide(description: "A day or date only if the text states one. Otherwise an empty string")
    var due: String
}

@Generable
struct GeneratedHeader {
    @Guide(description: "A specific title of 3 to 8 words that names the main topic")
    var title: String
    @Guide(description: "Three to five sentences: who took part, using the speaker labels, what was discussed, and what was concluded")
    var overview: String
}

enum Summarizer {
    // On-device only. Do not switch this to PrivateCloudComputeLanguageModel: that one runs on Apple's servers.
    static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    // Budgets are measured in the model's own tokens: its context size, minus the instructions,
    // the schema, room for the response and a safety margin.
    static let partReserve = 1_400
    static let headerReserve = 400
    /// Long single-speaker turns are split at this many words so chunks can break between them.
    static let splitWords = 120

    static func partInstructions(for template: SummaryTemplate, part: Int, of: Int) -> String {
        """
        You write detailed \(template.name.lowercased()) from part \(part) of \(of) of a speech-to-text \
        transcript. Each line starts with a speaker label. Expect missing punctuation and some misheard \
        words. Use only what the text says. Never add advice, opinions or general statements that are \
        not in the text. Keep every specific: names, companies, products, numbers, dates, prices, reasons \
        and disagreements. Say who said what with the speaker label.
        \(template.sections)
        """
    }

    static func headerInstructions(_ template: SummaryTemplate) -> String {
        """
        You write the title and overview of \(template.name.lowercased()) from its section headings and \
        key points. Use only what the text says.
        """
    }

    static func summarize(_ text: String, template: SummaryTemplate, date: Date, seconds: Double?) async throws -> String {
        if case .unavailable(let reason) = model.availability {
            throw AppError(message: describe(reason))
        }
        // Timestamps cost tokens and carry no meaning for a summary; speaker labels stay.
        let stripped = text.replacingOccurrences(of: #"(?m)^\[\d\d:\d\d:\d\d\] "#, with: "",
                                                 options: .regularExpression)
        let speakers = SummaryFormat.speakerNames(in: text)
        let material = SummaryFormat.splitTurns(stripped, maxWords: splitWords)

        let context = model.contextSize
        let margin = max(64, context / 20)
        // Part 99 of 99 measures the longest the part instructions get.
        let partBudget = context
            - (try await model.tokenCount(for: Instructions(partInstructions(for: template, part: 99, of: 99))))
            - (try await model.tokenCount(for: GeneratedPart.generationSchema))
            - partReserve - margin
        let headerBudget = context
            - (try await model.tokenCount(for: Instructions(headerInstructions(template))))
            - (try await model.tokenCount(for: GeneratedHeader.generationSchema))
            - headerReserve - margin
        if partBudget < 200 || headerBudget < 200 {
            throw AppError(message: "Apple's on-device model has too little room to summarize on this Mac.")
        }

        let chunks = try await TokenChunker.split(material, budget: partBudget,
                                                  count: { try await model.tokenCount(for: $0) })
        if chunks.isEmpty { throw AppError(message: "There is no speech in the transcript to summarize.") }

        var parts: [SummaryPart] = []
        for (i, chunk) in chunks.enumerated() {
            parts += try await part(chunk, template: template, index: i + 1, of: chunks.count, budget: partBudget)
        }
        let merged = SummaryFormat.merge(parts, template: template)

        // The header sees the merged sections, with fewer points each until it fits.
        var title = "Recording summary"
        var overview = ""
        for n in [4, 3, 2, 1, 0] {
            let input = SummaryFormat.overviewInput(merged, pointsPerSection: n)
            if try await model.tokenCount(for: input) > headerBudget { continue }
            let session = LanguageModelSession(model: model, instructions: headerInstructions(template))
            do {
                let h = try await session.respond(to: input, generating: GeneratedHeader.self,
                                                  options: GenerationOptions(maximumResponseTokens: headerReserve)).content
                title = h.title
                overview = h.overview
                break
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                continue
            }
        }
        return SummaryFormat.render(title: title, overview: overview, merged: merged, template: template,
                                    date: date, seconds: seconds, speakers: speakers)
    }

    /// Sections and action items for one chunk. If the model still finds it too long,
    /// halves it and returns the halves' parts in order.
    private static func part(_ chunk: String, template: SummaryTemplate, index: Int, of count: Int,
                             budget: Int, depth: Int = 0) async throws -> [SummaryPart] {
        let session = LanguageModelSession(model: model,
                                           instructions: partInstructions(for: template, part: index, of: count))
        do {
            let g = try await session.respond(to: chunk, generating: GeneratedPart.self,
                                              options: GenerationOptions(maximumResponseTokens: partReserve)).content
            return [SummaryPart(
                sections: g.sections.map { SummarySection(heading: $0.heading, points: $0.points) },
                actions: g.actionItems.map { SummaryAction(owner: $0.owner, task: $0.task, due: $0.due) })]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where depth < 3 {
            let half = max(1, budget / 2)
            let halves = try await TokenChunker.split(chunk, budget: half,
                                                      count: { try await model.tokenCount(for: $0) })
            var out: [SummaryPart] = []
            for h in halves {
                out += try await part(h, template: template, index: index, of: count, budget: half, depth: depth + 1)
            }
            return out
        }
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is off. Turn it on in System Settings → Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple's on-device model is still downloading. Try again in a few minutes."
        case .deviceNotEligible:
            return "This Mac can't run Apple's on-device model."
        @unknown default:
            return "Apple's on-device model is not available."
        }
    }

    static func describe(_ error: Error) -> String {
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
            return "The transcript is too long for Apple's on-device model, even in parts."
        }
        return (error as? AppError)?.message ?? error.localizedDescription
    }
}
