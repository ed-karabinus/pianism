import Charts
import PianismCore
import SwiftUI

/// This week at a glance, atop History: its total, and a bar for each day's practice (HIS-2).
struct WeekView: View {
    let week: PracticeWeek

    /// Room for the bars as the axis labels grow with the text size, short enough to leave the sessions on screen
    /// (decided with Ed, 2026-10-29).
    @ScaledMetric private var height: CGFloat = 100

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
        } header: {
            TimedRow(title: Text("This week", bundle: .module), duration: week.total)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.historyWeek)
        }
    }
}
