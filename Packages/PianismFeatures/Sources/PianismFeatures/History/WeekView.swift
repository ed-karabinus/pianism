import Charts
import PianismCore
import SwiftUI

/// A week at a glance, atop History: its total, a bar for each day's practice, and the time with each piece and
/// skill (HIS-2). It shows this week, and earlier ones with a swipe or the arrows.
struct WeekView: View {
    let model: HistoryModel

    /// Room for the bars as the axis labels grow with the text size.
    @ScaledMetric private var height: CGFloat = 140
    @Environment(\.layoutDirection) private var layoutDirection

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
            // Alongside the list's scrolling, and only for a mostly sideways swipe: toward the later days, which are on
            // the left in right-to-left languages, as the chart mirrors.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { drag in
                    guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    model.showWeek(earlier: (drag.translation.width > 0) == (layoutDirection == .leftToRight))
                }
            )
            .accessibilityIdentifier(AccessibilityID.historyWeekChart)
            // Untagged time alone would only repeat the week's total.
            if tagTimes.contains(where: { $0.tag != nil }) {
                ForEach(tagTimes) { tagTime in
                    TimedRow(title: Text(tags: tagTime.tag.map { [$0] } ?? []), duration: tagTime.time)
                        .accessibilityIdentifier(AccessibilityID.historyWeekTag)
                }
            }
        } header: {
            HStack {
                Button(LocalizedStringResource("Earlier week", bundle: .module), systemImage: "chevron.backward") {
                    model.showWeek(earlier: true)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!model.canShowEarlierWeek)
                .accessibilityIdentifier(AccessibilityID.historyWeekEarlier)
                TimedRow(title: title, duration: week.total)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.historyWeek)
                Button(LocalizedStringResource("Later week", bundle: .module), systemImage: "chevron.forward") {
                    model.showWeek(earlier: false)
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(model.pickedWeek == nil)
                .accessibilityIdentifier(AccessibilityID.historyWeekLater)
            }
            .labelStyle(.iconOnly)
        } footer: {
            // So times that add up to more than the week's don't read as a mistake.
            if tagTimes.reduce(0, { $0 + $1.time }) > week.total {
                Text("A session counts toward each of its tags.", bundle: .module)
            }
        }
    }

    private var week: PracticeWeek { model.week }
    private var tagTimes: [PracticeWeek.TagTime] { week.timeByTag(in: model.tagIndex) }

    /// "This week", "Last week", or the week's dates, such as "Oct 5 – 11", with the year if it isn't this one.
    private var title: Text {
        let calendar = model.calendar
        let start = week.days[0].start
        switch calendar.dateComponents([.weekOfYear], from: start, to: model.now).weekOfYear {
        case 0: return Text("This week", bundle: .module)
        case 1: return Text("Last week", bundle: .module)
        default:
            let dates = Date.IntervalFormatStyle.interval.month(.abbreviated).day()
            let style = calendar.isDate(start, equalTo: model.now, toGranularity: .year) ? dates : dates.year()
            return Text((start..<week.days[6].start).formatted(style))
        }
    }
}
