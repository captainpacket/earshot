// Window layout (2026-11-23): the "Set up Earshot" card sat above Home's ScrollView, so the split view
// measured its text at a near-zero width, asked for ~1,774 pt of height, and was laid out 1,722 pt tall
// in a 705 pt window: both columns slid up under the title bar. This hosts a real NavigationSplitView in
// a real NSWindow, with the card showing, and checks the split view fits the window.
// RenderUI cannot catch this: it draws a fake window with a plain HStack. Written before the fix.
// Run: bash EarshotApp/Tests/run.sh
import SwiftUI
import AppKit

var failures = 0
var checks = 0
func checkTrue(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    print(ok ? "PASS" : "FAIL", name); if !ok { failures += 1; let d = detail(); if !d.isEmpty { print("   ", d) } }
}

/// The card as a new user without Accessibility sees it: microphone allowed, Dictation waiting.
func card() -> some View {
    SetupCard(checklist: SetupChecklist(microphone: .allowed, dictationEnabled: true,
                                        accessibilityTrusted: false, dictationSkipped: false),
              onAllowMicrophone: {}, onOpenMicrophoneSettings: {}, onTurnOnDictation: {},
              onOpenAccessibilitySettings: {}, onSkipDictation: {})
}

let items = (0..<50).map {
    HomeItem(id: "\($0)", date: Date().addingTimeInterval(Double(-$0) * 7200), title: "Recording \($0)",
             detail: "transcribed · summarized", state: .done)
}

/// The window's structure from ContentView: sidebar, detail of a top bar over the section's content,
/// and the scene's minimum size.
struct Shell<Detail: View>: View {
    let detail: Detail
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) { Text("Earshot").font(.headline); Text("Home"); Spacer() }
                .padding(12)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                Text("Top bar").frame(height: 52)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Earshot")
        .frame(minWidth: 1180, minHeight: 560)
    }
}

struct Measured { var content: NSSize; var fitting: NSSize; var split: NSRect? }

@MainActor func measure<V: View>(_ view: V, width: CGFloat = 1268, height: CGFloat) -> Measured {
    let host = NSHostingView(rootView: view)
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.contentView = host
    w.setContentSize(NSSize(width: width, height: height))
    w.orderFront(nil)
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    func split(in v: NSView) -> NSView? {
        if v is NSSplitView { return v }
        for s in v.subviews { if let f = split(in: s) { return f } }
        return nil
    }
    let m = Measured(content: host.bounds.size, fitting: host.fittingSize,
                     split: split(in: host).map { $0.convert($0.bounds, to: host) })
    w.orderOut(nil)
    return m
}

func fits(_ m: Measured) -> Bool {
    guard let s = m.split else { return false }
    return abs(s.minY) < 1 && abs(s.height - m.content.height) < 1 && m.fitting.height <= m.content.height + 1
}

@main struct WindowLayoutTests {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)

        // Control: the old layout, card stacked above Home's ScrollView, must be caught by this test.
        let old = measure(Shell(detail: VStack(spacing: 0) {
            card().padding(.horizontal, 28)
            HomeView(items: items, onOpen: { _ in })
        }), height: 705)
        checkTrue("a split view was found to measure", old.split != nil)
        checkTrue("control: the card above the ScrollView overflows the window (the 2026-11-23 bug)", !fits(old),
                  "\(old)")

        // Home with the card as its header, inside its ScrollView, at the heights the owner used.
        for h in [560.0, 705.0, 1410.0] {
            let m = measure(Shell(detail: HomeView(items: items, onOpen: { _ in }, header: AnyView(card()))), height: h)
            checkTrue("card in Home's header: split view fills a \(Int(h)) pt window exactly", fits(m), "\(m)")
        }
        // No header, as when setup is done.
        let plain = measure(Shell(detail: HomeView(items: items, onOpen: { _ in })), height: 705)
        checkTrue("Home without a header still fits", fits(plain), "\(plain)")
        // The narrowest window the scene allows.
        let narrow = measure(Shell(detail: HomeView(items: items, onOpen: { _ in }, header: AnyView(card()))),
                             width: 1180, height: 560)
        checkTrue("card in Home's header fits the minimum 1180x560 window", fits(narrow), "\(narrow)")

        let minimum = 7
        print("\(checks) checks, \(failures) failed")
        if checks < minimum { print("VACUOUS: fewer than \(minimum) checks ran"); exit(1) }
        exit(failures == 0 ? 0 : 1)
    }
}
