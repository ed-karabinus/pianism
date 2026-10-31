import Charts
import PianismCore
import SwiftUI

/// This week at a glance, atop History: its total, a bar for each day's practice, and, a tap away, the time with each
/// piece and skill (HIS-2).
struct WeekView: View {
    let week: PracticeWeek
    let tags: TagIndex

    /// Room for the bars as the axis labels grow with the text size, short enough to leave the sessions on screen
    /// (decided with Ed, 2026-10-29).
    @ScaledMetric private var height: CGFloat = 100
    /// Wide enough for either icon at any text size, so every name lines up, even with no icon.
    @ScaledMetric private var iconWidth: CGFloat = 24
    /// Closed at first, so the sessions stay on screen, then as it was left (decided with Ed, 2026-10-29).
    @AppStorage("showsWeekByTag") private var showsByTag = false

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
                DisclosureGroup(isExpanded: $showsByTag) {
                    ForEach(tagTimes, content: row)
                } label: {
                    // The identifier goes on the label: set on the group, it would reach every row.
                    Text("By piece and skill", bundle: .module).accessibilityIdentifier(
                        AccessibilityID.historyWeekByTag)
                }
            }
        } header: {
            TimedRow(title: Text("This week", bundle: .module), duration: week.total)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.historyWeek)
        } footer: {
            // So times that add up to more than the week's don't read as a mistake.
            if showsByTag && tagTimes.reduce(0, { $0 + $1.time }) > week.total {
                Text("A session counts toward each of its tags.", bundle: .module)
            }
        }
    }

    private var tagTimes: [PracticeWeek.TagTime] { week.timeByTag(in: tags) }

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
}
