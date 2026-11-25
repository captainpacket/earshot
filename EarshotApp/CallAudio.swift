// Stub for the red commit (ADR-2611241100, ADR-2611241200): compiles, decides nothing.
import Foundation

enum CallAudioSource: Equatable {
    case none, allSystem, device(String)
    static func read(_ stored: String) -> CallAudioSource { .allSystem }
    var stored: String { "" }
}
enum CaptureMode: Equatable { case dictation, notes, recordings }
enum CallAudioPermission: Equatable { case notAsked, granted, refused }
enum TapPlan: Equatable { case none, allSystem, device(String) }
struct CallAudioContext: Equatable {
    var mode: CaptureMode; var source: CallAudioSource; var osSupportsTap: Bool
    var permission: CallAudioPermission; var availableDevices: Set<String>
}
struct CallAudioDecision: Equatable { var tap: TapPlan; var message: String? }
struct CallAudioOption: Equatable { var id: String; var name: String }
enum CallAudioRules {
    static let defaultSource: CallAudioSource = .allSystem
    static let stopWhenQuietDetail = ""
    static func options(inputs: [(id: String, name: String)], microphoneID: String, defaultMicrophoneID: String?, osSupportsTap: Bool) -> [CallAudioOption] { [] }
    static func effectiveSource(stored: String, microphoneID: String, defaultMicrophoneID: String?) -> CallAudioSource { .allSystem }
    static func shouldAskPermission(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> Bool { true }
    enum CardAction: Equatable { case allow, openSettings, none }
    static func cardAction(source: CallAudioSource, permission: CallAudioPermission, osSupportsTap: Bool) -> CardAction { .allow }
    static func decide(_ c: CallAudioContext) -> CallAudioDecision { .init(tap: .none, message: nil) }
}
enum CallAudioActivity {
    static func fed(mic: Float?, call: Float?) -> Float? { mic }
    static func callPlaying(call: Float?, threshold: Float) -> Bool { false }
}
protocol CallAudioTap: AnyObject {
    var level: Float? { get }
    func start(_ plan: TapPlan) throws
    func stop()
    func finish() -> AudioSignal
}
final class CallAudioSession {
    private(set) var decision = CallAudioDecision(tap: .none, message: nil)
    private(set) var tapRunning = false
    init(tap: CallAudioTap) {}
    func begin(_ context: CallAudioContext) {}
    func deviceLost(_ id: String) {}
    func end() {}
}
struct AudioSignal: Equatable { var samples: [Float]; var sampleRate: Double; var channels: Int }
enum CallAudioMix {
    static let outputRate = 16_000.0
    static func mix(mic: AudioSignal, tap: AudioSignal) -> [Float] { [] }
}
