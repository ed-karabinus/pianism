import SwiftUI
import WidgetKit

/// The widget extension (ADR 0010): the small widget showing today's practice.
@main
struct PianismWidgets: WidgetBundle {
    var body: some Widget {
        PracticeWidget()
    }
}
