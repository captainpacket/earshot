// Call-audio source for recordings (ADR-2611240900). Pure: no Core Audio, no AVFoundation, no I/O.
// The Core Audio process tap is a driven adapter behind `CallAudioTap`; this file only decides and mixes.
import Foundation

enum CallAudioSource: Equatable { case none, allSystem, app(String) }

/// Which function is capturing. Only `.recordings` can ever cause a tap.
enum CaptureMode: Equatable { case dictation, notes, recordings }

enum CallAudioPermission: Equatable { case notAsked, granted, refused }

enum TapPlan: Equatable { case none, allSystem, app(String) }

struct CallAudioContext: Equatable {
    var mode: CaptureMode
    var source: CallAudioSource
    var osSupportsTap: Bool
    var permission: CallAudioPermission
    var runningApps: Set<String>
}

struct CallAudioDecision: Equatable {
    var tap: TapPlan
    var message: String?
}

enum CallAudioRules {
    /// The setting is shown only where a tap can exist (macOS 14.2 and later).
    static func settingVisible(osSupportsTap: Bool) -> Bool { osSupportsTap }
    static let choices: [String] = ["None", "All system audio", "One app"]
    static let defaultSource: CallAudioSource = .none

    /// Whether picking this source should ask for the permission now (never at launch, never for None).
    static func shouldAskPermission(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> Bool {
        osSupportsTap && source != .none && permission == .notAsked
    }

    /// What the permission card shows: Allow first, Open Settings once refused (ADR-2611142200).
    enum CardAction: Equatable { case allow, openSettings, none }
    static func cardAction(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> CardAction {
        guard osSupportsTap, source != .none else { return .none }
        switch permission { case .notAsked: return .allow; case .refused: return .openSettings; case .granted: return .none }
    }

    static func decide(_ c: CallAudioContext) -> CallAudioDecision {
        guard c.mode == .recordings, c.osSupportsTap, c.source != .none else { return .init(tap: .none, message: nil) }
        guard c.permission == .granted else {
            let why = c.permission == .refused
                ? "Call audio is not being recorded because permission was refused."
                : "Call audio is not being recorded because permission has not been given."
            return .init(tap: .none, message: why)
        }
        switch c.source {
        case .none: return .init(tap: .none, message: nil)
        case .allSystem: return .init(tap: .allSystem, message: nil)
        case .app(let id):
            guard !id.isEmpty, c.runningApps.contains(id) else {
                return .init(tap: .none, message: "No app is selected for call audio, so only the microphone is recorded.")
            }
            return .init(tap: .app(id), message: nil)
        }
    }
}

/// The driven port. The Core Audio adapter implements it; tests use a fake.
protocol CallAudioTap: AnyObject {
    func start(_ plan: TapPlan) throws
    func stop()
}

/// One recording's use of the tap: starts with Record, stops with Stop, ends if the chosen app quits.
final class CallAudioSession {
    private let tap: CallAudioTap
    private(set) var decision = CallAudioDecision(tap: .none, message: nil)
    private(set) var tapRunning = false
    init(tap: CallAudioTap) { self.tap = tap }

    func begin(_ context: CallAudioContext) {
        decision = CallAudioRules.decide(context)
        guard decision.tap != .none else { return }
        do { try tap.start(decision.tap); tapRunning = true }
        catch { decision.tap = .none; decision.message = "Call audio could not be started, so only the microphone is recorded." }
    }
    func appQuit(_ id: String) {
        if tapRunning, decision.tap == .app(id) { tap.stop(); tapRunning = false }
    }
    func end() { if tapRunning { tap.stop(); tapRunning = false } }
}

struct AudioSignal: Equatable {
    var samples: [Float]      // interleaved
    var sampleRate: Double
    var channels: Int
}

enum CallAudioMix {
    static let outputRate = 16_000.0
    /// Echo search window: a remote voice leaking from speakers into the mic arrives this late at most.
    static let maxEchoSeconds = 0.25

    static func mono16k(_ s: AudioSignal) -> [Float] {
        let ch = max(1, s.channels)
        guard !s.samples.isEmpty, s.sampleRate > 0 else { return [] }
        let frames = s.samples.count / ch
        guard frames > 0 else { return [] }
        var mono = [Float](repeating: 0, count: frames)
        for f in 0..<frames { var sum: Float = 0; for c in 0..<ch { sum += s.samples[f * ch + c] }; mono[f] = sum / Float(ch) }
        if s.sampleRate == outputRate { return mono }
        let outCount = Int((Double(frames) * outputRate / s.sampleRate).rounded())
        guard outCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let pos = Double(i) * s.sampleRate / outputRate
            let j = min(Int(pos), frames - 1), k = min(j + 1, frames - 1)
            let t = Float(pos - Double(j))
            out[i] = mono[j] * (1 - t) + mono[k] * t
        }
        return out
    }

    /// Removes the tap's voice from the mic when the mic only hears it again through the speakers
    /// (best single delay, least-squares gain), so the mix carries it once.
    static func removeEcho(mic: [Float], tap: [Float]) -> [Float] {
        let n = min(mic.count, tap.count)
        guard n > 1 else { return mic }
        let maxLag = min(Int(maxEchoSeconds * outputRate), n - 1)
        var best = (lag: 0, score: Float(0), gain: Float(0))
        for lag in 0...maxLag {
            var dot: Float = 0, energy: Float = 0
            for i in lag..<n { dot += mic[i] * tap[i - lag]; energy += tap[i - lag] * tap[i - lag] }
            guard energy > 1e-9 else { continue }
            let score = dot * dot / energy
            if score > best.score { best = (lag, score, dot / energy) }
        }
        guard best.gain > 0.05 else { return mic }
        var out = mic
        for i in best.lag..<n { out[i] -= best.gain * tap[i - best.lag] }
        return out
    }

    static func mix(mic: AudioSignal, tap: AudioSignal) -> [Float] {
        let m = mono16k(mic), t = mono16k(tap)
        let cleaned = removeEcho(mic: m, tap: t)
        var out = [Float](repeating: 0, count: max(m.count, t.count))
        for i in 0..<out.count { out[i] = (i < cleaned.count ? cleaned[i] : 0) + (i < t.count ? t[i] : 0) }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 1 { for i in 0..<out.count { out[i] /= peak } }
        return out
    }
}
