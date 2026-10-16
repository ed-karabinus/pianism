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
        if model.loadFailed {
            ContentUnavailableView {
                Label {
                    Text("Couldn't load your history", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            } description: {
                Text("Try again in a moment.", bundle: .module)
            }
        } else if model.days.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No practice yet", bundle: .module)
                } icon: {
                    Image(systemName: "music.note.list")
                }
            } description: {
                Text("Sessions you finish appear here.", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.historyEmpty)
        } else {
            List(model.days) { day in
                Section {
                    ForEach(day.sessions) { session in
                        SessionRow(session: session)
                    }
                } header: {
                    HStack {
                        title(for: day)
                        Spacer()
                        Text(ElapsedTime.display(day.total)).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title(for: day))
                    .accessibilityValue(ElapsedTime.spoken(day.total))
                    .accessibilityIdentifier(AccessibilityID.historyDay)
                }
            }
        }
    }

    /// "Today", "Yesterday", or the date, such as "Wednesday, October 14".
    private func title(for day: PracticeDay) -> Text {
        let now = model.clock.now
        if model.calendar.isDate(day.start, inSameDayAs: now) {
            return Text("Today", bundle: .module)
        }
        if let yesterday = model.calendar.date(byAdding: .day, value: -1, to: now),
            model.calendar.isDate(day.start, inSameDayAs: yesterday)
        {
            return Text("Yesterday", bundle: .module)
        }
        return Text(day.start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }
}

/// One finished session: when it ran, and how long was practice.
private struct SessionRow: View {
    let session: PracticeSession

    var body: some View {
        // A finished session's practice time is fixed, so the date passed here is ignored.
        let practiced = session.elapsed(at: .distantPast)
        let times = (session.startedAt..<(session.endedAt ?? session.startedAt)).formatted(.interval.hour().minute())
        HStack {
            Text(times)
            Spacer()
            Text(ElapsedTime.display(practiced)).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(times)
        .accessibilityValue(ElapsedTime.spoken(practiced))
        .accessibilityIdentifier(AccessibilityID.historySession)
    }
}

#Preview("Some practice") {
    HistoryView(model: .preview())
}

#Preview("Empty, dark, AX5") {
    HistoryView(model: .preview(empty: true))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
