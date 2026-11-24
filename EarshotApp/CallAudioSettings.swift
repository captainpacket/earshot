// Settings → Recording → Call audio (ADR-2611240900). Shown only where a Core Audio tap exists (macOS 14.2+).
import AppKit
import SwiftUI

struct CallAudioSettingsRows: View {
    @AppStorage(CallAudioPrefs.source) private var stored = ""
    @State private var apps: [(id: String, name: String)] = []
    @State private var permission = CallAudioPrefs.permission

    private var source: CallAudioSource {
        stored == "all" ? .allSystem : stored.hasPrefix("app:") ? .app(String(stored.dropFirst(4))) : .none
    }

    var body: some View {
        if CallAudioRules.settingVisible(osSupportsTap: CoreAudioTap.isSupported) {
            Group {
                SettingsRow("Record the other side from",
                            detail: "Adds the sound a call plays to your recording, from every app or from one. It can include other people's voices, so tell them, and only record where that is allowed. The audio stays on this Mac.") {
                    Picker("", selection: $stored) {
                        Text("None").tag("")
                        Text("All system audio").tag("all")
                        if !apps.isEmpty { Divider() }
                        ForEach(apps, id: \.id) { Text($0.name).tag("app:\($0.id)") }
                        if stored.hasPrefix("app:"), !apps.contains(where: { "app:\($0.id)" == stored }) {
                            Text("Chosen app (not running)").tag(stored)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                switch CallAudioRules.cardAction(source: source, permission: permission, osSupportsTap: CoreAudioTap.isSupported) {
                case .openSettings:
                    SettingsRow("Permission", detail: "macOS did not allow Earshot to record system audio. Allow it in Privacy & Security → Screen & System Audio Recording.") {
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                case .allow:
                    SettingsRow("Permission", detail: "macOS asks the first time Earshot records a call with this on.") { EmptyView() }
                case .none:
                    EmptyView()
                }
            }
            .onAppear { apps = CoreAudioTap.runningApps(); permission = CallAudioPrefs.permission }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                apps = CoreAudioTap.runningApps(); permission = CallAudioPrefs.permission
            }
        }
    }
}
