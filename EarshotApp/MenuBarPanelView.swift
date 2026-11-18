// The panel that opens from the menu bar, restyled to match the main window (ADR-2611072100 B4).
// Plain values and closures only, so the render harness can draw it.
import SwiftUI
import AppKit

struct MenuBarRecent: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
}

struct MenuBarPanelView: View {
    let icon: AnyView
    let recordingSince: Date?
    let micName: String?
    let level: () -> Float
    /// Seconds left before a quiet recording stops by itself, or nil.
    let endingIn: Int?
    let recent: [MenuBarRecent]
    let version: String
    /// The Retry last dictation button, when there is one.
    let extra: AnyView?
    let onRecord: () -> Void
    let onKeepRecording: () -> Void
    let onOpen: (String?) -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                icon
                Text("Earshot").font(.headline)
                Spacer(minLength: 8)
                Label("On this Mac", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRecord) {
                HStack(spacing: 8) {
                    if let start = recordingSince {
                        Image(systemName: "stop.fill")
                        TimelineView(.periodic(from: start, by: 1)) { ctx in
                            Text("Stop  " + Self.elapsed(from: start, to: ctx.date)).monospacedDigit()
                        }
                    } else {
                        Image(systemName: "record.circle")
                        Text("Record")
                    }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordingSince != nil ? Color.red : Color.brandAccent)
            .controlSize(.large)

            if let extra { extra }

            if recordingSince != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(micName ?? "Microphone", systemImage: "mic")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    TimelineView(.animation(minimumInterval: 0.08)) { _ in
                        PanelLevel(decibels: level())
                    }
                    if let s = endingIn {
                        Label("No one has spoken for a while. Stopping in \(s) s.", systemImage: "hourglass")
                            .font(.callout)
                            .foregroundStyle(Color.brandWarningText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Keep Recording", action: onKeepRecording)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card)
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(recent.prefix(5).enumerated()), id: \.element.id) { index, r in
                            if index > 0 { Divider() }
                            Button { onOpen(r.id) } label: {
                                HStack(spacing: 10) {
                                    Text(r.title).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 8)
                                    Text(Self.time(r.date))
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(card)
                }
            }

            HStack(spacing: 12) {
                Button("Open Earshot") { onOpen(nil) }
                Spacer(minLength: 8)
                Button("Settings…", action: onSettings)
                Button("Quit", action: onQuit)
            }
            .buttonStyle(.borderless)

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }

    /// "12:30 PM" with ordinary spaces, so it never wraps between the time and PM.
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The microphone level as a full-width bar: green, then amber, then red when it is too loud.
private struct PanelLevel: View {
    let decibels: Float

    var body: some View {
        let fill = CGFloat(max(0, min(1, (decibels + 60) / 60)))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(fill > 0.9 ? Color.red : fill > 0.7 ? Color.brandWarning : Color.green)
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(height: 6)
    }
}
