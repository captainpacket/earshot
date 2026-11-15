// The first-launch "Set up Earshot" card (ADR-2611142200): microphone and Accessibility are asked for
// when Earshot is set up, not found later in System Settings. Plain values only, so it renders.
import SwiftUI
import AppKit

/// What each row of the setup card shows. Pure.
struct SetupChecklist: Equatable {
    enum Mic: Equatable { case notAsked, allowed, refused }
    enum Step: Equatable { case needed, waiting, done, refused, skipped }

    var microphone: Mic
    var dictationEnabled: Bool
    var accessibilityTrusted: Bool
    var dictationSkipped: Bool

    var microphoneStep: Step {
        switch microphone {
        case .notAsked: return .needed
        case .allowed: return .done
        case .refused: return .refused
        }
    }

    var dictationStep: Step {
        if accessibilityTrusted { return .done }
        if dictationEnabled { return .waiting }
        return dictationSkipped ? .skipped : .needed
    }

    /// The card stays until the microphone is allowed and Dictation is allowed or set aside.
    var showsCard: Bool {
        microphoneStep != .done || !(dictationStep == .done || dictationStep == .skipped)
    }
}

struct SetupCard: View {
    let checklist: SetupChecklist
    let onAllowMicrophone: () -> Void
    let onOpenMicrophoneSettings: () -> Void
    let onTurnOnDictation: () -> Void
    let onOpenAccessibilitySettings: () -> Void
    let onSkipDictation: () -> Void

    var body: some View {
        if checklist.showsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set up Earshot").font(.headline)
                VStack(spacing: 0) {
                    row(icon: "mic.fill", title: "Microphone",
                        detail: micDetail, step: checklist.microphoneStep) {
                        switch checklist.microphoneStep {
                        case .needed: Button("Allow", action: onAllowMicrophone).buttonStyle(.borderedProminent)
                        case .refused: Button("Open Settings", action: onOpenMicrophoneSettings).buttonStyle(.bordered)
                        default: EmptyView()
                        }
                    }
                    Divider()
                    row(icon: "keyboard", title: "Dictation",
                        detail: dictationDetail, step: checklist.dictationStep) {
                        switch checklist.dictationStep {
                        case .needed:
                            HStack(spacing: 8) {
                                Button("Not Now", action: onSkipDictation).buttonStyle(.bordered)
                                Button("Turn On", action: onTurnOnDictation).buttonStyle(.borderedProminent)
                            }
                        case .waiting:
                            Button("Open Settings", action: onOpenAccessibilitySettings).buttonStyle(.borderedProminent)
                        default: EmptyView()
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            }
            .tint(Color.brandAccent)
            .padding(16)
            .frame(maxWidth: 640, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var micDetail: String {
        switch checklist.microphoneStep {
        case .refused: return "macOS is blocking the microphone. Switch Earshot on in Privacy & Security → Microphone."
        case .done: return "Allowed."
        default: return "To record meetings and notes. The audio stays on this Mac."
        }
    }

    private var dictationDetail: String {
        switch checklist.dictationStep {
        case .waiting:
            return "Switch Earshot on in System Settings → Privacy & Security → Accessibility. This ticks itself when it's done."
        case .done: return "Allowed. Hold Control-Option-Space in any app and speak."
        default: return "Type with your voice in any app. macOS asks you to allow Accessibility so Earshot can type."
        }
    }

    private func row<Trailing: View>(icon: String, title: String, detail: String, step: SetupChecklist.Step,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        // Side by side when there is room; the buttons drop below the text in a narrow window.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                // A fixed ideal width, so ViewThatFits chooses this layout by the room it has,
                // not by the length of the text on one line.
                label(icon: icon, title: title, detail: detail, step: step)
                    .frame(minWidth: 240, idealWidth: 240, maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                trailing().fixedSize()
            }
            VStack(alignment: .leading, spacing: 10) {
                label(icon: icon, title: title, detail: detail, step: step)
                trailing().fixedSize().padding(.leading, 38)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func label(icon: String, title: String, detail: String, step: SetupChecklist.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step == .done ? "checkmark.circle.fill" : icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(step == .done ? Color.green : step == .refused ? Color.brandWarningText : Color.brandAccent)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(step == .refused ? Color.brandWarningText : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
