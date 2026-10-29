import Charts
import PianismCore
import SwiftUI

/// This week at a glance, atop History: its total, a bar for each day's practice, and the time with each piece and
/// skill (HIS-2).
struct WeekView: View {
    let week: PracticeWeek
    let tags: TagIndex

    /// Room for the bars as the axis labels grow with the text size.
    @ScaledMetric private var height: CGFloat = 140

    var body: some View {
        Section {
            Chart(week.days) { day in
                BarMark(
                    x: .value(Text("Day", bundle: .module), day.start, unit: .day),
                    y: .value(Text("Minutes", bundle: .module), day.total / 60)
                )
                .accessibilityLabel(day.start.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(ElapsedTime.spoken(day.total))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxisLabel { Text("Minutes", bundle: .module) }
            .frame(height: height)
            // Untagged time alone would only repeat the week's total.
            if tagTimes.contains(where: { $0.tag != nil }) {
                ForEach(tagTimes) { tagTime in
                    TimedRow(title: Text(tags: tagTime.tag.map { [$0] } ?? []), duration: tagTime.time)
                        .accessibilityIdentifier(AccessibilityID.historyWeekTag)
                }
            }
        } header: {
            TimedRow(title: Text("This week", bundle: .module), duration: week.total)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.historyWeek)
        } footer: {
            // So times that add up to more than the week's don't read as a mistake.
            if tagTimes.reduce(0, { $0 + $1.time }) > week.total {
                Text("A session counts toward each of its tags.", bundle: .module)
            }
        }
    }

    private var tagTimes: [PracticeWeek.TagTime] { week.timeByTag(in: tags) }
}
