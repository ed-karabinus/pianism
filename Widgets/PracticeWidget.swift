import PianismCore
import PianismGlance
import PianismPersistence
import SwiftUI
import WidgetKit

/// The small Home Screen widget: today's practice (GLN-2).
struct PracticeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.practice, provider: PracticeProvider()) { entry in
            PracticeWidgetView(practiced: entry.practiced)
        }
        .configurationDisplayName("Practice")
        .description("Today's practice time.")
        .supportedFamilies([.systemSmall])
    }
}

struct PracticeEntry: TimelineEntry {
    let date: Date
    /// Today's practice as of `date`.
    let practiced: TimeInterval
}

/// Reads the two App Group files the app writes: the running session (ADR 0003) and the day's finished practice
/// (ADR 0010). The extension's composition root, so the system clock is read here, and the rule is the core's (E3).
struct PracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PracticeEntry {
        PracticeEntry(date: .now, practiced: 25 * 60)
    }

    func getSnapshot(in context: Context, completion: @escaping (PracticeEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Now, and the next local midnight, when the total starts over at 0 with no process running.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PracticeEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        var entries = [entry(at: now)]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(entry(at: midnight))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> PracticeEntry {
        let running = try? FileRunningSessionStore(appGroup: AppGroup.identifier)?.current()
        let totals = FilePracticeTotals(appGroup: AppGroup.identifier)?.read()
        let practiced = totals?.today(at: date, running: running, in: .autoupdatingCurrent)
        return PracticeEntry(date: date, practiced: practiced ?? 0)
    }
}

struct PracticeWidgetView: View {
    let practiced: TimeInterval

    var body: some View {
        VStack(alignment: .leading) {
            Label("Today", systemImage: "pianokeys")
                .font(.headline)
            Spacer()
            Text(duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                .font(.title.bold())
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today")
        .accessibilityValue(
            duration.formatted(.units(allowed: [.hours, .minutes], width: .wide)))
    }

    /// Whole minutes, rounded down as the app's clock is, so the widget never shows more than was practiced.
    private var duration: Duration {
        .seconds(Int(practiced / 60) * 60)
    }
}

#Preview("Nothing yet", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, practiced: 0)
}

#Preview("25 minutes", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, practiced: 25 * 60)
}

#Preview("2 hours 5 minutes", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, practiced: 2 * 60 * 60 + 5 * 60)
}

// The widget previews above take no modifiers, so dark and AX5 preview the view in a small widget's frame.
#Preview("2 hours 5 minutes, dark, AX5") {
    PracticeWidgetView(practiced: 2 * 60 * 60 + 5 * 60)
        .frame(width: 158, height: 158)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
