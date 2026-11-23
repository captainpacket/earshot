// Earshot's home screen: greeting, status cards, filterable day-grouped feed, floating record bar,
// and the sidebar status card. Pure SwiftUI + AppKit colors; no dependency on Library or the app.
import SwiftUI
import AppKit

struct HomeItem: Identifiable, Equatable {
    enum State: Equatable {
        case done
        case working
        case failed(String)
    }

    let id: String
    var date: Date
    var title: String
    var detail: String
    var state: State
    /// Buttons shown under the row, so a failed or untranscribed recording has a visible next step.
    var actions: [HomeAction] = []
}

/// A button on a Home row (ADR-2611072100 B1).
struct HomeAction: Identifiable, Equatable {
    enum Step: Equatable { case transcribe, speakers, summary }
    enum Kind: Equatable {
        case transcribe
        case retry(Step)
        case trash
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .transcribe: return "transcribe"
        case .retry(let step): return "retry-\(step)"
        case .trash: return "trash"
        }
    }

    var title: String {
        switch kind {
        case .transcribe: return "Transcribe"
        case .retry: return "Try Again"
        case .trash: return "Move to Trash"
        }
    }

    var destructive: Bool { kind == .trash }

    /// The buttons for a row. A failure retries the step that failed (transcription when there is no
    /// transcript to work from) and offers the Trash. A recording waiting for the models gets none: the
    /// download card above is its action.
    static func choices(hasTranscript: Bool, state: HomeItem.State, failedStep: Step?,
                        waitingForModels: Bool) -> [HomeAction] {
        if waitingForModels { return [] }
        switch state {
        case .working:
            return []
        case .failed:
            let step = hasTranscript ? (failedStep ?? .transcribe) : .transcribe
            return [HomeAction(kind: .retry(step)), HomeAction(kind: .trash)]
        case .done:
            return hasTranscript ? [] : [HomeAction(kind: .transcribe)]
        }
    }
}

struct HomeView: View {
    let items: [HomeItem]
    let onOpen: (String) -> Void
    var rowMenu: ((HomeItem) -> AnyView)? = nil
    var onAction: ((String, HomeAction.Kind) -> Void)? = nil
    /// Shown above the greeting, inside the ScrollView: the setup cards. Outside it, their wrapped text
    /// set the window's minimum height and pushed both columns up under the title bar (1.5.3).
    let header: AnyView?

    private enum Filter { case all, errors }
    @State private var filter: Filter = .all

    init(items: [HomeItem], onOpen: @escaping (String) -> Void, header: AnyView? = nil) {
        self.items = items
        self.onOpen = onOpen
        self.header = header
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var failedCount: Int {
        items.filter { if case .failed = $0.state { return true } else { return false } }.count
    }

    private var visibleItems: [HomeItem] {
        let base: [HomeItem]
        switch filter {
        case .all: base = items
        case .errors: base = items.filter { if case .failed = $0.state { return true } else { return false } }
        }
        return base.sorted { $0.date > $1.date }
    }

    private var groups: [(day: Date, items: [HomeItem])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: visibleItems) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { (day: $0, items: byDay[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            // The header sits in a stack with no spacing, so an empty one (setup done) adds no gap; a
            // header that shows something brings its own space below it.
            VStack(alignment: .leading, spacing: 0) {
            if let header { header }
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting).font(.largeTitle.bold())
                    Text("Press Record, or drop an audio or video file here. Everything stays on this Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    pill("All · \(items.count)", selected: filter == .all) { filter = .all }
                    if failedCount > 0 {
                        pill("Errors · \(failedCount)", selected: filter == .errors) { filter = .errors }
                    }
                }

                if items.isEmpty {
                    Text("Nothing here yet. Press Record to start.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.day) { groupIndex, group in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(dayTitle(group.day))
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, groupIndex > 0 ? 18 : 0)
                                    .padding(.bottom, 4)
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider() }
                                    row(item)
                                }
                            }
                        }
                    }
                }
            }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 130)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .allowsHitTesting(false)
        }
        .onChange(of: failedCount) { _, count in
            if count == 0 { filter = .all }
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color.brandAccentText : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(selected ? Color.brandAccent.opacity(0.22) : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: HomeItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rowMain(item)
            if !item.actions.isEmpty, let onAction {
                // Outside the row's own button, so each click goes to its button and not to Open.
                HStack(spacing: 8) {
                    ForEach(item.actions) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            onAction(item.id, action.kind)
                        } label: {
                            Text(action.title).lineLimit(1).fixedSize()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(action.destructive ? nil : Color.brandAccent)
                    }
                }
                .padding(.leading, 96)  // under the title, past the time column
                .padding(.bottom, 10)
            }
        }
    }

    private func rowMain(_ item: HomeItem) -> some View {
        let failed: String? = { if case .failed(let m) = item.state { return m } else { return nil } }()
        return Button { onOpen(item.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(item.date.formatted(date: .omitted, time: .shortened)
                        .replacingOccurrences(of: "\u{202F}", with: " ")
                        .replacingOccurrences(of: "\u{00A0}", with: " "))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(failed != nil ? .body.weight(.semibold) : .body)
                        .foregroundStyle(failed != nil ? Color.brandWarningText : Color.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(item.detail).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let failed {
                        Text(failed).font(.callout).foregroundStyle(Color.brandWarningText)
                            .lineLimit(nil)  // the whole reason: it is at most three lines of tool output
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if item.state == .working {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { if let rowMenu { rowMenu(item) } }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
    }
}

struct RecordBar: View {
    let recordingSince: Date?
    let onRecord: () -> Void
    let onImport: () -> Void

    init(recordingSince: Date?, onRecord: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.recordingSince = recordingSince
        self.onRecord = onRecord
        self.onImport = onImport
    }

    var body: some View {
        HStack(spacing: 28) {
            Button(action: onImport) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down").font(.title3)
                    Text("Import").font(.callout)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Button(action: onRecord) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 56, height: 56)
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 56, height: 56)
                        if recordingSince != nil {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: 18, height: 18)
                        } else {
                            Circle().fill(Color.white).frame(width: 18, height: 18)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                if let since = recordingSince {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.elapsed(from: since, to: context.date))
                            .font(.callout.monospacedDigit())
                    }
                }
            }

            VStack(spacing: 3) {
                Text("⌘R").font(.callout).foregroundStyle(.secondary)
                Text(recordingSince != nil ? "Stop" : "Record").font(.callout)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct SidebarStatusCard: View {
    let ready: Bool
    let detail: String

    init(ready: Bool, detail: String) {
        self.ready = ready
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(ready ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(ready ? "Ready · on this Mac" : "Recording")
                    .font(.callout.weight(.semibold))
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}
