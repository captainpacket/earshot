// Stub for the red commit (ADR-2611240900): compiles, decides nothing, mixes nothing.
import Foundation

enum CallAudioSource: Equatable { case none, allSystem, app(String) }
enum CaptureMode: Equatable { case dictation, notes, recordings }
enum CallAudioPermission: Equatable { case notAsked, granted, refused }
enum TapPlan: Equatable { case none, allSystem, app(String) }
struct CallAudioContext: Equatable {
    var mode: CaptureMode; var source: CallAudioSource; var osSupportsTap: Bool
    var permission: CallAudioPermission; var runningApps: Set<String>
}
struct CallAudioDecision: Equatable { var tap: TapPlan; var message: String? }
enum CallAudioRules {
    static func settingVisible(osSupportsTap: Bool) -> Bool { false }
    static let choices: [String] = []
    static let defaultSource: CallAudioSource = .allSystem
    static func shouldAskPermission(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> Bool { true }
    enum CardAction: Equatable { case allow, openSettings, none }
    static func cardAction(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> CardAction { .none }
    static func decide(_ c: CallAudioContext) -> CallAudioDecision { .init(tap: .none, message: nil) }
}
protocol CallAudioTap: AnyObject { func start(_ plan: TapPlan) throws; func stop() }
final class CallAudioSession {
    private(set) var decision = CallAudioDecision(tap: .none, message: nil)
    private(set) var tapRunning = false
    init(tap: CallAudioTap) {}
    func begin(_ context: CallAudioContext) {}
    func appQuit(_ id: String) {}
    func end() {}
}
struct AudioSignal: Equatable { var samples: [Float]; var sampleRate: Double; var channels: Int }
enum CallAudioMix {
    static let outputRate = 16_000.0
    static func mix(mic: AudioSignal, tap: AudioSignal) -> [Float] { [] }
}
