import PianismCore
import SwiftUI

/// The History screen: finished sessions grouped by day, newest first, with each day's total (HIS-1).
struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("History", bundle: .module))
        }
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var content: some View {
        if model.days.isEmpty, model.loadFailed {
            ContentUnavailableView(
                LocalizedStringResource("Couldn't load your history", bundle: .module),
                systemImage: "exclamationmark.triangle",
                description: Text("Restart Pianism to try again.", bundle: .module)
            )
            .accessibilityIdentifier(AccessibilityID.historyUnavailable)
        } else if model.days.isEmpty {
            ContentUnavailableView(
                LocalizedStringResource("No practice yet", bundle: .module), systemImage: "music.note.list",
                description: Text("Sessions you finish appear here.", bundle: .module)
            )
            .accessibilityIdentifier(AccessibilityID.historyEmpty)
        } else {
            List {
                if model.loadFailed {
                    Label(
                        LocalizedStringResource(
                            "Couldn't load your earlier history. Sessions waiting to be saved are shown.",
                            bundle: .module),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.historyUnavailable)
                }
                ForEach(model.days) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            let times = (session.startedAt..<(session.endedAt ?? session.startedAt))
                                .formatted(.interval.hour().minute())
                            let title =
                                model.waitingIDs.contains(session.id)
                                ? Text("\(times), not saved yet", bundle: .module) : Text(times)
                            // A finished session's practice time is fixed, so the date passed here is ignored.
                            TimedRow(title: title, duration: session.elapsed(at: .distantPast))
                                .accessibilityIdentifier(AccessibilityID.historySession)
                        }
                    } header: {
                        TimedRow(title: title(for: day), duration: day.total)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(AccessibilityID.historyDay)
                    }
                }
            }
        }
    }

    /// "Today", "Yesterday", or the date, such as "Wednesday, October 14".
    private func title(for day: PracticeDay) -> Text {
        if model.calendar.isDate(day.start, inSameDayAs: model.now) {
            return Text("Today", bundle: .module)
        }
        if let yesterday = model.calendar.date(byAdding: .day, value: -1, to: model.now),
            model.calendar.isDate(day.start, inSameDayAs: yesterday)
        {
            return Text("Yesterday", bundle: .module)
        }
        return Text(day.start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }
}

/// A title with a practice time after it, read by VoiceOver as one element: a day's header or a session.
private struct TimedRow: View {
    let title: Text
    let duration: TimeInterval

    var body: some View {
        LabeledContent {
            Text(ElapsedTime.display(duration)).monospacedDigit()
        } label: {
            title
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(ElapsedTime.spoken(duration))
    }
}

#Preview("Some practice, dark, AX5") {
    HistoryView(model: .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Empty") {
    HistoryView(model: .preview(empty: true))
}

#Preview("History couldn't load, sessions waiting") {
    HistoryView(model: .preview(waiting: true))
}
