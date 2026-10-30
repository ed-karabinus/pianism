import Charts
import PianismCore
import SwiftUI

/// A week at a glance, atop History: its total, a bar for each day's practice, and, a tap away, the time with each
/// piece and skill (HIS-2). It shows this week, and earlier ones with a swipe or the arrows.
struct WeekView: View {
    let model: HistoryModel
    /// Shows the sessions of a tapped day with practice.
    let showDay: (Date) -> Void

    /// Room for the bars as the axis labels grow with the text size, short enough to leave the sessions on screen
    /// (decided with Ed, 2026-10-29).
    @ScaledMetric private var height: CGFloat = 100
    /// Wide enough for either icon at any text size, so every name lines up, even with no icon.
    @ScaledMetric private var iconWidth: CGFloat = 24
    /// Closed at first, so the sessions stay on screen, then as it was left (decided with Ed, 2026-10-29).
    @AppStorage("showsWeekByTag") private var showsByTag = false
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
            // A tap anywhere in a day's column, not just on its bar, which can be short (decided with Ed, 2026-10-29).
            .chartGesture { chart in
                SpatialTapGesture().onEnded { tap in
                    if let date = chart.value(atX: tap.location.x, as: Date.self),
                        let day = model.dayWithPractice(at: date)
                    {
                        showDay(day)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.historyWeekChart)
            // Untagged time alone would only repeat the week's total.
            if tagTimes.contains(where: { $0.tag != nil }) {
                DisclosureGroup(isExpanded: $showsByTag) {
                    ForEach(tagTimes, content: row)
                } label: {
                    // The identifier goes on the label: set on the group, it would reach every row.
                    Text("By piece and skill", bundle: .module).accessibilityIdentifier(
                        AccessibilityID.historyWeekByTag)
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
            if showsByTag && tagTimes.reduce(0, { $0 + $1.time }) > week.total {
                Text("A session counts toward each of its tags.", bundle: .module)
            }
        }
    }

    private var week: PracticeWeek { model.week }
    private var tagTimes: [PracticeWeek.TagTime] { week.timeByTag(in: model.tagIndex) }

    /// A tag's time, marked as a piece or a skill, as a piece and a skill can share a name.
    private func row(_ tagTime: PracticeWeek.TagTime) -> some View {
        let title = Text(tags: tagTime.tag.map { [$0] } ?? [])
        let kind: (icon: String, name: Text)? =
            switch tagTime.tag?.kind {
            case .piece: ("music.note", Text("Piece", bundle: .module))
            case .skill: ("hand.raised", Text("Skill", bundle: .module))
            case nil: nil
            }
        return HStack {
            Image(systemName: kind?.icon ?? "music.note")
                .foregroundStyle(.secondary)
                .opacity(kind == nil ? 0 : 1)
                .frame(width: iconWidth)
            TimedRow(title: title, duration: tagTime.time)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.map { Text("\(title), \($0.name)", bundle: .module) } ?? title)
        .accessibilityValue(ElapsedTime.spoken(tagTime.time))
        .accessibilityIdentifier(AccessibilityID.historyWeekTag)
    }

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
