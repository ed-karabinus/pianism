import AppIntents
import PianismGlance
import SwiftUI
import WidgetKit

/// The widget extension (ADR 0010): the small widget showing today's practice, and the running session as a Live
/// Activity.
@main
struct PianismWidgets: WidgetBundle {
    var body: some Widget {
        PracticeWidget()
        PracticeLiveActivity()
    }
}

/// Where the widget's intents live, for Xcode's metadata processor (ADR 0010).
struct PianismWidgetsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [PianismGlanceIntents.self] }
}
